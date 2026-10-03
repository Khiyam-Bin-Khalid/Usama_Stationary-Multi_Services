import 'dart:io';
import 'package:dio/dio.dart';
import 'api_client.dart';
import 'guarded.dart';
import '../models/order.dart';

class PaymentApi {
  final ApiClient client;
  PaymentApi(this.client);

  Future<OrderPayment> uploadReceipt(String orderId, File file, {String? note}) => guarded(() async {
        final formData = FormData.fromMap({
          'receipt': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
          if (note != null && note.isNotEmpty) 'note': note,
        });
        final res = await client.dio.post('/payments/orders/$orderId/receipt', data: formData);
        return OrderPayment.fromJson(Map<String, dynamic>.from(res.data['payment'] as Map));
      });

  Future<OrderPayment> uploadReceiptBytes(String orderId, List<int> bytes, String filename, {String? note}) => guarded(() async {
        final formData = FormData.fromMap({
          'receipt': MultipartFile.fromBytes(bytes, filename: filename),
          if (note != null && note.isNotEmpty) 'note': note,
        });
        final res = await client.dio.post('/payments/orders/$orderId/receipt', data: formData);
        return OrderPayment.fromJson(Map<String, dynamic>.from(res.data['payment'] as Map));
      });

  /// Receipts awaiting an explicit admin decision. Each entry carries the
  /// payment plus the populated order (items with images/SKUs + customer).
  Future<List<PendingPayment>> pendingReview() => guarded(() async {
        final res = await client.dio.get('/payments/pending-review');
        return (res.data['payments'] as List).map((e) => PendingPayment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<OrderPayment> orderPayment(String orderId) => guarded(() async {
        final res = await client.dio.get('/payments/orders/$orderId');
        return OrderPayment.fromJson(Map<String, dynamic>.from(res.data['payment'] as Map));
      });

  Future<OrderPayment> review(String paymentId, {required bool approve, String? note}) => guarded(() async {
        final res = await client.dio.post('/payments/$paymentId/review', data: {'approve': approve, if (note != null) 'note': note});
        return OrderPayment.fromJson(Map<String, dynamic>.from(res.data['payment'] as Map));
      });
}

class PendingPayment {
  final OrderPayment payment;
  final CustomerOrder? order;
  const PendingPayment({required this.payment, this.order});

  factory PendingPayment.fromJson(Map<String, dynamic> json) => PendingPayment(
        payment: OrderPayment.fromJson(json),
        order: json['order'] is Map ? CustomerOrder.fromJson(Map<String, dynamic>.from(json['order'] as Map)) : null,
      );
}
