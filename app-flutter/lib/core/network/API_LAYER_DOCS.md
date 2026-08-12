# API Layer Documentation

## Overview

Production-ready API layer with centralized configuration, error handling, and retry logic.

---

## Architecture

### Layer Responsibilities

**DATA LAYER:**
- Uses `DioClient` for HTTP requests
- Catches `DioException`
- Converts to `Failure` using `ErrorHandler`
- Returns `Failure` to domain

**DOMAIN LAYER:**
- Receives `Failure` objects only
- Never sees `DioException`
- Never depends on Dio
- Pure Dart

**PRESENTATION LAYER:**
- Receives `Failure` from use cases
- Displays user-friendly messages
- Never parses Dio exceptions

---

## Files

### 1. `api_constants.dart`

**Purpose:** Centralized API configuration

**Contents:**
- Base URLs
- API version
- Timeouts
- Retry configuration
- All endpoints

**Rules:**
- NO hardcoded URLs anywhere else
- All endpoints defined here
- Easy to update for different environments

**Example:**
```dart
// Base URL
ApiConstants.baseUrl // 'https://nebras.app'

// Endpoints
ApiConstants.booksEndpoint // '/api/v1/books'
ApiConstants.bookDetail('123') // '/api/v1/books/123'
```

### 2. `dio_client.dart`

**Purpose:** Centralized Dio configuration

**Features:**
- Singleton instance
- Configured once
- Default headers
- Timeouts
- Interceptors (logging + error)
- Separate download client

**Usage:**
```dart
// Get configured Dio instance
final dio = DioClient.instance;

// For downloads
final downloadDio = DioClient.createDownloadClient();
```

### 3. `retry_interceptor.dart`

**Purpose:** Automatic retry for failed requests

**Features:**
- Only retries safe methods (GET, HEAD, OPTIONS)
- Limited retry count (default: 3)
- Configurable delay between retries
- Retries on:
  - Timeouts
  - Connection errors
  - 5xx server errors

**Configuration:**
```dart
ApiConstants.maxRetries // 3
ApiConstants.retryDelay // 2 seconds
```

### 4. `failures.dart`

**Purpose:** Domain-friendly error types

**Failure Types:**
- `NetworkFailure` - Connection issues
- `ServerFailure` - 5xx errors
- `ClientFailure` - 4xx errors
- `TimeoutFailure` - Request timeout
- `CancellationFailure` - User cancelled
- `NotFoundFailure` - 404
- `UnauthorizedFailure` - 401
- `ForbiddenFailure` - 403
- `ValidationFailure` - Input validation
- `CacheFailure` - Cache errors
- `UnknownFailure` - Unexpected errors

**All failures extend `Failure` base class**

### 5. `error_handler.dart`

**Purpose:** Translate Dio exceptions to Failures

**Key Method:**
```dart
ErrorHandler.handleDioException(DioException exception)
  → Failure
```

**This is the ONLY place where Dio exceptions are handled**

---

## Usage in Data Layer

### Example: Book Remote Data Source

```dart
class BookRemoteDataSource {
  final Dio dio;
  
  BookRemoteDataSource(this.dio);
  
  Future<BookModel> getBook(String id) async {
    try {
      final response = await dio.get(
        ApiConstants.bookDetail(id),
      );
      
      return BookModel.fromJson(response.data);
    } on DioException catch (e) {
      throw ErrorHandler.handleDioException(e);
    } catch (e) {
      throw ErrorHandler.handleException(e);
    }
  }
}
```

### Example: Repository Implementation

```dart
class BookRepoImplem implements BookRepos {
  final BookRemoteDataSource remote;
  
  @override
  Future<Either<Failure, Book>> getBook(String id) async {
    try {
      final bookModel = await remote.getBook(id);
      return Right(bookModel.toEntity());
    } on Failure catch (failure) {
      return Left(failure);
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
```

---

## Error Flow

```
Network Request
  ↓
DioException thrown
  ↓
Data Layer catches
  ↓
ErrorHandler.handleDioException()
  ↓
Converts to Failure
  ↓
Repository catches Failure
  ↓
Returns Either<Failure, Data>
  ↓
UseCase receives Either
  ↓
Provider handles Failure
  ↓
UI displays user-friendly message
```

---

## Retry Logic

### When Retry Happens

