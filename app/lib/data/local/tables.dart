import 'package:drift/drift.dart';

/// Local cache of the product catalog, refreshed by SyncService.pull() so
/// the POS/catalog screens can render (and be sold from) while offline.
class ProductsCache extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get sku => text()();
  TextColumn get category => text()();
  TextColumn get unit => text()();
  RealColumn get price => real()();
  RealColumn get costPrice => real()();
  IntColumn get currentStock => integer()();
  IntColumn get reorderThreshold => integer()();
  BoolColumn get isMadeToOrder => boolean()();
  BoolColumn get isAvailableOnline => boolean()();
  BoolColumn get isActive => boolean()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PromotionsCache extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get discountType => text()();
  RealColumn get discountValue => real()();
  TextColumn get categoriesJson => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per POS sale recorded while offline (or eagerly, before the
/// server confirms an online sale), keyed by the client-generated
/// clientTxnId so a retried push is safe (server dedupes on the same key).
class PendingSales extends Table {
  TextColumn get clientTxnId => text()();
  TextColumn get itemsJson => text()(); // [{productId, quantity, name, unitPrice}]
  TextColumn get paymentMethod => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  TextColumn get syncError => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientTxnId};
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
