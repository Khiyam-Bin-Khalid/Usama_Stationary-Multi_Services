import 'api_client.dart';
import 'guarded.dart';
import '../models/sale.dart';

class SaleApi {
  final ApiClient client;
  SaleApi(this.client);

  /// Records a POS sale online. Callers should catch failures and fall back
  /// to the offline queue (see SyncService) rather than losing the sale.
  Future<Map<String, dynamic>> recordSale({
    required String clientTxnId,
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    bool recordedOffline = false,
  }) => guarded(() async {
    final res = await client.dio.post(
      '/sales',
      data: {
        'clientTxnId': clientTxnId,
        'items': items,
        'paymentMethod': paymentMethod,
        'recordedOffline': recordedOffline,
      },
    );
    return res.data;
  });

  /// Staff get only their own transactions (server-side scoped); Admin /
  /// Super Admin see everyone's — used by the Daily Sale tab.
  Future<List<Sale>> listSales({DateTime? from, DateTime? to}) =>
      guarded(() async {
        final res = await client.dio.get(
          '/sales',
          queryParameters: {
            if (from != null) 'from': from.toIso8601String(),
            if (to != null) 'to': to.toIso8601String(),
            'limit': 200,
          },
        );
        return (res.data['sales'] as List)
            .map((e) => Sale.fromJson(e as Map<String, dynamic>))
            .toList();
      });
}
