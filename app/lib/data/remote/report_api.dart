import 'api_client.dart';
import 'guarded.dart';

class ReportApi {
  final ApiClient client;
  ReportApi(this.client);

  Future<Map<String, dynamic>> salesReport({
    String period = 'daily',
    String source = 'all',
    String? category,
    DateTime? from,
    DateTime? to,
  }) =>
      guarded(() async {
        final res = await client.dio.get('/reports/sales', queryParameters: {
          'period': period,
          'source': source,
          if (category != null) 'category': category,
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
        });
        return res.data;
      });

  Future<List<Map<String, dynamic>>> categoryReport({DateTime? from, DateTime? to}) => guarded(() async {
        final res = await client.dio.get('/reports/categories', queryParameters: {
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
        });
        return List<Map<String, dynamic>>.from(res.data['categories']);
      });
}
