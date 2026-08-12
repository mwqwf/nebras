import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/services/content_report_service.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/core/services/personalization_reset_service.dart';
import 'package:nebras_mobile_app/features/auth/model/user_profile.dart';
import 'package:nebras_mobile_app/features/auth/service/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الحالات الممكنة لشاشة الدخول.
/// - `unknown`     : لم تُستكمل محاولة الإقلاع بعد (نعرض سبلاش/لودر).
/// - `signedOut`   : لا يوجد مستخدم — يُعرض Welcome.
/// - `signedIn`    : هناك مستخدم — يُعرض HomeShell.
enum AuthStatus { unknown, signedOut, signedIn }

/// مزوّد حالة المصادقة الموحّد للتطبيق.
///
/// فلسفة التصميم:
///   • لا يحتفظ الـ UI بأي تفاصيل حول `google_sign_in` — يُكلّم هذا
///     الـ provider فقط (signInWithGoogle / signOut / currentUser).
///   • الحالة الوحيدة (SSOT) للحساب تُحفظ هنا وفي SharedPreferences كي
///     يظلّ الدخول محفوظاً بعد إعادة تشغيل التطبيق.
///   • محاولة الدخول الصامتة (`bootstrap`) تُنادى مرّة واحدة عند الإقلاع
///     حتى يظهر المستخدم مسجّلاً دون استعراض واجهة الحساب مجدّدًا.
class AuthProvider extends ChangeNotifier {
  static const _kUserKey = 'auth_current_user_v1';
  static const Duration bootstrapTimeout = Duration(seconds: 3);

  final AuthService _service;

  AuthProvider(this._service);

  AuthStatus _status = AuthStatus.unknown;
  UserProfile? _user;
  bool _isBusy = false;
  String? _lastError;

  AuthStatus get status => _status;
  UserProfile? get user => _user;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isBusy => _isBusy;
  String? get lastError => _lastError;

