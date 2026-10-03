import 'dart:convert';
import 'package:drift/drift.dart';
import '../models/sale.dart';
import 'tables.dart';
import 'connection/connection.dart' if (dart.library.js_interop) 'connection/connection_web.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [ProductsCache, PromotionsCache, PendingSales, SyncMeta, LocalSalesCache])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  @override
  int get schemaVersion => 3;

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
  }) {
    return into(pendingSales).insert(
      PendingSalesCompanion.insert(
        clientTxnId: clientTxnId,
        itemsJson: jsonEncode(items),
        paymentMethod: paymentMethod,
        createdAt: DateTime.now(),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<List<QueuedSale>> unsyncedSales() async {
    final rows = await (select(pendingSales)..where((t) => t.synced.equals(false))).get();
    return rows
        .map((r) => QueuedSale(
              clientTxnId: r.clientTxnId,
              items: List<Map<String, dynamic>>.from(jsonDecode(r.itemsJson)),
              paymentMethod: r.paymentMethod,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  Stream<int> watchUnsyncedCount() {
    final query = select(pendingSales)..where((t) => t.synced.equals(false));
    return query.watch().map((rows) => rows.length);
  }

  Future<void> markSynced(String clientTxnId) =>
      (update(pendingSales)..where((t) => t.clientTxnId.equals(clientTxnId)))
          .write(const PendingSalesCompanion(synced: Value(true)));

  Future<void> markSyncError(String clientTxnId, String error) =>
      (update(pendingSales)..where((t) => t.clientTxnId.equals(clientTxnId)))
          .write(PendingSalesCompanion(syncError: Value(error)));

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
  Future<List<Sale>> localSalesInRange(DateTime from, DateTime to) async {
    final rows = await (select(localSalesCache)
          ..where((t) => t.createdAt.isBiggerOrEqualValue(from) & t.createdAt.isSmallerOrEqualValue(to)))
        .get();
    return rows.map((r) => Sale.fromJson(jsonDecode(r.saleJson) as Map<String, dynamic>)).toList();
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

/// Plain view of a queued offline sale, decoded from the itemsJson blob.
class QueuedSale {
  final String clientTxnId;
  final List<Map<String, dynamic>> items;
  final String paymentMethod;
  final DateTime createdAt;

  const QueuedSale({
    required this.clientTxnId,
    required this.items,
    required this.paymentMethod,
    required this.createdAt,
  });
}
