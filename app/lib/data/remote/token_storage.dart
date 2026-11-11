import 'dart:convert';
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
///
/// Offline accounts live in a separate vault ([offlineAccounts]) so several
/// people can sign in on one shared counter device, and so an expired session
/// never takes offline access away with it.
class TokenStorage {
  final _storage = const FlutterSecureStorage();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _roleKey = 'user_role';

  // Offline-first keys
  static const _loggedOutKey = 'logged_out';
  static const _userProfileKey = 'user_profile_json';
  static const _legacyCredHashKey = 'offline_cred_hash';
  static const _offlineAccountsKey = 'offline_accounts';

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

  /// Ends the session completely. Used by the token-refresh interceptor when
  /// the server rejects the refresh token, so the user must log in again. The
  /// offline vault is kept: it has its own expiry.
  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _roleKey),
      _storage.delete(key: _loggedOutKey),
      _storage.delete(key: _userProfileKey),
    ]);
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

  /// Persist the active user's profile so a restart works without a network.
  Future<void> saveUserProfile(String userJson) => _storage.write(key: _userProfileKey, value: userJson);

  /// The cached user profile JSON, or null if never set.
  Future<String?> get userProfileJson => _storage.read(key: _userProfileKey);

  // ── Offline account vault ───────────────────────────────────────────────

  Future<Map<String, OfflineAccount>> offlineAccounts() async {
    final raw = await _storage.read(key: _offlineAccountsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, OfflineAccount.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<OfflineAccount?> offlineAccount(String email) async => (await offlineAccounts())[normaliseEmail(email)];

  Future<void> saveOfflineAccount(String email, OfflineAccount account) async {
    final accounts = await offlineAccounts();
    accounts[normaliseEmail(email)] = account;
    await _writeAccounts(accounts);
    await _storage.delete(key: _legacyCredHashKey);
  }

  Future<void> removeOfflineAccount(String email) async {
    final accounts = await offlineAccounts();
    if (accounts.remove(normaliseEmail(email)) != null) await _writeAccounts(accounts);
  }

  Future<void> _writeAccounts(Map<String, OfflineAccount> accounts) =>
      _storage.write(key: _offlineAccountsKey, value: jsonEncode(accounts.map((k, v) => MapEntry(k, v.toJson()))));

  static String normaliseEmail(String email) => email.trim().toLowerCase();
}

/// One staff account that has signed in online on this device. The password
/// is only ever kept as a salted PBKDF2 hash.
class OfflineAccount {
  final String salt;
  final String hash;
  final int iterations;
  final String profileJson;
  final String accessToken;
  final String refreshToken;
  final DateTime verifiedAt; // last time the server accepted this account
  final int failedAttempts;
  final DateTime? lockedUntil;

  const OfflineAccount({
    required this.salt,
    required this.hash,
    required this.iterations,
    required this.profileJson,
    required this.accessToken,
    required this.refreshToken,
    required this.verifiedAt,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  OfflineAccount copyWith({int? failedAttempts, DateTime? lockedUntil, String? profileJson, DateTime? verifiedAt, bool clearLock = false}) =>
      OfflineAccount(
        salt: salt,
        hash: hash,
        iterations: iterations,
        profileJson: profileJson ?? this.profileJson,
        accessToken: accessToken,
        refreshToken: refreshToken,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
      );

  factory OfflineAccount.fromJson(Map<String, dynamic> json) => OfflineAccount(
        salt: json['salt'] as String,
        hash: json['hash'] as String,
        iterations: json['iterations'] as int,
        profileJson: json['profileJson'] as String,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        verifiedAt: DateTime.parse(json['verifiedAt'] as String),
        failedAttempts: json['failedAttempts'] as int? ?? 0,
        lockedUntil: json['lockedUntil'] == null ? null : DateTime.parse(json['lockedUntil'] as String),
      );

  Map<String, dynamic> toJson() => {
        'salt': salt,
        'hash': hash,
        'iterations': iterations,
        'profileJson': profileJson,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'verifiedAt': verifiedAt.toIso8601String(),
        'failedAttempts': failedAttempts,
        if (lockedUntil != null) 'lockedUntil': lockedUntil!.toIso8601String(),
      };
}
