import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/roles.dart';
import '../models/user.dart';
import '../remote/api_client.dart';
import '../remote/auth_api.dart';
import '../remote/token_storage.dart';
import 'offline_credentials.dart';

/// Authentication repository with offline-first login support.
///
/// **Online login**: the server verifies the credentials. For staff accounts
/// (Super Admin, Admin, Staff) on desktop/mobile the tokens, profile and a
/// salted password hash are also stored in the device's offline vault, one
/// entry per account, so anyone who has signed in here can sign in offline.
///
/// **App restart while offline**: [currentUser] returns the cached profile, so
/// the user never sees the login screen just because connectivity dropped.
///
/// **Offline login**: when the server can't be reached, the password is checked
/// against the vault. The selected role must match, repeated wrong passwords
/// lock the account for a few minutes, and an account the server hasn't seen
/// for [offlineValidity] must connect again.
class AuthRepository {
  final AuthApi authApi;
  final TokenStorage tokenStorage;
  final DateTime Function() _now;

  static const offlineValidity = Duration(days: 30);
  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 5);

  AuthRepository({required this.authApi, required this.tokenStorage, DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<AppUser> login(String email, String password, {String? role}) async {
    try {
      final result = await authApi.login(email, password, role: role);
      await tokenStorage.save(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        role: result.user.role,
      );
      await tokenStorage.saveUserProfile(jsonEncode(_userToJson(result.user)));
      await _rememberForOffline(email, password, result.user, result.accessToken, result.refreshToken);
      return result.user;
    } on ApiException catch (e) {
      // The server says these credentials are no longer good (password changed,
      // account disabled): the old offline copy must stop working too.
      if (e.statusCode == 401) await tokenStorage.removeOfflineAccount(email);
      if (!e.isServerDown || kIsWeb) rethrow;
      return _offlineLogin(email, password, role);
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
    await tokenStorage.saveUserProfile(jsonEncode(_userToJson(result.user)));
    return result.user;
  }

  /// Returns the current user. Never throws.
  ///
  /// - If the user explicitly logged out → null.
  /// - If no token → null.
  /// - If the API call succeeds → fresh user object (cached profile updated).
  /// - If the server is unreachable + token present → cached profile.
  /// - If the server rejects the session → null.
  Future<AppUser?> currentUser() async {
    if (await tokenStorage.isLoggedOut) return null;
    final token = await tokenStorage.accessToken;
    if (token == null) return null;
    try {
      final user = await authApi.me();
      final userJson = jsonEncode(_userToJson(user));
      await tokenStorage.saveUserProfile(userJson);
      final account = await tokenStorage.offlineAccount(user.email);
      if (account != null) {
        await tokenStorage.saveOfflineAccount(user.email, account.copyWith(profileJson: userJson, verifiedAt: _now()));
      }
      return user;
    } on ApiException catch (e) {
      if (e.isServerDown) return _cachedProfile();
      final cached = await _cachedProfile();
      if (cached != null) await tokenStorage.removeOfflineAccount(cached.email);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => tokenStorage.clear();

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<AppUser?> _cachedProfile() async {
    final profileJson = await tokenStorage.userProfileJson;
    if (profileJson == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(profileJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberForOffline(String email, String password, AppUser user, String accessToken, String refreshToken) async {
    if (kIsWeb || !UserRole.staffRoles.contains(user.role)) return;
    final salt = OfflineCredentials.newSalt();
    await tokenStorage.saveOfflineAccount(
      email,
      OfflineAccount(
        salt: salt,
        hash: await OfflineCredentials.hash(password, salt, OfflineCredentials.iterations),
        iterations: OfflineCredentials.iterations,
        profileJson: jsonEncode(_userToJson(user)),
        accessToken: accessToken,
        refreshToken: refreshToken,
        verifiedAt: _now(),
      ),
    );
  }

  Future<AppUser> _offlineLogin(String email, String password, String? role) async {
    final account = await tokenStorage.offlineAccount(email);
    if (account == null) {
      throw ApiException('Can\'t reach the server, and this account hasn\'t signed in on this device yet. '
          'Connect to the internet and sign in once to enable offline login.');
    }
    final now = _now();
    final lockedUntil = account.lockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      final minutes = lockedUntil.difference(now).inMinutes + 1;
      throw ApiException('Too many wrong passwords. Try again in $minutes minute(s).');
    }
    if (now.difference(account.verifiedAt) > offlineValidity) {
      throw ApiException('Offline access for this account has expired. Connect to the internet and sign in.');
    }

    final hash = await OfflineCredentials.hash(password, account.salt, account.iterations);
    if (!OfflineCredentials.matches(hash, account.hash)) {
      final failed = account.failedAttempts + 1;
      final locked = failed >= maxFailedAttempts;
      await tokenStorage.saveOfflineAccount(
        email,
        locked ? account.copyWith(failedAttempts: 0, lockedUntil: now.add(lockDuration)) : account.copyWith(failedAttempts: failed, clearLock: true),
      );
      throw ApiException('Invalid email or password');
    }

    final user = AppUser.fromJson(jsonDecode(account.profileJson) as Map<String, dynamic>);
    // Same rule as the server: the picked role must be the account's real role.
    if (role != null && role != user.role) {
      throw ApiException('This account is registered as ${user.role}, not $role. Select the correct role to sign in.');
    }

    if (account.failedAttempts != 0 || lockedUntil != null) {
      await tokenStorage.saveOfflineAccount(email, account.copyWith(failedAttempts: 0, clearLock: true));
    }
    // Make this account's tokens the active ones, so the next sync runs as the
    // person actually at the counter rather than whoever was here before.
    await tokenStorage.save(accessToken: account.accessToken, refreshToken: account.refreshToken, role: user.role);
    await tokenStorage.saveUserProfile(account.profileJson);
    return user;
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
