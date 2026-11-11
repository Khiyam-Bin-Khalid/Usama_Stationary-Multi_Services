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
  Future<List<Sale>> listSales({DateTime? from, DateTime? to}) => _page(from, to, 1);

  /// Every sale in the window, for the month of daily records on the device.
  /// The API caps a page at [_pageSize], so a busy month spans several pages.
  Future<List<Sale>> listAllSales({DateTime? from, DateTime? to}) async {
    final all = <Sale>[];
    for (var page = 1;; page++) {
      final sales = await _page(from, to, page);
      all.addAll(sales);
      if (sales.length < _pageSize) return all;
    }
  }

  static const _pageSize = 200;

  Future<List<Sale>> _page(DateTime? from, DateTime? to, int page) => guarded(() async {
        final res = await client.dio.get(
          '/sales',
          queryParameters: {
            if (from != null) 'from': from.toUtc().toIso8601String(),
            if (to != null) 'to': to.toUtc().toIso8601String(),
            'limit': _pageSize,
            'page': page,
          },
        );
        return (res.data['sales'] as List).map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
      });
}
