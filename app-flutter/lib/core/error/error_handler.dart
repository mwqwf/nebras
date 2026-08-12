import 'package:dio/dio.dart';
import 'package:nebras_mobile_app/core/error/failures.dart';

/// Error Handler
/// Translates Dio exceptions into domain-friendly Failure objects
/// This is the ONLY place where Dio exceptions are handled
/// Domain layer never sees Dio exceptions
class ErrorHandler {
  ErrorHandler._();

  /// Convert DioException to Failure
  static Failure handleDioException(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutFailure(
          'Connection timeout. Please check your internet connection.',
        );

      case DioExceptionType.connectionError:
        return const NetworkFailure(
          'Network error. Please check your internet connection.',
        );

      case DioExceptionType.badResponse:
        return _handleBadResponse(exception);

      case DioExceptionType.cancel:
        return const CancellationFailure('Request was cancelled');

      case DioExceptionType.badCertificate:
        return const NetworkFailure('SSL certificate error');

      case DioExceptionType.unknown:
        return UnknownFailure(
          exception.message ?? 'An unexpected error occurred',
        );
    }
  }

  /// Handle bad response (status code errors)
  static Failure _handleBadResponse(DioException exception) {
    final statusCode = exception.response?.statusCode;
    final message = _extractErrorMessage(exception.response);

    if (statusCode == null) {
      return UnknownFailure(message);
    }

    // Client errors (4xx)
    if (statusCode >= 400 && statusCode < 500) {
      switch (statusCode) {
        case 401:
          return UnauthorizedFailure(message);
        case 403:
          return ForbiddenFailure(message);
        case 404:
          return NotFoundFailure(message);
        default:
          return ClientFailure(message, statusCode);
      }
    }

    // Server errors (5xx)
    if (statusCode >= 500) {
      return ServerFailure(message, statusCode);
    }

    return UnknownFailure(message);
  }

  /// Extract error message from response
  static String _extractErrorMessage(Response? response) {
    if (response == null) {
      return 'An error occurred';
    }

    try {
      final data = response.data;
      
      // Try to extract message from common API response formats
      if (data is Map<String, dynamic>) {
        return data['message'] ??
            data['error'] ??
            data['detail'] ??
            'Error ${response.statusCode}';
      }

      return 'Error ${response.statusCode}';
    } catch (e) {
      return 'Error ${response.statusCode}';
    }
  }

  /// Handle generic exceptions
  static Failure handleException(Object exception) {
    if (exception is DioException) {
      return handleDioException(exception);
    }

    return UnknownFailure(exception.toString());
  }
}
