import 'package:dio/dio.dart';
import 'package:nebras_mobile_app/core/network/api_constants.dart';

/// Retry Interceptor
/// Adds basic retry support for safe network calls
/// Limited retry count to avoid aggressive retries
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration retryDelay;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = ApiConstants.maxRetries,
    this.retryDelay = ApiConstants.retryDelay,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Only retry on specific error types
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    // Check retry count
    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;
    if (retryCount >= maxRetries) {
      return handler.next(err);
    }

    // Wait before retry
    await Future.delayed(retryDelay);

    // Increment retry count
    err.requestOptions.extra['retryCount'] = retryCount + 1;

    try {
      // Retry the request
      final response = await dio.fetch(err.requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Determine if request should be retried
  bool _shouldRetry(DioException err) {
    // Only retry safe methods (GET, HEAD, OPTIONS)
    final method = err.requestOptions.method.toUpperCase();
    if (!['GET', 'HEAD', 'OPTIONS'].contains(method)) {
      return false;
    }

    // Retry on timeout
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }

    // Retry on connection error
    if (err.type == DioExceptionType.connectionError) {
      return true;
    }

    // Retry on specific status codes (5xx server errors)
    final statusCode = err.response?.statusCode;
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return true;
    }

    return false;
  }
}
