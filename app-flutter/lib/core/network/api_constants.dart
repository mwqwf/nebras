/// API Constants
/// All base URLs and endpoints centralized here
/// No hardcoded URLs anywhere else in the application
class ApiConstants {
  ApiConstants._();

  // ── Base URL — قابل للتجاوز عند الإصدار ─────────────────────────────
  //
  // **لماذا لا يكون ثابتاً صلباً؟**
  //   * خادم Render Free يدخل Sleep بعد 15 دقيقة من عدم الاستخدام، وأوّل
  //     طلب يستغرق 30–60 ثانية (cold start). نريد القدرة على نقل الخدمة
  //     لاحقاً إلى Render Paid أو Cloud Run بدون إصدار جديد ومراجعة متجر.
  //   * عند الترقية إلى Firebase Remote Config (مستقبليّاً) فقط أضف
  //     `firebase_remote_config` ومرّر النتيجة إلى `setOverride()` أثناء
  //     الـ bootstrap. كلّ الـ datasources تقرأ من `ApiConstants.baseUrl`
  //     بلا حاجة لتعديل.
  //
  // طريقة الاستخدام عند البناء:
  //   `flutter build apk --dart-define=NEBRAS_API_BASE_URL=https://api.example.com/`
  static const String _defaultBaseUrl = 'https://nebras-backend.onrender.com/';
  static const String _envBaseUrl = String.fromEnvironment(
    'NEBRAS_API_BASE_URL',
    defaultValue: '',
  );
  static String? _runtimeOverride;

  /// يستخدم في الـ bootstrap (مثلاً بعد قراءة Firebase Remote Config) لضبط
  /// عنوان الخادم في وقت التشغيل دون إعادة بناء. مرّر `null` للعودة إلى
  /// القيمة الافتراضيّة.
  static void setOverride(String? url) {
    _runtimeOverride = (url != null && url.trim().isNotEmpty)
        ? url.trim()
        : null;
  }

  /// يُعيد عنوان الـ API الحاليّ بحسب الأولويّة:
  ///   1. runtime override (مثلاً من Remote Config)
  ///   2. `--dart-define=NEBRAS_API_BASE_URL=...` عند البناء
  ///   3. الافتراضيّ المضمَّن في الكود
  static String get baseUrl {
    if (_runtimeOverride != null) return _runtimeOverride!;
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    return _defaultBaseUrl;
  }

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  //content
  static const String content = '/api/public/all/';
  static String contentDetail(int id) => '$content$id/';

  // ── Sections ────────────────────────────────────────────────
  static const String mainSections = '/api/public/sections/main/';
  static String mainSectionDetail(String name) => '$mainSections$name/';
  static const String subSections = '/api/public/sections/sub/';
  static String subSectionsByMain(String mainName) =>
      '$subSections?main_section=$mainName';
  static String subSectionDetail(String name) => '$subSections$name/';
  static const String secondarySections = '/api/public/sections/secondary/';
  static String secondarySectionsBySub(String subId) =>
      '$secondarySections?sub_section=$subId';
  // ── Content Metadata ────────────────────────────────────────
  static const String metadata = '/api/public/metadata/';

  // ── YouTube ─────────────────────────────────────────────────
  static const String youtube = '/api/public/youtube/';
  static String youtubeDetail(int id) => '$youtube$id/';

  // ── Files (R2) ──────────────────────────────────────────────
  static const String files = '/api/public/files/';
  static String fileDetail(int id) => '$files$id/';

  // ── Notifications ──────────────────────────────────────────
  static const String notifications = '/api/notifications/devices/';
  static String notificationDetail(int id) => '$notifications$id/';
}
