import 'package:dio/dio.dart';
import 'api_client.dart';
import 'guarded.dart';
import '../models/product.dart';

class ProductApi {
  final ApiClient client;
  ProductApi(this.client);

  Future<List<Product>> list({
    String? category,
    String? q,
    String? barcode,
    bool? isAvailableOnline,
    bool lowStockOnly = false,
    bool sellableOnly = false,
  }) =>
      guarded(() async {
        final res = await client.dio.get('/products', queryParameters: {
          if (category != null) 'category': category,
          if (q != null && q.isNotEmpty) 'q': q,
          if (barcode != null && barcode.isNotEmpty) 'barcode': barcode,
          if (isAvailableOnline != null) 'isAvailableOnline': isAvailableOnline,
          if (lowStockOnly) 'lowStockOnly': true,
          if (sellableOnly) 'sellableOnly': true,
          'limit': 200,
        });
        return (res.data['products'] as List).map((e) => Product.fromJson(e)).toList();
      });

  Future<Product> get(String id) => guarded(() async {
        final res = await client.dio.get('/products/$id');
        return Product.fromJson(res.data['product']);
      });

  Future<Product> create(Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.post('/products', data: payload);
        return Product.fromJson(res.data['product']);
      });

  Future<Product> update(String id, Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.patch('/products/$id', data: payload);
        return Product.fromJson(res.data['product']);
      });

  /// Soft delete — the server keeps the record for reports (spec §4.1).
  Future<void> delete(String id) => guarded(() => client.dio.delete('/products/$id'));

  Future<Product> adjustStock(String id, {required num delta, required String reason}) => guarded(() async {
        final res = await client.dio.post('/products/$id/adjust-stock', data: {'delta': delta, 'reason': reason});
        return Product.fromJson(res.data['product']);
      });

  Future<Product> uploadImage(String id, List<int> bytes, String filename) => guarded(() async {
        final formData = FormData.fromMap({
          'image': MultipartFile.fromBytes(bytes, filename: filename),
        });
        final res = await client.dio.post('/products/$id/image', data: formData);
        return Product.fromJson(res.data['product']);
      });
}
