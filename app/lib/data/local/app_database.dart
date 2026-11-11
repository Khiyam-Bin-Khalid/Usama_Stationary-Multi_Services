import 'dart:convert';
import 'package:drift/drift.dart';
import '../models/sale.dart';
import 'tables.dart';
import 'connection/connection.dart' if (dart.library.js_interop) 'connection/connection_web.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [ProductsCache, PromotionsCache, PendingSales, PendingOps, SyncMeta, LocalSalesCache])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  /// Days of dated sales records kept on the device. The server keeps every
  /// sale permanently; this only bounds the local copy.
  static const recordDays = 31;

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(localSalesCache);
          }
          if (from < 3) {
            // Barcode + image reference cached so the offline POS shows the
            // same product photo/scan code as the online catalog.
            await m.addColumn(productsCache, productsCache.barcode);
            await m.addColumn(productsCache, productsCache.imageUrl);
          }
          if (from < 4) {
            // Offline product management + attributing queued sales.
            await m.createTable(pendingOps);
            await m.addColumn(productsCache, productsCache.description);
            await m.addColumn(pendingSales, pendingSales.cashierId);
            await m.addColumn(pendingSales, pendingSales.cashierName);
            // Cached rows have no description yet: re-pull the whole catalog.
            await (delete(syncMeta)..where((t) => t.key.equals('lastSync'))).go();
          }
        },
      );

  // --- Products ---

  Future<void> replaceProducts(List<ProductsCacheCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(productsCache, rows));
  }

  Future<List<ProductsCacheData>> allProducts() => select(productsCache).get();

  Stream<List<ProductsCacheData>> watchProducts({String? category}) {
    final query = select(productsCache)..where((t) => t.isActive.equals(true));
    if (category != null) query.where((t) => t.category.equals(category));
    return query.watch();
  }

  Future<void> upsertProduct(ProductsCacheCompanion row) => into(productsCache).insertOnConflictUpdate(row);

  Future<ProductsCacheData?> productById(String id) =>
      (select(productsCache)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<ProductsCacheData>> activeProducts() =>
      (select(productsCache)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Stream<List<ProductsCacheData>> watchActiveProducts() =>
      (select(productsCache)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<void> applyLocalStockDelta(String productId, num delta) async {
    final row = await (select(productsCache)..where((t) => t.id.equals(productId))).getSingleOrNull();
    if (row == null) return;
    await (update(productsCache)..where((t) => t.id.equals(productId)))
        .write(ProductsCacheCompanion(currentStock: Value(row.currentStock + delta.round())));
  }

  // --- Promotions ---

  Future<void> replacePromotions(List<PromotionsCacheCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(promotionsCache, rows));
  }

  Future<List<PromotionsCacheData>> activePromotions() async {
    final now = DateTime.now();
    return (select(promotionsCache)
          ..where((t) => t.startDate.isSmallerOrEqualValue(now) & t.endDate.isBiggerOrEqualValue(now)))
        .get();
  }

  // --- Pending (offline) sales ---

  Future<void> queueSale({
    required String clientTxnId,
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    required DateTime createdAt,
    String? cashierId,
    String? cashierName,
  }) {
    return into(pendingSales).insert(
      PendingSalesCompanion.insert(
        clientTxnId: clientTxnId,
        itemsJson: jsonEncode(items),
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        cashierId: Value(cashierId),
        cashierName: Value(cashierName),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<List<QueuedSale>> unsyncedSales() async {
    final rows = await (select(pendingSales)
          ..where((t) => t.synced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(QueuedSale.fromRow).toList();
  }

  Stream<List<QueuedSale>> watchUnsyncedSales() {
    final query = select(pendingSales)
      ..where((t) => t.synced.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(QueuedSale.fromRow).toList());
  }

  /// Sales plus product changes still waiting for the server.
  Stream<int> watchUnsyncedCount() => customSelect(
        'SELECT (SELECT COUNT(*) FROM pending_sales WHERE synced = 0) + (SELECT COUNT(*) FROM pending_ops) AS waiting',
        readsFrom: {pendingSales, pendingOps},
      ).watchSingle().map((row) => row.read<int>('waiting'));

  Future<void> markSynced(String clientTxnId) =>
      (update(pendingSales)..where((t) => t.clientTxnId.equals(clientTxnId)))
          .write(const PendingSalesCompanion(synced: Value(true)));

  Future<void> markSyncError(String clientTxnId, String error) =>
      (update(pendingSales)..where((t) => t.clientTxnId.equals(clientTxnId)))
          .write(PendingSalesCompanion(syncError: Value(error)));

  /// Clears a rejection so the next sync sends the sale again.
  Future<void> retrySale(String clientTxnId) =>
      (update(pendingSales)..where((t) => t.clientTxnId.equals(clientTxnId)))
          .write(const PendingSalesCompanion(syncError: Value(null)));

  /// Gives up on a sale the server rejected: removes it and puts its stock back.
  Future<void> discardSale(QueuedSale sale) => transaction(() async {
        for (final item in sale.items) {
          await applyLocalStockDelta((item['productId'] ?? item['product']) as String, item['quantity'] as num);
        }
        await (delete(pendingSales)..where((t) => t.clientTxnId.equals(sale.clientTxnId))).go();
        await (delete(localSalesCache)..where((t) => t.clientTxnId.equals(sale.clientTxnId))).go();
      });

  // --- Pending (offline) product changes ---

  Future<void> queueOp({
    required String opId,
    required String type,
    String? productId,
    required String label,
    Map<String, dynamic> payload = const {},
    Uint8List? imageBytes,
    String? imageName,
    String? lastError,
  }) {
    return into(pendingOps).insert(PendingOpsCompanion.insert(
      opId: opId,
      type: type,
      productId: Value(productId),
      label: label,
      payloadJson: jsonEncode(payload),
      imageBytes: Value(imageBytes),
      imageName: Value(imageName),
      createdAt: DateTime.now(),
      lastError: Value(lastError),
    ));
  }

  Future<List<PendingOp>> allPendingOps() => (select(pendingOps)..orderBy([(t) => OrderingTerm.asc(t.seq)])).get();

  Stream<List<PendingOp>> watchPendingOps() => (select(pendingOps)..orderBy([(t) => OrderingTerm.asc(t.seq)])).watch();

  Future<PendingOp?> pendingOpBySeq(int seq) => (select(pendingOps)..where((t) => t.seq.equals(seq))).getSingleOrNull();

  Future<void> removeOp(int seq) => (delete(pendingOps)..where((t) => t.seq.equals(seq))).go();

  Future<void> markOpError(int seq, String error) =>
      (update(pendingOps)..where((t) => t.seq.equals(seq))).write(PendingOpsCompanion(lastError: Value(error)));

  Future<void> retryOp(int seq) =>
      (update(pendingOps)..where((t) => t.seq.equals(seq))).write(const PendingOpsCompanion(lastError: Value(null)));

  /// Gives up on a product change. The optimistic local edit is undone by
  /// re-pulling the catalog from the server on the next sync.
  Future<void> discardOp(PendingOp op) => transaction(() async {
        if (op.type == 'product_create') {
          final id = op.productId!;
          final soldOffline = (await unsyncedSales()).any((s) => s.productIds.contains(id));
          final hasDependents = (await allPendingOps()).any((o) => o.seq != op.seq && o.productId == id);
          if (soldOffline || hasDependents) {
            throw StateError('This product has queued sales or changes. Discard those first.');
          }
          await (delete(productsCache)..where((t) => t.id.equals(id))).go();
        }
        await removeOp(op.seq);
        await (delete(syncMeta)..where((t) => t.key.equals('lastSync'))).go();
      });

  /// A product created offline got its real id: repoint everything queued
  /// against the temporary one and remember it for anything still holding the
  /// old id (an open screen, a cart). Local ids are UUIDs, so a plain text
  /// replacement inside the JSON blobs cannot hit anything else.
  Future<void> remapProductId(String localId, ProductsCacheCompanion serverRow) => transaction(() async {
        await (delete(productsCache)..where((t) => t.id.equals(localId))).go();
        await upsertProduct(serverRow);
        final realId = serverRow.id.value;
        await (update(pendingOps)..where((t) => t.productId.equals(localId)))
            .write(PendingOpsCompanion(productId: Value(realId)));
        final sales = await (select(pendingSales)..where((t) => t.synced.equals(false))).get();
        for (final row in sales.where((r) => r.itemsJson.contains(localId))) {
          await (update(pendingSales)..where((t) => t.clientTxnId.equals(row.clientTxnId)))
              .write(PendingSalesCompanion(itemsJson: Value(row.itemsJson.replaceAll(localId, realId))));
        }
        final local = await (select(localSalesCache)..where((t) => t.pending.equals(true))).get();
        for (final row in local.where((r) => r.saleJson.contains(localId))) {
          await (update(localSalesCache)..where((t) => t.clientTxnId.equals(row.clientTxnId)))
              .write(LocalSalesCacheCompanion(saleJson: Value(row.saleJson.replaceAll(localId, realId))));
        }
        await into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(key: 'remap:$localId', value: realId));
      });

  /// The real id of a product that was created offline, or [id] unchanged.
  Future<String> resolveProductId(String id) async {
    if (!isLocalProductId(id)) return id;
    final row = await (select(syncMeta)..where((t) => t.key.equals('remap:$id'))).getSingleOrNull();
    return row?.value ?? id;
  }

  // --- Local Sales Cache (offline Daily Sale view) ---

  /// Upsert a sale into the local mirror. [pending] is true for sales that
  /// were recorded offline and haven't been confirmed by the server yet.
  Future<void> upsertLocalSale(Sale sale, {bool pending = false}) {
    return into(localSalesCache).insertOnConflictUpdate(
      LocalSalesCacheCompanion.insert(
        clientTxnId: sale.clientTxnId,
        saleJson: jsonEncode(sale.toJson()),
        createdAt: sale.createdAt,
        pending: Value(pending),
      ),
    );
  }

  /// Called by SyncService after the server confirms a queued offline sale.
  Future<void> confirmLocalSale(String clientTxnId, Sale confirmedSale) {
    return (update(localSalesCache)..where((t) => t.clientTxnId.equals(clientTxnId)))
        .write(LocalSalesCacheCompanion(
          saleJson: Value(jsonEncode(confirmedSale.toJson())),
          createdAt: Value(confirmedSale.createdAt),
          pending: const Value(false),
        ));
  }

  /// Clears the pending flag when the server confirms a queued sale without
  /// echoing it back (the /sync/push response only carries the saleId).
  Future<void> markLocalSaleConfirmed(String clientTxnId) {
    return (update(localSalesCache)..where((t) => t.clientTxnId.equals(clientTxnId)))
        .write(const LocalSalesCacheCompanion(pending: Value(false)));
  }

  /// All local sales whose [createdAt] falls within [from..to].
  Future<List<Sale>> localSalesInRange(DateTime from, DateTime to) async => _decodeSales(await _salesInRange(from, to).get());

  Stream<List<Sale>> watchLocalSalesInRange(DateTime from, DateTime to) => _salesInRange(from, to).watch().map(_decodeSales);

  SimpleSelectStatement<$LocalSalesCacheTable, LocalSalesCacheData> _salesInRange(DateTime from, DateTime to) =>
      select(localSalesCache)
        ..where((t) => t.createdAt.isBiggerOrEqualValue(from) & t.createdAt.isSmallerOrEqualValue(to))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

  List<Sale> _decodeSales(List<LocalSalesCacheData> rows) => rows
      .map((r) => Sale.fromJson(jsonDecode(r.saleJson) as Map<String, dynamic>).withPendingSync(r.pending))
      .toList();

  /// Drops confirmed records older than [before]. Anything not yet on the
  /// server is kept however old it is: it may be the only copy.
  Future<void> pruneRecords(DateTime before) async {
    await (delete(localSalesCache)..where((t) => t.pending.equals(false) & t.createdAt.isSmallerThanValue(before))).go();
    await (delete(pendingSales)..where((t) => t.synced.equals(true) & t.createdAt.isSmallerThanValue(before))).go();
  }

  // --- Sync bookkeeping ---

  Future<DateTime?> lastSyncTime() async {
    final row = await (select(syncMeta)..where((t) => t.key.equals('lastSync'))).getSingleOrNull();
    if (row == null) return null;
    return DateTime.tryParse(row.value);
  }

  Future<void> setLastSyncTime(DateTime time) => into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion.insert(key: 'lastSync', value: time.toIso8601String()),
      );
}

const _localIdPrefix = 'local-';

/// Ids of products created offline, until the server assigns a real one.
bool isLocalProductId(String id) => id.startsWith(_localIdPrefix);
String newLocalProductId(String uuid) => '$_localIdPrefix$uuid';

/// Cache row for a product as the API (or [Product.toJson]) represents it.
ProductsCacheCompanion productCompanionFromJson(Map<String, dynamic> p) => ProductsCacheCompanion.insert(
      id: p['_id'] as String,
      name: p['name'] as String,
      sku: p['sku'] as String,
      barcode: Value(p['barcode'] as String?),
      imageUrl: Value(p['imageUrl'] as String?),
      description: Value(p['description'] as String?),
      category: p['category'] as String,
      unit: p['unit'] as String? ?? 'pcs',
      price: (p['price'] as num).toDouble(),
      costPrice: (p['costPrice'] as num?)?.toDouble() ?? 0,
      currentStock: (p['currentStock'] as num?)?.toInt() ?? 0,
      reorderThreshold: (p['reorderThreshold'] as num?)?.toInt() ?? 0,
      isMadeToOrder: p['isMadeToOrder'] as bool? ?? false,
      isAvailableOnline: p['isAvailableOnline'] as bool? ?? true,
      isActive: p['isActive'] as bool? ?? true,
      updatedAt: p['updatedAt'] == null ? DateTime.now() : DateTime.parse(p['updatedAt'] as String),
    );

/// Plain view of a queued offline sale, decoded from the itemsJson blob.
class QueuedSale {
  final String clientTxnId;
  final List<Map<String, dynamic>> items;
  final String paymentMethod;
  final DateTime createdAt;
  final String? cashierId;
  final String? cashierName;
  final String? syncError;

  const QueuedSale({
    required this.clientTxnId,
    required this.items,
    required this.paymentMethod,
    required this.createdAt,
    this.cashierId,
    this.cashierName,
    this.syncError,
  });

  factory QueuedSale.fromRow(PendingSale r) => QueuedSale(
        clientTxnId: r.clientTxnId,
        items: List<Map<String, dynamic>>.from(jsonDecode(r.itemsJson)),
        paymentMethod: r.paymentMethod,
        createdAt: r.createdAt,
        cashierId: r.cashierId,
        cashierName: r.cashierName,
        syncError: r.syncError,
      );

  // Rows queued before schema v4 used 'productId' here too; both map to the
  // 'product' key the API expects when pushed.
  List<String> get productIds => [for (final i in items) (i['productId'] ?? i['product']) as String];
  bool get waitsForProduct => productIds.any(isLocalProductId);
  double get total => items.fold(0, (sum, i) => sum + ((i['unitPrice'] as num?) ?? 0) * (i['quantity'] as num));
}
