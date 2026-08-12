/// ثوابت التهيئة العامّة للوحة تحكّم نبراس (نسخة Flutter).
///
/// كلّ القيم قابلة للتجاوز وقت البناء عبر `--dart-define` حتى لا تُحزَم في
/// المصدر. القيم الافتراضيّة تطابق مشروع نبراس الحاليّ (nebras-9118c).
class AppConfig {
  AppConfig._();

  /// أصل لوحة الويب المنشورة على Vercel — منه تُستدعى نقاط الـ API الخادمية
  /// (محرّكات IA/Noor/Hindawi، المشرفون، التقارير، الإشعارات…). بدون شرطة
  /// نهائيّة.
  static const String backendBaseUrl = String.fromEnvironment(
    'NEBRAS_API_BASE_URL',
    defaultValue: 'https://nebras-dashboard-main.vercel.app',
  );

  /// Web OAuth client (نوع 3) — مطلوب ليُصدِر `google_sign_in` على Android
  /// رمز ID صالحاً لـ Firebase Auth. نفس قيمة تطبيق نبراس المحمول.
  static const String googleServerClientId = String.fromEnvironment(
    'NEBRAS_GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '412379996427-0i55p23iunk93tilvje5442d6e42s4p9.apps.googleusercontent.com',
  );

  /// قاعدة Firestore مُسمّاة باسم `default` (بدون أقواس) في مشروع نبراس.
  static const String firestoreDatabaseId = 'default';
}
