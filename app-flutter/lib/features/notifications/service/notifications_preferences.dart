import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات الإشعارات المركزيّة — طبقة تخزين محليّة بسيطة فوق
/// [SharedPreferences]. تمتلك قيمة واحدة: هل يسمح المستخدم باستقبال
/// إشعارات FCM؟
///
/// - القيمة الافتراضيّة **مفعَّلة** (true)، فيُحافظ التطبيق على سلوكه
///   الحاليّ لمستخدمين موجودين أصلاً.
/// - الكتابة والقراءة متزامنتان نسبيّاً، ولا حاجة لآليّة إعلام؛ مزوِّد
///   الإشعارات ([NotificationProvider]) هو من يُعلم الواجهة بعد أيّ تغيير.
class NotificationsPreferences {
  NotificationsPreferences._();

  /// مفتاح ثابت داخل SharedPreferences. لا تُغيِّره لاحقاً لئلّا تُفقد
  /// تفضيلات المستخدمين الحاليّين.
  static const String _kPushEnabled = 'notifications_push_enabled';

  /// الحالة الافتراضيّة — مفعَّلة.
  static const bool _defaultEnabled = true;

  /// قراءة الحالة الحاليّة. تُرجع الافتراضيّ إذا لم تُكتَب قيمة مسبقاً.
  static Future<bool> isPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPushEnabled) ?? _defaultEnabled;
  }

  /// كتابة التفضيل الجديد. لا تقوم هذه الدالّة بأيّ عمل شبكيّ؛ السلوك
  /// (الاشتراك/إلغاء الاشتراك من مواضيع FCM) يُدار من
  /// `FirebaseNotificationDatasource.enable/disablePushNotifications`.
  static Future<void> setPushEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPushEnabled, enabled);
  }
}
