import 'dart:convert';
import 'package:drift/drift.dart';
import 'tables.dart';
import 'connection/connection.dart' if (dart.library.js_interop) 'connection/connection_web.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [ProductsCache, PromotionsCache, PendingSales, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  @override
  int get schemaVersion => 1;

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
