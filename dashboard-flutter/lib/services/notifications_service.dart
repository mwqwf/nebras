import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/chat_repository.dart';
import '../ui/chat/chat_screen.dart';
import 'server_api.dart';

/// إشعارات لوحة نبراس — دردشة الإدارة + المحتوى الجديد.
///
/// الخادم يرسل رسائل FCM **data-only** (بلا كتلة notification) كي يتحكّم
/// التطبيق بالعرض: نبني الإشعار محليّاً عبر flutter_local_notifications،
/// ونحترم الكتم، ولا نُظهر إشعاراً لرسائلي أنا أو وشاشة الدردشة مفتوحة.
const String kAdminChatTopic = 'nebras_admin_chat';
const String kModeratorReportsTopic = 'nebras_moderator_reports';
const String kChatMutePref = 'nebras_chat_muted';

/// معالج رسائل الخلفيّة — top-level إلزاميّاً (يعمل في isolate مستقلّ).
@pragma('vm:entry-point')
Future<void> nebrasFcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await NotificationsService.showFromData(message.data,
      foreground: false);
}

class NotificationsService {
  NotificationsService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'nebras_admin_chat',
    'دردشة الإدارة',
    description: 'رسائل مجموعة إدارة نبراس وإشعارات المحتوى.',
    importance: Importance.high,
  );

  /// تهيئة كاملة — تُستدعى من DashboardShell بعد التصريح.
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      await _local.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await FirebaseMessaging.instance.requestPermission();
      await syncSubscription();
      await saveToken();

      // رسائل المقدمة: نعرضها محليّاً إلا إن كانت شاشة الدردشة مفتوحة.
      FirebaseMessaging.onMessage.listen((m) {
        showFromData(m.data, foreground: true);
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => saveToken());
    } catch (_) {
      // الإشعارات كماليّة — لا تُسقط اللوحة.
    }
  }

  /// مزامنة الاشتراك في topic الدردشة مع تفضيل الكتم.
  static Future<void> syncSubscription() async {
    final muted = await isMuted();
    try {
      if (muted) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(kAdminChatTopic);
      } else {
        await FirebaseMessaging.instance.subscribeToTopic(kAdminChatTopic);
      }
	  // بلاغات المحتوى ليست رسائل دردشة: لا يجعل كتم الدردشة المشرف يفوّت
	  // مخالفة تحتاج إلى استجابة سريعة.
	  await FirebaseMessaging.instance.subscribeToTopic(kModeratorReportsTopic);
    } catch (_) {}
  }

  static Future<bool> isMuted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kChatMutePref) ?? false;
  }

  static Future<void> setMuted(bool muted) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kChatMutePref, muted);
    await syncSubscription();
  }

  /// حفظ token في وثيقة العضو (لاستهداف مستقبلي مباشر إن لزم).
  static Future<void> saveToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ChatRepository.instance.saveFcmToken(token);
    } catch (_) {}
  }

  /// عرض إشعار محلّي من حمولة data (خلفية أو مقدمة).
  static Future<void> showFromData(Map<String, dynamic> data,
      {required bool foreground}) async {
    final title = '${data['title'] ?? ''}'.trim();
    final body = '${data['body'] ?? ''}'.trim();
    if (title.isEmpty && body.isEmpty) return;
	final isModerationAlert = data['kind'] == 'content_report';

    // لا إشعار لرسائلي أنا.
    final senderId = '${data['senderId'] ?? ''}';
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (senderId.isNotEmpty && senderId == myUid) return;

    // احترام الكتم (يشمل الخلفيّة — رسائل data-only لا يعرضها النظام وحده).
    try {
      final p = await SharedPreferences.getInstance();
      if (!isModerationAlert && (p.getBool(kChatMutePref) ?? false)) return;
    } catch (_) {}

    // في المقدمة وشاشة الدردشة مفتوحة: المستخدم يرى الرسالة أصلاً.
    if (foreground && !isModerationAlert && ChatScreen.isOpen) return;

    try {
      await _local.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await _local.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title.isEmpty ? 'نبراس' : title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'nebras_admin_chat',
            'دردشة الإدارة',
            channelDescription: 'رسائل مجموعة إدارة نبراس وإشعارات المحتوى.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }

  // ─── إرسال إشعارات عبر خادم اللوحة (fire-and-forget) ──────

  /// إشعار أعضاء الدردشة برسالة جديدة (يُستدعى بعد نجاح الإرسال).
  static void notifyChatMessage({
    required String senderName,
    required String preview,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    unawaited(ServerApi.instance.notify({
      'title': senderName,
      'body': preview,
      'topic': kAdminChatTopic,
      'data': {'kind': 'admin_chat', 'senderId': uid},
    }).catchError((_) => null));
  }

  /// إشعار متابعي قسم بمحتوى جديد (يُستدعى بعد نجاح الرفع السريع).
  static void notifySectionUpload({
    required String sectionId,
    required String sectionName,
    required String title,
  }) {
    if (sectionId.isEmpty) return;
    unawaited(ServerApi.instance.notify({
      'title': 'جديد في $sectionName ✨',
      'body': title,
      'topic': 'nebras_section_$sectionId',
      'data': {'kind': 'section_content', 'sectionId': sectionId},
    }).catchError((_) => null));
  }
}
