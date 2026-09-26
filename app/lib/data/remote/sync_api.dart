import 'api_client.dart';
import 'guarded.dart';

class SyncApi {
  final ApiClient client;
  SyncApi(this.client);

  Future<List<Map<String, dynamic>>> pushSales(List<Map<String, dynamic>> sales) => guarded(() async {
        final res = await client.dio.post('/sync/push', data: {'sales': sales});
        return List<Map<String, dynamic>>.from(res.data['results']);
      });

  Future<Map<String, dynamic>> pullDeltas(DateTime? since) => guarded(() async {
        final res = await client.dio.get('/sync/pull', queryParameters: {
          if (since != null) 'since': since.toIso8601String(),
        });
        return res.data;
      });
}
