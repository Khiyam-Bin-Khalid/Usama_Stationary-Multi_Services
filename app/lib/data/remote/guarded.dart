import 'package:dio/dio.dart';
import 'api_client.dart';

Future<T> guarded<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on DioException catch (e) {
    throw ApiException.fromDioError(e);
  }
}
