import 'package:drift/drift.dart';

/// Local cache of the product catalog, refreshed by SyncService.pull() so
/// the POS/catalog screens can render (and be sold from) while offline.
class ProductsCache extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get sku => text()();
  TextColumn get barcode => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get description => text().nullable()();
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

  /// Who rang the sale up. Null only for rows queued before schema v4.
  TextColumn get cashierId => text().nullable()();
  TextColumn get cashierName => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientTxnId};
}

/// Product changes an Admin made while offline, replayed in [seq] order: a
/// later op can depend on the id the server assigns to a product_create. opId
/// makes a replay safe if the server's answer is lost on the way back.
class PendingOps extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get opId => text().unique()();
  TextColumn get type => text()(); // product_create|product_update|product_delete|stock_adjust|product_image
  TextColumn get productId => text().nullable()(); // may be a local- id until its create is synced
  TextColumn get label => text()(); // shown in the sync queue
  TextColumn get payloadJson => text()();
  BlobColumn get imageBytes => blob().nullable()();
  TextColumn get imageName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get lastError => text().nullable()();
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Local mirror of confirmed (and pending-sync) sales used by the Daily Sale
/// tab when the device is offline. The full Sale is stored as a JSON blob;
/// [createdAt] is denormalized so we can query today's rows without
/// deserializing every blob.
class LocalSalesCache extends Table {
  /// Stable key — clientTxnId for offline sales, set to the server _id once
  /// confirmed so a server-side re-pull deduplicates correctly.
  TextColumn get clientTxnId => text()();
  TextColumn get saleJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// True while the sale hasn't been confirmed by the server yet.
  BoolColumn get pending => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {clientTxnId};
}
