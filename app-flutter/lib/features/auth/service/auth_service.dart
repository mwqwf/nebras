import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nebras_mobile_app/features/auth/model/user_profile.dart';

/// واجهة رفيعة تلفّ `google_sign_in` و `firebase_auth` لعزل بقيّة التطبيق
/// عن تفاصيل الحزمة.
///
/// Android: `applicationId` يختلف بين `flutter run` و release — راجع
/// [docs/GOOGLE_SIGNIN_ANDROID.md](../../../docs/GOOGLE_SIGNIN_ANDROID.md).
///
/// تصميم تدفّق الدخول:
///   1. `signInSilently()` عند الإقلاع — يستعيد الحساب إن كان المستخدم
///       قد سجّل دخوله سابقاً، ويعيد `null` بسلاسة إن لم يفعل.
///   2. `signInInteractive()` عند ضغط المستخدم على زرّ "الدخول بـ Google"
///       — يفتح نافذة اختيار الحساب الخاصّة بنظام Android ويسجل الدخول في Firebase.
class AuthService {
  AuthService()
    : _googleSignIn = GoogleSignIn(
        scopes: const ['email', 'profile', 'openid'],
        // Web client (OAuth type 3) — مطلوب لـ Firebase Auth idToken على Android.
        serverClientId:
            '412379996427-0i55p23iunk93tilvje5442d6e42s4p9.apps.googleusercontent.com',
      ),
      _auth = FirebaseAuth.instance;

  final GoogleSignIn _googleSignIn;
  final FirebaseAuth _auth;

  /// محاولة دخول صامتة — لا تُظهر أيّ واجهة. تُستخدم أثناء الإقلاع.
  Future<UserProfile?> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return null;

      return await _firebaseAuthWithGoogle(account);
    } catch (e, st) {
      debugPrint('[AuthService] signInSilently failed: $e\n$st');
      return null;
    }
  }

  /// دخول تفاعلي — يفتح مُنتقي حسابات Google على الجهاز ويسجل في Firebase.
  Future<UserProfile?> signInInteractive() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return null;

      return await _firebaseAuthWithGoogle(account);
    } on PlatformException catch (e) {
      debugPrint(
        '[AuthService] signIn PlatformException: ${e.code} ${e.message}',
      );
      throw AuthException(
        code: e.code,
        message: e.message ?? 'Google sign-in failed',
      );
    } catch (e, st) {
      debugPrint('[AuthService] signIn unknown error: $e\n$st');
      throw AuthException(code: 'unknown', message: e.toString());
    }
  }

  Future<UserProfile?> _firebaseAuthWithGoogle(
    GoogleSignInAccount account,
  ) async {
    final GoogleSignInAuthentication googleAuth = await account.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential = await _auth.signInWithCredential(
      credential,
    );
    return _mapAccount(userCredential.user);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('[AuthService] signOut error: $e');
    }
  }

  /// حذف الحساب نهائيّاً من Firebase Authentication. إن طلب Firebase
  /// إعادة مصادقة حديثة (`requires-recent-login`) نُعيد المصادقة بـ Google
  /// ثمّ نحذف. في كلّ الأحوال نُسجّل الخروج من Google بعدها.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        final account = await _googleSignIn.signIn();
        if (account == null) {
          throw const AuthException(
            code: 'reauth_cancelled',
            message: 'Re-authentication required to delete the account',
          );
        }
        final googleAuth = await account.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
        await user.delete();
      } else {
        throw AuthException(code: e.code, message: e.message ?? 'Delete failed');
      }
    } finally {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    try {
      await _auth.signOut();
      await _googleSignIn.disconnect();
    } catch (_) {
      /* قد يرمي إن كان المستخدم مسجّلاً أصلاً — نتجاهل بأمان. */
    }
  }

  UserProfile? _mapAccount(User? user) {
    if (user == null) return null;
    return UserProfile(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!
          : (user.email != null ? user.email!.split('@').first : 'User'),
      photoUrl: user.photoURL,
      signedInAt: DateTime.now(),
    );
  }
}

class AuthException implements Exception {
  final String code;
  final String message;
  const AuthException({required this.code, required this.message});

  @override
  String toString() => 'AuthException($code): $message';
}
