import 'package:equatable/equatable.dart';

/// Base Failure class
/// All failures in the domain layer extend this
abstract class Failure extends Equatable {
  final String message;
  final int? statusCode;

  const Failure(this.message, [this.statusCode]);

  @override
  List<Object?> get props => [message, statusCode];
}

/// Network-related failures
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network error occurred']);
}

/// Server-related failures (5xx errors)
class ServerFailure extends Failure {
  const ServerFailure([
    super.message = 'Server error occurred',
    super.statusCode,
  ]);
}

/// Client-related failures (4xx errors)
class ClientFailure extends Failure {
  const ClientFailure([
    super.message = 'Client error occurred',
    super.statusCode,
  ]);
}

/// Timeout failures
class TimeoutFailure extends Failure {
  const TimeoutFailure([super.message = 'Request timeout']);
}

/// Cancellation failures
class CancellationFailure extends Failure {
  const CancellationFailure([super.message = 'Request cancelled']);
}

/// Cache failures
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error occurred']);
}

/// Unknown failures
class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unknown error occurred']);
}

/// Validation failures
class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Validation error']);
}

/// Not found failures (404)
class NotFoundFailure extends Failure {
  const NotFoundFailure([String message = 'Resource not found'])
    : super(message, 404);
}

/// Unauthorized failures (401)
class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([String message = 'Unauthorized access'])
    : super(message, 401);
}

/// Forbidden failures (403)
class ForbiddenFailure extends Failure {
  const ForbiddenFailure([String message = 'Access forbidden'])
    : super(message, 403);
}
