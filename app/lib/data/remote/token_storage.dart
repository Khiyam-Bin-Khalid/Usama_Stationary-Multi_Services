import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage; on web it falls back to browser storage
/// under the hood (the package handles that), which is acceptable here
/// since tokens are short-lived and the refresh token rotates.
///
/// Offline-first additions: the access/refresh tokens are NOT deleted on
/// logout — only a [_loggedOutKey] flag is written. This lets the app:
///   1. Stay logged in across restarts when offline (tokens may be stale but
///      the cached user profile is returned instead of hitting the API).
///   2. Allow offline re-login by verifying against a stored credential hash.
/// Once back online the normal token-refresh interceptor refreshes (or clears)
/// the tokens automatically.
class TokenStorage {
  final _storage = const FlutterSecureStorage();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _roleKey = 'user_role';

  // Offline-first keys
  static const _loggedOutKey = 'logged_out';
  static const _userProfileKey = 'user_profile_json';
  static const _credHashKey = 'offline_cred_hash';

  // ── Token management ────────────────────────────────────────────────────────

  /// Save tokens after a successful online login/register. Also clears the
  /// logged-out flag so [currentUser] will return the cached profile offline.
  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String role,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: accessToken),
      _storage.write(key: _refreshKey, value: refreshToken),
      _storage.write(key: _roleKey, value: role),
      _storage.write(key: _loggedOutKey, value: 'false'),
    ]);
  }

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<String?> get role => _storage.read(key: _roleKey);

  Future<void> updateAccessToken(String token) =>
      _storage.write(key: _accessKey, value: token);

  /// Marks the session as logged out without deleting tokens so that offline
  /// re-login can restore it later. Callers that need a truly clean state
  /// (e.g. after a failed token refresh) should call [clearAll] instead.
  Future<void> clear() async {
    await Future.wait([
      _storage.write(key: _loggedOutKey, value: 'true'),
      _storage.delete(key: _roleKey),
    ]);
  }

  /// Hard wipe — removes everything including offline credential cache.
  /// Used by the token-refresh interceptor when the refresh token itself
  /// is rejected by the server, so we must force the user to log in online.
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // ── Offline auth helpers ─────────────────────────────────────────────────

  /// Whether the user explicitly logged out. Returns false when not set (i.e.
  /// the key has never been written — the app was just installed).
  Future<bool> get isLoggedOut async {
    final v = await _storage.read(key: _loggedOutKey);
    return v == 'true';
  }

  /// Clear the logged-out flag after a successful offline re-login.
  Future<void> markActive() =>
      _storage.write(key: _loggedOutKey, value: 'false');

  /// Persist the user's profile JSON and HMAC-based credential hash after a
  /// successful online login so they can authenticate while offline later.
  Future<void> saveUserProfile({
    required String userJson,
    required String credentialHash,
  }) async {
    await Future.wait([
      _storage.write(key: _userProfileKey, value: userJson),
      _storage.write(key: _credHashKey, value: credentialHash),
    ]);
  }

  /// The cached user profile JSON, or null if never set.
  Future<String?> get userProfileJson => _storage.read(key: _userProfileKey);

  /// The stored HMAC credential hash, or null if never set.
  Future<String?> get credentialHash => _storage.read(key: _credHashKey);
}
