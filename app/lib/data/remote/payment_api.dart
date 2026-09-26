import 'dart:io';
import 'package:dio/dio.dart';
import 'api_client.dart';
import 'guarded.dart';

class PaymentApi {
  final ApiClient client;
  PaymentApi(this.client);

  Future<Map<String, dynamic>> uploadReceipt(String orderId, File file) => guarded(() async {
        final formData = FormData.fromMap({
          'receipt': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
        });
        final res = await client.dio.post('/payments/orders/$orderId/receipt', data: formData);
        return res.data['payment'];
      });

  Future<Map<String, dynamic>> uploadReceiptBytes(String orderId, List<int> bytes, String filename) => guarded(() async {
        final formData = FormData.fromMap({
          'receipt': MultipartFile.fromBytes(bytes, filename: filename),
        });
        final res = await client.dio.post('/payments/orders/$orderId/receipt', data: formData);
        return res.data['payment'];
      });

  Future<List<Map<String, dynamic>>> pendingReview() => guarded(() async {
        final res = await client.dio.get('/payments/pending-review');
        return List<Map<String, dynamic>>.from(res.data['payments']);
      });

  Future<Map<String, dynamic>> review(String paymentId, {required bool approve, String? note}) => guarded(() async {
        final res = await client.dio.post('/payments/$paymentId/review', data: {'approve': approve, if (note != null) 'note': note});
        return res.data['payment'];
      });
}
