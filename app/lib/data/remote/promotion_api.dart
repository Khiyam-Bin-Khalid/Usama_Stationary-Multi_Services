import 'api_client.dart';
import 'guarded.dart';
import '../models/promotion.dart';

class PromotionApi {
  final ApiClient client;
  PromotionApi(this.client);

  Future<List<Promotion>> active() => guarded(() async {
        final res = await client.dio.get('/promotions/active');
        return (res.data['promotions'] as List).map((e) => Promotion.fromJson(e)).toList();
      });

  Future<List<Promotion>> allForAdmin() => guarded(() async {
        final res = await client.dio.get('/promotions');
        return (res.data['promotions'] as List).map((e) => Promotion.fromJson(e)).toList();
      });

  Future<Promotion> create(Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.post('/promotions', data: payload);
        return Promotion.fromJson(res.data['promotion']);
      });

  Future<Promotion> update(String id, Map<String, dynamic> payload) => guarded(() async {
        final res = await client.dio.patch('/promotions/$id', data: payload);
        return Promotion.fromJson(res.data['promotion']);
      });
}
