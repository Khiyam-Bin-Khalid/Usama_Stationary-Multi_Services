import 'api_client.dart';
import 'guarded.dart';

class ReportApi {
  final ApiClient client;
  ReportApi(this.client);

  Future<Map<String, dynamic>> salesReport({
    String period = 'daily',
    String source = 'all',
    String? category,
    String? productId,
    DateTime? from,
    DateTime? to,
  }) =>
      guarded(() async {
        final res = await client.dio.get('/reports/sales', queryParameters: {
          'period': period,
          'source': source,
          if (category != null) 'category': category,
          if (productId != null) 'product': productId,
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
        });
        return res.data;
      });

  /// Role-shaped landing dashboard (GET /reports/dashboard).
  Future<Map<String, dynamic>> dashboard() => guarded(() async {
        final res = await client.dio.get('/reports/dashboard');
        return Map<String, dynamic>.from(res.data);
      });

  Future<List<Map<String, dynamic>>> categoryReport({DateTime? from, DateTime? to, String source = 'all'}) => guarded(() async {
        final res = await client.dio.get('/reports/categories', queryParameters: {
          'source': source,
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
        });
        return List<Map<String, dynamic>>.from(res.data['categories']);
      });

  /// Top products by revenue (optionally within a category).
  Future<List<Map<String, dynamic>>> productReport({DateTime? from, DateTime? to, String source = 'all', String? category, int limit = 20}) =>
      guarded(() async {
        final res = await client.dio.get('/reports/products', queryParameters: {
          'source': source,
          if (category != null) 'category': category,
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          'limit': limit,
        });
        return List<Map<String, dynamic>>.from(res.data['products']);
      });
}
