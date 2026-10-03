import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/user.dart';
import '../remote/api_client.dart';
import '../remote/auth_api.dart';
import '../remote/token_storage.dart';

/// Authentication repository with offline-first login support.
///
/// **First online login**: credentials are verified by the server. On success
/// the access/refresh tokens, user profile and a local HMAC credential hash
/// are persisted on-device via [TokenStorage].
///
/// **App restart while offline**: [currentUser] returns the cached user profile
/// (because the device still has a stored token and the profile JSON), so the
/// user never sees the login screen just because connectivity dropped.
///
/// **Explicit offline login** (user typed credentials on the login screen while
/// offline): the HMAC of the entered credentials is compared against the
/// stored hash. If it matches, the previously cached profile is restored —
/// the user gets right back in with the stale tokens; the first API call when
/// connectivity returns will refresh them transparently.
class AuthRepository {
  final AuthApi authApi;
  final TokenStorage tokenStorage;

  AuthRepository({required this.authApi, required this.tokenStorage});

  Future<AppUser> login(String email, String password, {String? role}) async {
    try {
      final result = await authApi.login(email, password, role: role);
      await tokenStorage.save(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        role: result.user.role,
      );
      await tokenStorage.saveUserProfile(
        userJson: jsonEncode(_userToJson(result.user)),
        credentialHash: _credentialHash(email, password),
      );
      return result.user;
    } on ApiException catch (e) {
      if (!e.isNetworkError) rethrow;
      // Offline path — verify against stored credential hash.
      final cached = await _tryOfflineLogin(email, password);
      if (cached != null) return cached;
      rethrow; // no cached credentials → propagate the network error
    }
  }

  Future<AppUser> registerCustomer({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final result = await authApi.registerCustomer(
      name: name,
      email: email,
      password: password,
      phone: phone,
    );
    await tokenStorage.save(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      role: result.user.role,
    );
    await tokenStorage.saveUserProfile(
      userJson: jsonEncode(_userToJson(result.user)),
      credentialHash: _credentialHash(email, password),
    );
    return result.user;
  }

  /// Returns the current user. Never throws.
  ///
  /// - If the user explicitly logged out → null.
  /// - If no token → null.
  /// - If the API call succeeds → fresh user object (cached profile updated).
  /// - If network unreachable + token present → cached profile (offline mode).
  /// - Any other error → null.
  Future<AppUser?> currentUser() async {
    if (await tokenStorage.isLoggedOut) return null;
    final token = await tokenStorage.accessToken;
    if (token == null) return null;
    try {
      final user = await authApi.me();
      // Keep the cached profile fresh so offline re-login has the latest data.
      final existingHash = await tokenStorage.credentialHash;
      await tokenStorage.saveUserProfile(
        userJson: jsonEncode(_userToJson(user)),
        credentialHash: existingHash ?? '',
      );
      return user;
    } on ApiException catch (e) {
      if (!e.isNetworkError) return null;
      // Network error — return the locally-cached profile so the app keeps
      // working without forcing the user back to the login screen.
      final profileJson = await tokenStorage.userProfileJson;
      if (profileJson == null) return null;
      try {
        return AppUser.fromJson(jsonDecode(profileJson) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => tokenStorage.clear();

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Attempt an offline login by comparing the entered credentials against
  /// the locally-stored HMAC hash. Returns the cached [AppUser] on success.
  Future<AppUser?> _tryOfflineLogin(String email, String password) async {
    final storedHash = await tokenStorage.credentialHash;
    if (storedHash == null || storedHash.isEmpty) return null;
    if (_credentialHash(email, password) != storedHash) return null;
    final profileJson = await tokenStorage.userProfileJson;
    if (profileJson == null) return null;
    try {
      final user = AppUser.fromJson(
        jsonDecode(profileJson) as Map<String, dynamic>,
      );
      // Restore the session flag so currentUser() returns the profile offline.
      await tokenStorage.markActive();
      return user;
    } catch (_) {
      return null;
    }
  }

  /// HMAC-SHA256 of the normalised email + password using a fixed app-level
  /// key. Good enough for a POS running on a controlled device; for a public
  /// app you'd want PBKDF2 with a per-device salt.
  static String _credentialHash(String email, String password) {
    final key = utf8.encode('usama-pos-offline-v1');
    final msg = utf8.encode('${email.toLowerCase().trim()}:$password');
    return Hmac(sha256, key).convert(msg).toString();
  }

  static Map<String, dynamic> _userToJson(AppUser u) => {
        '_id': u.id,
        'name': u.name,
        'email': u.email,
        'role': u.role,
        if (u.phone != null) 'phone': u.phone,
        if (u.branch != null) 'branch': u.branch,
        'isActive': u.isActive,
      };
}
