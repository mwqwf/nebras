import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/network/api_constants.dart';
import 'package:nebras_mobile_app/core/network/retry_interceptor.dart';

/// DioClient
/// Centralized Dio configuration
/// Configured once with timeouts, headers, and interceptors
class DioClient {
  DioClient._();

  static Dio? _instance;

  /// Get singleton Dio instance
  static Dio get instance {
    _instance ??= _createDio();
    return _instance!;
  }

  /// Create and configure Dio instance
  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors — LogInterceptor مقصور على التطوير فقط كي لا
    // تُسرَّب الهيدرز (Authorization) ومحتوى الطلب/الردّ في Release.
    if (kDebugMode) {
      dio.interceptors.add(_createLogInterceptor());
    }
    // إعادة المحاولة على الطلبات الآمنة (GET/HEAD/OPTIONS) عند مهلات/أخطاء
    // الشبكة و5xx — مهمّ لـ cold start خادم Render (ثوانٍ طويلة لأوّل طلب).
    dio.interceptors.add(RetryInterceptor(dio: dio));
    dio.interceptors.add(_createErrorInterceptor());

    return dio;
  }

  /// Create log interceptor for debugging
  static LogInterceptor _createLogInterceptor() {
    return LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: false,
      responseBody: true,
      error: true,
      logPrint: (obj) {
        // debugPrint آمن: throttled وتختفي في Release لأن LogInterceptor
        // نفسه لا يُركَّب أصلاً خارج kDebugMode.
        debugPrint(obj.toString());
      },
    );
  }

  /// Create error interceptor for consistent error handling
  static InterceptorsWrapper _createErrorInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) {
        // تسجيل تفاصيل الخطأ في التطوير فقط. في Release نكتفي
        // بتمرير الخطأ لمُعالج Dio بدون أي طباعة في الـ logs.
        if (kDebugMode) {
          debugPrint('DIO ERROR: ${error.type}');
          debugPrint('MESSAGE: ${error.message}');
        }
        handler.next(error);
      },
    );
  }

  /// Create Dio instance for file downloads
  /// Separate configuration for download operations
  static Dio createDownloadClient() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: const Duration(minutes: 10), // Longer timeout for downloads
        sendTimeout: ApiConstants.sendTimeout,
        responseType: ResponseType.bytes,
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(_createLogInterceptor());
    }

    return dio;
  }

  /// Reset instance (useful for testing)
  static void reset() {
    _instance = null;
  }
}
