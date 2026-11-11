import 'package:dio/dio.dart';
import '../../core/config.dart';
import 'token_storage.dart';

/// Thin wrapper around Dio: attaches the access token to every request and
/// transparently refreshes it once on a 401 before retrying, so callers
/// never have to think about token expiry.
class ApiClient {
  final Dio dio;
  final TokenStorage tokenStorage;
  final String _baseUrl;
  Future<bool>? _refreshing;

  ApiClient(this.tokenStorage, {String? baseUrl})
      : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        dio = Dio(BaseOptions(baseUrl: baseUrl ?? AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 10))) {
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
          if (isUnauthorized && !isRetry) {
            try {
              // Parallel 401s share one refresh instead of racing each other.
              final refreshed = await (_refreshing ??= _refreshToken().whenComplete(() => _refreshing = null));
              if (refreshed) {
                final opts = error.requestOptions;
                opts.extra['retried'] = true;
                final token = await tokenStorage.accessToken;
                opts.headers['Authorization'] = 'Bearer $token';
                final response = await dio.fetch(opts);
                return handler.resolve(response);
              }
            } on DioException catch (e) {
              return handler.next(e);
            } catch (_) {
              // Fall through and report the original 401.
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
      final response = await Dio(BaseOptions(baseUrl: _baseUrl, connectTimeout: const Duration(seconds: 10))).post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      await tokenStorage.updateAccessToken(response.data['accessToken'] as String);
      return true;
    } on DioException catch (e) {
      // Only a real rejection ends the session. A dropped connection during a
      // refresh must not log the user out or lose their offline access.
      final status = e.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) await tokenStorage.clearAll();
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
  final int? statusCode;

  ApiException(this.message, [this.details, this.isNetworkError = false, this.statusCode]);

  /// The server can't do its job right now: unreachable, or reachable but
  /// failing (5xx, e.g. the API is up but its database connection dropped).
  /// Anything an offline-capable feature can safely retry later belongs here.
  bool get isServerDown => isNetworkError || (statusCode != null && statusCode! >= 500);

  factory ApiException.fromDioError(DioException e) {
    final data = e.response?.data;
    final status = e.response?.statusCode;
    if (data is Map && data['error'] != null) {
      return ApiException(data['error'] as String, data['details'] as List<dynamic>?, false, status);
    }
    const networkTypes = {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.unknown,
    };
    if (networkTypes.contains(e.type)) {
      return ApiException('You are offline. This needs a connection to the server.', null, true);
    }
    return ApiException(e.message ?? 'Request failed', null, false, status);
  }

  @override
  String toString() => details != null && details!.isNotEmpty ? '$message: ${details!.join(', ')}' : message;
}
