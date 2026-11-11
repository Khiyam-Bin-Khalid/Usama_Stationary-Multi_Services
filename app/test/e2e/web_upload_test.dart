// The web admin's upload path in a real browser: XHR, CORS and multipart are
// all different from the desktop HTTP stack. Needs the throwaway stack:
//
//   node backend/scripts/e2e-stack.js
//   flutter test --platform chrome test/e2e/web_upload_test.dart
@TestOn('chrome')
library;

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usama_book_depot/data/remote/api_client.dart';
import 'package:usama_book_depot/data/remote/auth_api.dart';
import 'package:usama_book_depot/data/remote/product_api.dart';
import 'package:usama_book_depot/data/remote/token_storage.dart';

void main() {
  test('web admin adds a product photo and the storefront shows it', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final tokens = TokenStorage();
    final client = ApiClient(tokens, baseUrl: 'http://127.0.0.1:4100/api');
    final auth = await AuthApi(client).login('owner@example.com', 'OwnerPass123', role: 'superadmin');
    await tokens.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken, role: auth.user.role);
    final products = ProductApi(client);

    final name = 'Web Photo ${DateTime.now().millisecondsSinceEpoch}';
    final created = await products.create({'name': name, 'category': 'stationery', 'price': 75, 'currentStock': 3});
    final png = [
      ...base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='),
      ...utf8.encode('E2E-IMAGE-MARKER'),
    ];
    final updated = await products.uploadImage(created.id, png, 'photo.png');
    expect(updated.imageUrl, startsWith('https://res.cloudinary.com/'));

    await tokens.clearAll(); // a logged-out customer
    final store = await ProductApi(ApiClient(tokens, baseUrl: 'http://127.0.0.1:4100/api')).list(q: name);
    expect(store.single.imageUrl, updated.imageUrl);
  });
}
