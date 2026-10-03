import 'api_client.dart';
import 'guarded.dart';
import '../models/order.dart';

class PlaceOrderResult {
  final CustomerOrder order;
  final String? stripeCheckoutUrl;
  const PlaceOrderResult({required this.order, this.stripeCheckoutUrl});
}

class OrderApi {
  final ApiClient client;
  OrderApi(this.client);

  /// Prices the cart (images, SKUs, line totals, discount, delivery, tax,
  /// grand total) without creating anything — the checkout summary.
  Future<OrderQuote> quote({required List<Map<String, dynamic>> items, bool isHomeDelivery = true}) => guarded(() async {
        final res = await client.dio.post('/orders/quote', data: {'items': items, 'isHomeDelivery': isHomeDelivery});
        return OrderQuote.fromJson(Map<String, dynamic>.from(res.data['quote'] as Map));
      });

  Future<PlaceOrderResult> placeOrder({
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    required Map<String, dynamic> delivery,
  }) =>
      guarded(() async {
        final res = await client.dio.post('/orders', data: {
          'items': items,
          'paymentMethod': paymentMethod,
          'delivery': delivery,
        });
        final checkout = res.data['checkout'];
        return PlaceOrderResult(
          order: CustomerOrder.fromJson(res.data['order']),
          stripeCheckoutUrl: checkout != null ? checkout['checkoutUrl'] as String? : null,
        );
      });

  Future<List<CustomerOrder>> myOrders() => guarded(() async {
        final res = await client.dio.get('/orders/mine');
        return (res.data['orders'] as List).map((e) => CustomerOrder.fromJson(e)).toList();
      });

  Future<CustomerOrder> myOrder(String id) => guarded(() async {
        final res = await client.dio.get('/orders/mine/$id');
        return CustomerOrder.fromJson(res.data['order']);
      });

  /// Admin/staff: all orders, optionally filtered by one status or a group.
  Future<List<CustomerOrder>> listAll({String? status, List<String>? statuses}) => guarded(() async {
        final res = await client.dio.get('/orders', queryParameters: {
          if (status != null) 'status': status,
          if (statuses != null && statuses.isNotEmpty) 'statuses': statuses.join(','),
          'limit': 200,
        });
        return (res.data['orders'] as List).map((e) => CustomerOrder.fromJson(e)).toList();
      });

  /// Admin/staff: one order with customer, payment (receipt) and history.
  Future<CustomerOrder> getOrder(String id) => guarded(() async {
        final res = await client.dio.get('/orders/$id');
        return CustomerOrder.fromJson(res.data['order']);
      });

  Future<Map<String, int>> statusCounts() => guarded(() async {
        final res = await client.dio.get('/orders/status-counts');
        return Map<String, int>.from((res.data['counts'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())));
      });

  Future<CustomerOrder> updateStatus(
    String orderId, {
    required String status,
    String? note,
    String? courierName,
    String? trackingNote,
  }) =>
      guarded(() async {
        final res = await client.dio.patch('/orders/$orderId/status', data: {
          'status': status,
          if (note != null && note.isNotEmpty) 'note': note,
          if (courierName != null && courierName.isNotEmpty) 'courierName': courierName,
          if (trackingNote != null && trackingNote.isNotEmpty) 'trackingNote': trackingNote,
        });
        return CustomerOrder.fromJson(res.data['order']);
      });
}