**Automatic retry for:**
- GET requests
- HEAD requests
- OPTIONS requests

**On these errors:**
- Connection timeout
- Receive timeout
- Connection error
- 5xx server errors

**NOT retried:**
- POST, PUT, DELETE (not safe to retry)
- 4xx client errors
- Cancellation
- After max retries reached

### Configuration

```dart
// In api_constants.dart
static const int maxRetries = 3;
static const Duration retryDelay = Duration(seconds: 2);
```

### Example Flow

```
GET /api/v1/books/123
  ↓
Connection timeout
  ↓
Wait 2 seconds
  ↓
Retry 1: GET /api/v1/books/123
  ↓
Connection timeout
  ↓
Wait 2 seconds
  ↓
Retry 2: GET /api/v1/books/123
  ↓
Success ✅
```

---

## Timeouts

### Default Timeouts

```dart
connectTimeout: 30 seconds
receiveTimeout: 60 seconds
sendTimeout: 30 seconds
```

### Download Client

```dart
connectTimeout: 30 seconds
receiveTimeout: 10 minutes  // Longer for large files
sendTimeout: 30 seconds
```

---

## Headers

### Default Headers

```dart
'Content-Type': 'application/json'
'Accept': 'application/json'
```

### Adding Custom Headers

```dart
// In data source
final response = await dio.get(
  endpoint,
  options: Options(
    headers: {
      'Authorization': 'Bearer $token',
    },
  ),
);
```

---

## Interceptors

### Log Interceptor

**Purpose:** Debug logging

**Logs:**
- Request URL
- Request headers
- Request body
- Response body
- Errors

**Production:** Use proper logging service

### Error Interceptor

**Purpose:** Consistent error logging

**Logs:**
- Error type
- Error message

---

## Best Practices

### ✅ DO

**In Data Layer:**
- Use `DioClient.instance`
- Use `ApiConstants` for endpoints
- Catch `DioException`
- Convert to `Failure` using `ErrorHandler`
- Return `Failure` to domain

**In Domain Layer:**
- Work with `Failure` objects
- Never import Dio
- Never catch `DioException`

**In Presentation Layer:**
- Handle `Failure` from use cases
- Display user-friendly messages
- Never parse Dio exceptions

### ❌ DON'T

- Hardcode URLs
- Create multiple Dio instances
- Handle Dio exceptions in domain
- Handle Dio exceptions in presentation
- Retry unsafe methods (POST, PUT, DELETE)
- Ignore error handling

---

## Testing

### Mocking Dio

```dart
class MockDio extends Mock implements Dio {}

test('should return book on success', () async {
  // Arrange
  when(mockDio.get(any)).thenAnswer(
    (_) async => Response(
      data: {'id': '123', 'title': 'Test'},
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    ),
  );
  
  // Act
  final result = await dataSource.getBook('123');
  
  // Assert
  expect(result, isA<BookModel>());
});
```

### Testing Error Handling

```dart
test('should throw NetworkFailure on connection error', () async {
  // Arrange
  when(mockDio.get(any)).thenThrow(
    DioException(
      type: DioExceptionType.connectionError,
      requestOptions: RequestOptions(path: ''),
    ),
  );
  
  // Act & Assert
  expect(
    () => dataSource.getBook('123'),
    throwsA(isA<NetworkFailure>()),
  );
});
```

---

## Migration Guide

### Before

```dart
// Hardcoded URL
final response = await dio.get('https://nebras.app/api/books/123');

// No error handling
final book = BookModel.fromJson(response.data);
```

### After

```dart
// Use ApiConstants
final response = await dio.get(ApiConstants.bookDetail('123'));

// Proper error handling
try {
  final book = BookModel.fromJson(response.data);
  return book;
} on DioException catch (e) {
  throw ErrorHandler.handleDioException(e);
}
```

---

## Summary

**✅ Centralized Configuration**
- All URLs in `ApiConstants`
- Single Dio instance
- Consistent timeouts

**✅ Error Handling**
- Dio exceptions → Failures
- Domain never sees Dio
- Clean error propagation

**✅ Retry Logic**
- Automatic for safe methods
- Limited retry count
- Configurable delay

**✅ Production Ready**
- Proper logging
- Timeout handling
- Scalable architecture

Ready for audio streaming, video streaming, and all future features.
