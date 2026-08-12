import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/config.dart';

enum DashRole { owner, supervisor }

/// حالة المصادقة — نظير `auth.svelte.js` + تدفّق `login/+page.svelte`.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _init();
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile', 'openid'],
    serverClientId: AppConfig.googleServerClientId,
  );

  User? user;
  bool authorized = false;
  bool isLoading = true;
  bool needsOwnerCode = false;
  DashRole? role;
  bool isBlocked = false;
  String viewMode = 'admin'; // admin | moderator
  String? errorMessage;

  bool get isOwner => role == DashRole.owner;
  bool get isSignedIn => user != null;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    viewMode = prefs.getString('nebras_view_mode') ?? 'admin';

    FirebaseAuth.instance.authStateChanges().listen((u) async {
      user = u;
      if (u == null) {
        authorized = false;
        needsOwnerCode = false;
        role = null;
        isBlocked = false;
        isLoading = false;
        notifyListeners();
        return;
      }
      // جلسة دائمة (مثل التطبيق العام): إن سبق اعتماد هذا الحساب على هذا
      // الجهاز ندخل فوراً دون انتظار الخادم، ثم نتحقّق بصمت في الخلفيّة —
      // لا يُطرد المستخدم إلا برفض صريح (إزالة/إيقاف)، لا بانقطاع شبكة.
      final cachedAuthorized =
          prefs.getBool('nebras_authorized_${u.uid}') ?? false;
      if (cachedAuthorized) {
        authorized = true;
        role = _mapRole(prefs.getString('nebras_role_${u.uid}'));
        isLoading = false;
        notifyListeners();
        await _checkAuthorization(background: true);
      } else {
        await _checkAuthorization();
      }
    });
  }

  Future<String?> _idToken({bool force = false}) async {
    final u = FirebaseAuth.instance.currentUser;
    return u?.getIdToken(force);
  }

  /// استدعاء `/api/auth/check` لتحديد الصلاحيّة.
  ///
  /// [background]: فحص صامت بعد دخول متفائل من الكاش — لا يعرض تحميلاً،
  /// ولا يُسقط الاعتماد عند خطأ شبكة/خادم عابر؛ يُسقطه فقط عند ردّ صريح
  /// بعدم الصلاحيّة (إزالة/إيقاف من الإدارة).
  Future<void> _checkAuthorization({bool background = false}) async {
    if (!background) {
      isLoading = true;
      notifyListeners();
    }
    try {
      final token = await _idToken();
      final res = await ApiClient.instance.authedJson(
        '/api/auth/check',
        method: 'POST',
        body: {'idToken': token},
      );
      final map = (res as Map?)?.cast<String, dynamic>() ?? {};
      if (map['authorized'] == true) {
        authorized = true;
        needsOwnerCode = false;
        isBlocked = false;
        role = _mapRole(map['user']?['role']);
        await _cacheAuthorization(true);
        // الخادم زامن الـ custom claims أثناء الفحص — نجدّد التوكن ليحملها
        // فوراً (يهمّ قواعد Firestore/Storage، وخاصّة ترقية مالك جديدة).
        try {
          await FirebaseAuth.instance.currentUser?.getIdToken(true);
        } catch (_) {}
      } else if (map['blocked'] == true) {
        authorized = false;
        isBlocked = true;
        needsOwnerCode = false;
        await _cacheAuthorization(false);
      } else if (map['needsOwnerCode'] == true) {
        authorized = false;
        needsOwnerCode = true;
        await _cacheAuthorization(false);
      } else {
        authorized = false;
        await _cacheAuthorization(false);
      }
    } catch (e) {
      // خطأ عابر (شبكة/خادم): في الفحص الصامت نُبقي الجلسة كما هي.
      if (!background) {
        authorized = false;
        errorMessage = e is ApiException ? e.message : '$e';
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// حفظ/مسح الاعتماد المحلّي الدائم لهذا الحساب.
  Future<void> _cacheAuthorization(bool ok) async {
    final uid = user?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (ok) {
      await prefs.setBool('nebras_authorized_$uid', true);
      await prefs.setString('nebras_role_$uid',
          role == DashRole.owner ? 'owner' : 'supervisor');
    } else {
      await prefs.remove('nebras_authorized_$uid');
      await prefs.remove('nebras_role_$uid');
    }
  }

  DashRole? _mapRole(dynamic r) {
    final s = '$r';
    if (s == 'owner') return DashRole.owner;
    if (s == 'supervisor' || s == 'admin' || s == 'moderator') {
      return DashRole.supervisor;
    }
    return null;
  }

  // ─── تسجيل الدخول بـ Google ──────────────────────────────

  Future<void> signInWithGoogle() async {
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        isLoading = false;
        notifyListeners();
        return; // ألغى المستخدم.
      }
      final googleAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      // authStateChanges سيُطلق _checkAuthorization.
    } catch (e) {
      errorMessage = 'فشل تسجيل الدخول بـ Google: $e';
      isLoading = false;
      notifyListeners();
    }
  }

  // ─── رمز اعتماد المالك ───────────────────────────────────

  /// يطلب إرسال رمز إلى بريد المالك. يُرجع رسالة للحالة.
  Future<String> requestOwnerCode() async {
    final token = await _idToken();
    final res = await ApiClient.instance.authedJson(
      '/api/auth/request-code',
      method: 'POST',
      body: {'idToken': token},
    );
    final map = (res as Map?)?.cast<String, dynamic>() ?? {};
    if (map['ok'] == true) {
      return map['delivered'] == true
          ? 'تم إرسال رمز التحقّق إلى بريد المالك.'
          : 'تم توليد الرمز (تحقّق من إعداد البريد لدى المالك).';
    }
    if (map['reason'] == 'rate_limited') {
      return 'طلب متكرّر بسرعة — انتظر ${map['retryAfterSec'] ?? ''} ثانية.';
    }
    if (map['reason'] == 'already_authorized') {
      await _checkAuthorization();
      return 'حسابك مُعتمَد بالفعل.';
    }
    return 'تعذّر إرسال الرمز.';
  }

  /// يتحقّق من الرمز ويعتمد الحساب. يُرجع true عند النجاح.
  Future<bool> verifyOwnerCode(String code) async {
    final token = await _idToken();
    final res = await ApiClient.instance.authedJson(
      '/api/auth/verify-code',
      method: 'POST',
      body: {'idToken': token, 'code': code.trim()},
    );
    final map = (res as Map?)?.cast<String, dynamic>() ?? {};
    if (map['ok'] == true) {
      needsOwnerCode = false;
      await _checkAuthorization();
      return true;
    }
    final reason = '${map['reason']}';
    errorMessage = switch (reason) {
      'no_code' => 'لم يُطلب رمز بعد.',
      'expired' => 'انتهت صلاحيّة الرمز — اطلب رمزاً جديداً.',
      'invalid' => 'الرمز غير صحيح.',
      'too_many_attempts' => 'محاولات كثيرة — اطلب رمزاً جديداً.',
      _ => 'تعذّر التحقّق من الرمز.',
    };
    notifyListeners();
    return false;
  }

  // ─── أخرى ────────────────────────────────────────────────

  Future<void> toggleViewMode() async {
    viewMode = viewMode == 'admin' ? 'moderator' : 'admin';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nebras_view_mode', viewMode);
    notifyListeners();
  }

  Future<void> setViewMode(String mode) async {
    viewMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nebras_view_mode', mode);
    notifyListeners();
  }

  Future<void> signOut() async {
    // تسجيل الخروج الصريح يمسح الاعتماد المحلّي — فيُطلب الدخول مجدّداً.
    await _cacheAuthorization(false);
    try {
      await FirebaseAuth.instance.signOut();
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<void> refreshAuthorization() => _checkAuthorization();
}
