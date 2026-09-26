import 'api_client.dart';
import 'guarded.dart';

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
  }) =>
      guarded(() async {
        final res = await client.dio.post('/sales', data: {
          'clientTxnId': clientTxnId,
          'items': items,
          'paymentMethod': paymentMethod,
          'recordedOffline': recordedOffline,
        });
        return res.data;
      });
}
