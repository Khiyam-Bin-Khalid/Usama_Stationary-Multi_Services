import 'api_client.dart';
import 'guarded.dart';
import '../models/product.dart';

class ProductApi {
  final ApiClient client;
  ProductApi(this.client);

  Future<List<Product>> list({String? category, String? q, bool? isAvailableOnline, bool lowStockOnly = false}) =>
      guarded(() async {
        final res = await client.dio.get('/products', queryParameters: {
          if (category != null) 'category': category,
          if (q != null && q.isNotEmpty) 'q': q,
          if (isAvailableOnline != null) 'isAvailableOnline': isAvailableOnline,
          if (lowStockOnly) 'lowStockOnly': true,
          'limit': 200,
        });
        return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
      });

  Future<Product> create(Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.post('/products', data: payload);
        return Product.fromJson(res.data['product']);
      });

  Future<Product> update(String id, Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.patch('/products/$id', data: payload);
        return Product.fromJson(res.data['product']);
      });

  Future<Product> adjustStock(String id, {required num delta, required String reason}) => guarded(() async {
        final res = await client.dio.post('/products/$id/adjust-stock', data: {'delta': delta, 'reason': reason});
        return Product.fromJson(res.data['product']);
      });
}
