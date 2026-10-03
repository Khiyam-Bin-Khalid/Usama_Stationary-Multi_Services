import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/models/product.dart';

Product productFromCache(ProductsCacheData row) => Product(
      id: row.id,
      name: row.name,
      sku: row.sku,
      barcode: row.barcode,
      imageUrl: row.imageUrl,
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

/// Product list for the POS quick-sell grid: streamed from the local drift
/// cache (works offline) on native platforms, or fetched from the API on web.
/// Spec §4.1: out-of-stock products are excluded (Product.isSellable).
final posProductsStreamProvider = StreamProvider<List<Product>>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  if (db != null) {
    yield* db.watchProducts().map((rows) => rows.map(productFromCache).where((p) => p.isSellable).toList());
  } else {
    final products = await ref.watch(productApiProvider).list(sellableOnly: true);
    yield products.where((p) => p.isSellable).toList();
  }
});
