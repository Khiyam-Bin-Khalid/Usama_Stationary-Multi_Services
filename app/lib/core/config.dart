import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class AppConfig {
  AppConfig._();

  /// Override at build/run time with:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000/api
  static const _override = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:4000/api';
    try {
      // Android emulator maps the host machine to 10.0.2.2, not localhost.
      if (Platform.isAndroid) return 'http://10.0.2.2:4000/api';
    } catch (_) {
      // Platform.* throws on web, already handled by kIsWeb above.
    }
    return 'http://localhost:4000/api';
  }

  /// Backend origin without the /api suffix, for resolving uploaded file
  /// URLs like /uploads/xyz.png returned by the API.
  static String get mediaBaseUrl {
    final base = apiBaseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }
}
