import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/models/product.dart';

Product productFromCache(ProductsCacheData row) => Product(
      id: row.id,
      name: row.name,
      sku: row.sku,
      category: row.category,
      unit: row.unit,
      price: row.price,
      costPrice: row.costPrice,
      currentStock: row.currentStock,
      reorderThreshold: row.reorderThreshold,
      isMadeToOrder: row.isMadeToOrder,
      isAvailableOnline: row.isAvailableOnline,
      isActive: row.isActive,
    );

/// Product list for the POS screen: streamed from the local drift cache
/// (works offline) on native platforms, or fetched directly from the API
/// on web where there is no local cache (see localDbAvailableProvider).
final posProductsStreamProvider = StreamProvider<List<Product>>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  if (db != null) {
    yield* db.watchProducts().map((rows) => rows.map(productFromCache).toList());
  } else {
    final products = await ref.watch(productApiProvider).list();
    yield products;
  }
});
