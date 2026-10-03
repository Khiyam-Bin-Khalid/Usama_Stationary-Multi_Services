import 'api_client.dart';
import 'guarded.dart';
import '../models/inventory_movement.dart';
import '../models/product.dart';

class InventoryApi {
  final ApiClient client;
  InventoryApi(this.client);

  /// Stock-movement history across all products, newest first.
  Future<List<InventoryMovement>> movements({
    String? productId,
    String? sku,
    String? category,
    String? type,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) =>
      guarded(() async {
        final res = await client.dio.get('/inventory/movements', queryParameters: {
          if (productId != null) 'product': productId,
          if (sku != null && sku.isNotEmpty) 'sku': sku,
          if (category != null) 'category': category,
          if (type != null) 'type': type,
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          'limit': limit,
        });
        return (res.data['logs'] as List).map((e) => InventoryMovement.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<List<Product>> lowStock() => guarded(() async {
        final res = await client.dio.get('/inventory/low-stock');
        return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
      });
}
