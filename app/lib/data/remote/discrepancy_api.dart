import 'api_client.dart';
import 'guarded.dart';
import '../models/discrepancy.dart';

class DiscrepancyApi {
  final ApiClient client;
  DiscrepancyApi(this.client);

  Future<DiscrepancyReport> report({required String productId, required int countedQty, String? note}) => guarded(() async {
        final res = await client.dio.post('/inventory/discrepancies', data: {
          'product': productId,
          'countedQty': countedQty,
          if (note != null && note.isNotEmpty) 'note': note,
        });
        return DiscrepancyReport.fromJson(res.data['report']);
      });

  Future<List<DiscrepancyReport>> list({String? status}) => guarded(() async {
        final res = await client.dio.get('/inventory/discrepancies', queryParameters: {
          if (status != null) 'status': status,
          'limit': 100,
        });
        return (res.data['reports'] as List).map((e) => DiscrepancyReport.fromJson(e)).toList();
      });

  Future<DiscrepancyReport> resolve(String id, {required bool applyAdjustment, bool dismiss = false, String? resolution}) =>
      guarded(() async {
        final res = await client.dio.patch('/inventory/discrepancies/$id/resolve', data: {
          'applyAdjustment': applyAdjustment,
          'dismiss': dismiss,
          if (resolution != null && resolution.isNotEmpty) 'resolution': resolution,
        });
        return DiscrepancyReport.fromJson(res.data['report']);
      });
}
