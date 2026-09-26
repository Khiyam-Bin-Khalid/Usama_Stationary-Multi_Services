import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage; on web it falls back to browser storage
/// under the hood (the package handles that), which is acceptable here
/// since tokens are short-lived and the refresh token rotates.
class TokenStorage {
  final _storage = const FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _roleKey = 'user_role';

  Future<void> save({required String accessToken, required String refreshToken, required String role}) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
      _storage.write(key: _roleKey, value: role),
    ]);
  }

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<String?> get role => _storage.read(key: _roleKey);

  Future<void> updateAccessToken(String token) => _storage.write(key: _accessKey, value: token);

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _roleKey),
    ]);
  }
}
