import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

/// خطأ موسَّع من طبقة الـ API — يحمل رمز الحالة والرسالة العربيّة الجاهزة للعرض،
/// مطابق لما يبنيه `_authedFetch.js` في لوحة الويب.
class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.reason, this.payload});

  final String message;
  final int status;
  final String? reason;
  final dynamic payload;

  @override
  String toString() => 'ApiException($status): $message';
}

/// طبقة مشتركة لإرسال طلبات JSON مصادَقة بـ `Authorization: Bearer <ID token>`
/// إلى نقاط الـ API الإداريّة للوحة (`/api/admin/*`, `/api/notify/*`,
/// `/api/auth/*`). نظير `authedJson` / `rawAuthedFetch`.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();

  Uri _url(String path) {
    if (path.startsWith('http')) return Uri.parse(path);
    final base = AppConfig.backendBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  /// رمز Firebase ID طازج للمستخدم الحاليّ (أو null إن لم يُسجَّل الدخول).
  Future<String?> _freshBearer({bool forceRefresh = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
    }
  }

  /// طلب JSON مصادَق. يرمي [ApiException] إن لم يكن 2xx.
  Future<dynamic> authedJson(
    String path, {
    String method = 'GET',
    Object? body,
    Map<String, String>? query,
  }) async {
    var uri = _url(path);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    final token = await _freshBearer();
    if (token == null) {
      throw ApiException('يجب تسجيل الدخول لإجراء هذه العملية.',
          status: 401, reason: 'not_signed_in');
    }

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    http.Response res;
    try {
      final m = method.toUpperCase();
      final encoded = body == null ? null : jsonEncode(body);
      switch (m) {
        case 'GET':
          res = await _http.get(uri, headers: headers);
          break;
        case 'POST':
          res = await _http.post(uri, headers: headers, body: encoded);
          break;
        case 'PATCH':
          res = await _http.patch(uri, headers: headers, body: encoded);
          break;
        case 'PUT':
          res = await _http.put(uri, headers: headers, body: encoded);
          break;
        case 'DELETE':
          res = await _http.delete(uri, headers: headers, body: encoded);
          break;
        default:
          res = await _http.get(uri, headers: headers);
      }
    } catch (e) {
      throw ApiException(
        'تعذّر الاتصال بالخادم — تأكد من اتصال الإنترنت ثمّ أعد المحاولة.',
        status: 0,
        reason: 'network_error',
      );
    }

    dynamic payload;
    final ct = res.headers['content-type'] ?? '';
    if (ct.contains('application/json') && res.body.isNotEmpty) {
      try {
        payload = jsonDecode(res.body);
      } catch (_) {
        payload = null;
      }
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        _buildErrorMessage(res.statusCode, payload),
        status: res.statusCode,
        reason: (payload is Map)
            ? (payload['reason'] ?? payload['error'])?.toString()
            : null,
        payload: payload,
      );
    }

    return payload;
  }

  /// نسخة خامّ ترجع Response مباشرة (لرفع FormData/multipart إن لزم).
  Future<http.StreamedResponse> rawAuthed(http.BaseRequest request) async {
    final token = await _freshBearer();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _http.send(request);
  }

  String _buildErrorMessage(int status, dynamic payload) {
    final serverMsg =
        (payload is Map && payload['message'] != null) ? '${payload['message']}'.trim() : '';
    if (serverMsg.isNotEmpty) return serverMsg;

    final reason = (payload is Map) ? payload['reason']?.toString() : null;
    final forceSignOut = (payload is Map) ? payload['forceSignOut'] == true : false;

    if (status == 401) return 'يجب تسجيل الدخول لإجراء هذه العملية.';
    if (status == 403) {
      if (reason == 'access_suspended' || forceSignOut) {
        return 'تم تعليق وصولك من قبل الإدارة.';
      }
      if (reason == 'role_not_allowed') return 'صلاحيّاتك لا تسمح بإتمام هذه العملية.';
      if (reason == 'not_in_admins') return 'حسابك غير مسجَّل كعضو في إدارة لوحة التحكّم.';
      return 'الوصول مرفوض.';
    }
    if (status == 404) return 'لم يُعثر على العنصر المطلوب.';
    if (status == 409) return 'تعارض في البيانات — حاول مرّة أخرى.';
    if (status == 501) {
      return 'خاصيّة الكتابة عبر السيرفر غير مفعّلة لهذا المشروع — يحتاج المسؤول إلى ضبط مفاتيح الخدمة.';
    }
    if (status == 400) {
      return 'طلب غير صحيح (${(payload is Map) ? payload['reason'] ?? 'bad_request' : 'bad_request'}).';
    }
    if (status >= 500) return 'حدث خطأ غير متوقَّع على الخادم — حاول مرّة أخرى لاحقاً.';
    return 'تعذّر إتمام العملية (HTTP $status).';
  }
}
