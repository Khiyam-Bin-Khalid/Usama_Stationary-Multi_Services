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

  /// Admin/staff: all orders, optionally filtered.
  Future<List<CustomerOrder>> listAll({String? status}) => guarded(() async {
        final res = await client.dio.get('/orders', queryParameters: {if (status != null) 'status': status});
        return (res.data['orders'] as List).map((e) => CustomerOrder.fromJson(e)).toList();
      });

  Future<CustomerOrder> updateStatus(String orderId, {required String status, String? note}) => guarded(() async {
        final res = await client.dio.patch('/orders/$orderId/status', data: {'status': status, if (note != null) 'note': note});
        return CustomerOrder.fromJson(res.data['order']);
      });
}