  /// يُستدعى مرّة واحدة عند إقلاع التطبيق.
  /// 1) يقرأ الحساب المحفوظ محلّيًا ليُظهر UI مناسب فورًا.
  /// 2) يحاول الدخول الصامت بـ Google لتجديد الجلسة في الخلفية.
  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUserKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          _user = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          _status = AuthStatus.signedIn;
        } catch (e) {
          debugPrint('[AuthProvider] cached user parse failed: $e');
          await prefs.remove(_kUserKey);
        }
      }

      final silent = await _service.signInSilently().timeout(
        bootstrapTimeout,
        onTimeout: () => null,
      );
      if (silent != null) {
        _user = silent;
        _status = AuthStatus.signedIn;
        await _persist(prefs);
      } else if (_user == null) {
        _status = AuthStatus.signedOut;
      }
    } catch (e, st) {
      debugPrint('[AuthProvider] bootstrap error: $e\n$st');
      if (_user == null) _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  /// يفتح مُنتقي حسابات Google ويُسجّل الحساب المختار. يُستخدم نفس
  /// التدفّق لشاشة "إنشاء حساب" وشاشة "تسجيل الدخول" — الفرق معنوي فقط
  /// (الرسائل التي يُعرضها UI).
  Future<bool> signInWithGoogle() async {
    if (_isBusy) return false;
    _setBusy(true);
    _lastError = null;
    try {
      final profile = await _service.signInInteractive();
      if (profile == null) {
        _setBusy(false);
        return false; // ألغى المستخدم.
      }
      _user = profile;
      _status = AuthStatus.signedIn;
      final prefs = await SharedPreferences.getInstance();
      await _persist(prefs);
      _setBusy(false);
      return true;
    } on AuthException catch (e) {
      _lastError = _friendlyError(e);
      _setBusy(false);
      return false;
    } catch (e) {
      _lastError = e.toString();
      _setBusy(false);
      return false;
    }
  }

  /// يسمح للمستخدم بتصفّح المحتوى العام بدون تسجيل دخول.
  /// المحتوى مفتوح للجميع (Firestore rules: allow read: if true)،
  /// لكن الميزات الشخصية (المحفوظات، التوصيات) تتطلّب حساباً.
  void continueAsGuest() {
    _user = null;
    _status = AuthStatus.signedIn;
    _lastError = null;
    notifyListeners();
  }

  /// الخروج من وضع الضيف والعودة إلى شاشة الترحيب (دون مسّ Google لأنّ
  /// الضيف بلا جلسة فعليّة). يلتقطه AuthGate ويُظهر WelcomeScreen.
  void exitGuest() {
    if (_user != null) return; // ليس ضيفاً — تجاهَل.
    _status = AuthStatus.signedOut;
    _lastError = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_isBusy) return;
    _setBusy(true);
    try {
      await _service.signOut();
      await PersonalizationResetService.instance.forgetAllLocalSignals();
    } finally {
      _user = null;
      _status = AuthStatus.signedOut;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUserKey);
      _setBusy(false);
    }
  }

  /// حذف الحساب نهائيّاً **داخل التطبيق**:
  ///   1) يحذف بيانات المستخدم السحابيّة المرتبطة بالـ uid (بلاغات المحتوى)
  ///      **قبل** حذف الهويّة، لأنّ قاعدة الأمان تسمح بالحذف فقط ما دام
  ///      `request.auth.uid` مطابقاً — متطلَّب سياسة حذف بيانات Google Play.
  ///   2) يحذف حساب Firebase Authentication (مع إعادة مصادقة عند الحاجة).
  ///   3) يمسح كلّ إشارات التخصيص المحليّة (اهتمامات/سلوك/تابع التصفّح).
  ///   4) يزيل الجلسة المحفوظة ويعيد الحالة إلى signedOut.
  /// مسح المفضّلة المحليّة يتمّ من الواجهة (SavedProvider) قبل الاستدعاء.
  Future<bool> deleteAccount() async {
    if (_isBusy) return false;
    _setBusy(true);
    _lastError = null;
    try {
      // أفضل جهد: حذف البلاغات السحابيّة قبل فقدان الهويّة. لا نُفشل الحذف
      // كلّه إن تعذّر هذا (قد تمنعه قاعدة أمان قديمة أو انقطاع الشبكة).
      try {
        await ContentReportService.instance.deleteReportsForCurrentUser();
      } catch (e) {
        debugPrint('[auth] cloud report cleanup skipped: $e');
      }
      await _service.deleteAccount();
      await PersonalizationResetService.instance.forgetAllLocalSignals();
      // مسح قائمة المحتوى المُخفى محلّياً ضمن تنظيف بيانات المستخدم.
      await HiddenContentService.instance.clearAll();
      _user = null;
      _status = AuthStatus.signedOut;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUserKey);
      _setBusy(false);
      return true;
    } on AuthException catch (e) {
      _lastError = e.message;
      _setBusy(false);
      return false;
    } catch (e) {
      _lastError = e.toString();
      _setBusy(false);
      return false;
    }
  }

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> _persist(SharedPreferences prefs) async {
    if (_user == null) {
      await prefs.remove(_kUserKey);
      return;
    }
    await prefs.setString(_kUserKey, jsonEncode(_user!.toJson()));
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  /// تحوِّل رموز الأخطاء الشائعة إلى رسائل قابلة للعرض. نُبقيها مفاتيح ترجمة
  /// قصيرة ومفهومة حتى يمكن للـ UI تمريرها إلى `.tr()` مباشرة.
  ///
  /// ملاحظة هامّة لرمز `sign_in_failed` (ApiException: 10 / DEVELOPER_ERROR):
  /// غالباً عدم تطابق `applicationId` + SHA-1 مع `google-services.json`.
  /// راجع docs/GOOGLE_SIGNIN_ANDROID.md (جدول debug vs متجر و build.gradle.kts).
  String _friendlyError(AuthException e) {
    switch (e.code) {
      case 'network_error':
        return 'Auth error network'; // ترجمة في الـ UI
      case 'sign_in_canceled':
      case 'sign_in_required':
        return 'Auth error canceled';
      case 'sign_in_failed':
        // لا نعرض تفاصيل تقنية للمستخدم النهائي، لكنّنا نطبع Hint واضح
        // في console للمطوّر.
        debugPrint(
          '[AuthProvider] sign_in_failed = DEVELOPER_ERROR (ApiException 10). '
          'تحقّق من تسجيل بصمة SHA-1 في Firebase Console وتحديث '
          'google-services.json. راجع تعليق _friendlyError.',
        );
        return 'Auth error sign_in_failed';
      default:
        return e.message;
    }
  }
}
