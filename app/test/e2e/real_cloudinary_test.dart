// Sends one real photo through the app to the Cloudinary account in
// backend/.env, against a throwaway database:
//
//   node backend/scripts/e2e-stack.js --real-cloudinary
//   REAL_CLOUDINARY=1 flutter test test/e2e/real_cloudinary_test.dart
//
// Set IMAGE_PATH to send a specific picture instead of a tiny generated one.
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usama_book_depot/data/remote/api_client.dart';
import 'package:usama_book_depot/data/remote/auth_api.dart';
import 'package:usama_book_depot/data/remote/product_api.dart';
import 'package:usama_book_depot/data/remote/token_storage.dart';

void main() {
  test('a product photo reaches the real Cloudinary account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tokens = TokenStorage();
    final client = ApiClient(tokens, baseUrl: 'http://127.0.0.1:4100/api');
    final auth = await AuthApi(client).login('owner@example.com', 'OwnerPass123', role: 'superadmin');
    await tokens.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken, role: auth.user.role);
    final products = ProductApi(client);
    final created = await products.create({'name': 'Cloudinary check', 'category': 'stationery', 'price': 1});
    final imagePath = Platform.environment['IMAGE_PATH'];
    final bytes = imagePath == null
        ? base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')
        : File(imagePath).readAsBytesSync();
    final filename = imagePath == null ? 'check.png' : imagePath.split('/').last;

    final updated = await products.uploadImage(created.id, bytes, filename);
    expect(updated.imageUrl, startsWith('https://res.cloudinary.com/'));
    final served = await Dio().get<List<int>>(updated.imageUrl!, options: Options(responseType: ResponseType.bytes));
    expect(served.statusCode, 200);
    expect(served.data, bytes, reason: 'Cloudinary must serve back the exact file sent');
    // ignore: avoid_print
    print('Uploaded: ${updated.imageUrl}');
  }, skip: Platform.environment['REAL_CLOUDINARY'] == '1' ? false : 'Needs --real-cloudinary stack and REAL_CLOUDINARY=1');
}
