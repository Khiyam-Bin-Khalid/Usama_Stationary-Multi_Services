import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/product.dart';
import '../../data/repositories/inventory_repository.dart';

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
