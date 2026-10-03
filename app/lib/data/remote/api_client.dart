import 'package:dio/dio.dart';
import '../../core/config.dart';
import 'token_storage.dart';

/// Thin wrapper around Dio: attaches the access token to every request and
/// transparently refreshes it once on a 401 before retrying, so callers
/// never have to think about token expiry.
class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;
  bool _isRefreshing = false;

  ApiClient(this.tokenStorage) : dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 10))) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          final isUnauthorized = error.response?.statusCode == 401;
          final isRetry = error.requestOptions.extra['retried'] == true;
          if (isUnauthorized && !isRetry && !_isRefreshing) {
            _isRefreshing = true;
            try {
              final refreshed = await _refreshToken();
              _isRefreshing = false;
              if (refreshed) {
                final opts = error.requestOptions;
                opts.extra['retried'] = true;
                final token = await tokenStorage.accessToken;
                opts.headers['Authorization'] = 'Bearer $token';
                final response = await dio.fetch(opts);
                return handler.resolve(response);
              }
            } catch (_) {
              _isRefreshing = false;
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await tokenStorage.refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl)).post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      await tokenStorage.updateAccessToken(response.data['accessToken'] as String);
      return true;
    } catch (_) {
      // Hard-wipe tokens and credential cache when the refresh token itself
      // is rejected — the user must log in online again.
      await tokenStorage.clearAll();
      return false;
    }
  }
}

class ApiException implements Exception {
  final String message;
  final List<dynamic>? details;
  // True when the server was never reached (offline, timeout, DNS, etc.) as
  // opposed to reaching it and getting a real error response (400/403/...).
  // Callers that fall back to offline queueing (e.g. PosRepository) key off
  // this — a genuine "insufficient stock" rejection should surface as an
  // error, not silently disappear into the offline queue.
  final bool isNetworkError;

  ApiException(this.message, [this.details, this.isNetworkError = false]);

  factory ApiException.fromDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return ApiException(data['error'] as String, data['details'] as List<dynamic>?, false);
    }
    const networkTypes = {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.unknown,
    };
    return ApiException(e.message ?? 'Network error', null, networkTypes.contains(e.type));
  }

  @override
  String toString() => details != null && details!.isNotEmpty ? '$message: ${details!.join(', ')}' : message;
}
