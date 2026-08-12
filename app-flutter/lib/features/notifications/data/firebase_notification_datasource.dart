import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nebras_mobile_app/core/routing/notification_navigator.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';
import 'package:nebras_mobile_app/features/notifications/service/notifications_preferences.dart';

/// Topic عمومي يشترك فيه جميع مستخدمي التطبيق؛ يُستخدم لبثّ الإشعارات
/// عند إضافة محتوى جديد أو إنشاء قسم من لوحة التحكّم.
/// يجب أن تطابق هذه القيمة FCM_BROADCAST_TOPIC في .env للوحة التحكّم.
const String kBroadcastTopic = 'nebras_all_users';

/// Firebase notification datasource
/// Handles FCM initialization, message reception, and local notification display
/// Exposes a `Stream<NotificationModel>` for new notifications
/// No navigation, no Hive access — those belong to the repository
class FirebaseNotificationDatasource {
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  final _controller = StreamController<NotificationModel>.broadcast();

  /// اشتراكات FCM: نحتفظ بها في حقول كي تُلغى بنظافة داخل [dispose].
  /// قبل هذا التعديل كانت listeners تُسجَّل بدون مرجع، فيتكرّر عرض
  /// الإشعارات عند إعادة التهيئة وتتسرّب الذاكرة عند الخروج.
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;

  /// Stream of incoming notifications (from FCM)
  Stream<NotificationModel> get notificationStream => _controller.stream;

  /// Pending notification from terminated state tap (for deep linking)
  NotificationModel? pendingNotification;

  /// ─── جاهزية initialize() ─────────────────────────────────────────
  /// يكتمل بعد تسجيل listeners FCM فعليّاً. المستهلكون (مثلاً
  /// `home_screen.dart` الذي يستمع إلى [notificationStream]) يمكنهم
  /// انتظاره عبر `await datasource.ready;` لتجنّب سباق ضياع أوّل إشعار
  /// يصل في أوّل 200ms من الإقلاع، حين يُهيَّأ الـ MultiProvider قبل
  /// انتهاء `_warmUpDeferredServices` في main.dart.
  final Completer<void> _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  FirebaseNotificationDatasource(this._messaging, this._localNotifications);

  /// Initialize FCM + local notifications
  Future<void> initialize() async {
    try {
      await _initializeInternal();
    } catch (e, st) {
      debugPrint('[FCM] initialize() failed: $e\n$st');
      // نمرّر الخطأ للمستهلك المنتظر لـ [ready] حتى لا يتعلّق إلى الأبد.
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(e, st);
      }
      rethrow;
    }
  }

  Future<void> _initializeInternal() async {
    // طلب إذن الإشعارات — على Android 13+ يُظهر حواراً للمستخدم،
    // وعلى iOS يُظهر حوار APNs. النتيجة غير حرجة؛ سنستمر بالتهيئة
    // حتى يتمكّن المستخدم من منح الإذن لاحقاً من إعدادات النظام.
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '[FCM] Permission status: ${settings.authorizationStatus}',
    );

    // Initialize local notifications for foreground banners.
    // نستخدم drawable أحاديّ اللون (silhouette أبيض) كما يفرض Android ≥ 5.0:
    // تمرير mipmap ملوّن ينتج عنه "مربّع أبيض صلب" في شريط الحالة.
    // يجب أن يطابق ic_stat_notify المُعرَّف في res/drawable/ والمستخدَم في
    // AndroidManifest.xml كـ default_notification_icon. الـ API يتوقّع اسم
    // الـ drawable فقط بدون البادئة `@drawable/` أو الامتداد.
    const androidSettings = AndroidInitializationSettings('ic_stat_notify');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    // نمرّر `onDidReceiveNotificationResponse` حتى يصلنا الضغط على
    // البانر الذي يُعرض في المقدّمة (flutter_local_notifications). دونه
    // لن نعرف بأن المستخدم فتح الإشعار أثناء استخدامه للتطبيق.
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Create notification channel for Android — اسم المعرّف يجب أن يطابق
    // meta-data في AndroidManifest.xml (default_notification_channel_id).
    const channel = AndroidNotificationChannel(
      'nebras_notifications',
      'Nebras Notifications',
      description: 'Notifications from Nebras app',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // يجب استدعاؤها على iOS قبل getToken لتفعيل APNs بشكل صحيح.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // الاشتراك في الـ topic العمومي مشروطٌ بتفضيل المستخدم. إذا كان قد
    // أوقف الإشعارات من صفحة الإعدادات، نتخطّى الاشتراك تماماً كي لا
    // يستقبل جهازه أيّ بثٍّ في الخلفية. السلوك الافتراضيّ لمستخدم جديد
    // هو التفعيل، فلا تغيير على التجربة الحاليّة.
    final pushEnabled = await NotificationsPreferences.isPushEnabled();
    if (pushEnabled) {
      try {
        await _messaging.subscribeToTopic(kBroadcastTopic);
        debugPrint('[FCM] Subscribed to topic: $kBroadcastTopic');
      } catch (e) {
        debugPrint('[FCM] Failed to subscribe to $kBroadcastTopic: $e');
      }
    } else {
      debugPrint('[FCM] Skipping topic subscription — disabled by user.');
      // نحذف الـ token احتياطاً حتى لا يتمكّن الخادم من إرسال إشعارات
      // مستهدفة لهذا الجهاز طالما المستخدم أوقف الاستقبال.
      try {
        await _messaging.deleteToken();
      } catch (_) {}
    }

    // Handle foreground messages — خزّن الاشتراك ليُلغى في dispose().
    _onMessageSub?.cancel();
    _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background tap — كذلك الأمر، تتبُّع الاشتراك إلزاميّ.
    _onMessageOpenedAppSub?.cancel();
    _onMessageOpenedAppSub =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // Handle terminated tap (app was killed)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      pendingNotification = _remoteMessageToModel(initialMessage);
      _controller.add(pendingNotification!);
      // نوجّه الضغط إلى المُوجِّه بعد جهوزيّة Navigator (المُوجِّه يتعامل
      // مع ذلك داخلياً). يكفي تمرير البيانات الخام من الإشعار.
      _dispatchTap(initialMessage.data);
    }

    // ✓ كلّ listeners FCM مُسجَّلة. نُكمل الـ Completer ليتسنّى للمستهلكين
    // الذين يستمعون إلى [notificationStream] انتظار جاهزيّة المصدر.
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  /// Handle foreground message: show local notification + emit to stream
  void _handleForegroundMessage(RemoteMessage message) {
    final model = _remoteMessageToModel(message);
    _controller.add(model);
    _showLocalNotification(model, message.data);
  }

  /// Handle background/terminated tap: emit to stream for deep linking
  void _handleMessageTap(RemoteMessage message) {
    final model = _remoteMessageToModel(message);
    pendingNotification = model;
    _controller.add(model);
    _dispatchTap(message.data);
  }

  /// يُستدعى عند الضغط على إشعار محليّ عُرض في المقدّمة عبر
  /// flutter_local_notifications. الـ payload نصّ JSON يحمل `data` الأصلية
  /// من FCM حتى يعرف المُوجِّه إلى أين يذهب.
  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        _dispatchTap(data);
      }
    } catch (e) {
      debugPrint('[FCM] Failed to parse local notification payload: $e');
    }
  }

  void _dispatchTap(Map<String, dynamic> data) {
    // تحويل أي قيم ليست String إلى String حتى يتعامل المُوجِّه معها
    // بسهولة (أرقام الـ IDs مثلاً تأتي أحياناً كـ num).
    final normalized = <String, dynamic>{
      for (final entry in data.entries) entry.key: entry.value,
    };
    NotificationNavigator.instance.handle(normalized);
  }

  /// Convert RemoteMessage to NotificationModel
  NotificationModel _remoteMessageToModel(RemoteMessage message) {
    final data = message.data;
    final notification = message.notification;

    return NotificationModel(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: notification?.title ?? data['title'] ?? '',
      body: notification?.body ?? data['body'] ?? '',
      type: data['type'] ?? 'video',
      contentId: data['contentId'] ?? '',
      createdAt: message.sentTime ?? DateTime.now(),
      sourceUrl: data['sourceUrl'] ?? data['video_url'] ?? data['file_url'],
    );
  }

  /// Show a local notification banner in foreground
  Future<void> _showLocalNotification(
    NotificationModel model,
    Map<String, dynamic> data,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'nebras_notifications',
      'Nebras Notifications',
      channelDescription: 'Notifications from Nebras app',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      // أيقونة silhouette أحاديّة اللون (انظر res/drawable/ic_stat_notify.xml).
      // قيمة `icon` تأخذ اسم الـ drawable فقط بدون البادئة `@drawable/`.
      icon: 'ic_stat_notify',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // نشفّر حمولة الإشعار كسلسلة JSON حتى تعود إلينا عند الضغط عبر
    // onDidReceiveNotificationResponse، فيتمكّن المُوجِّه من فتح الشاشة
    // الصحيحة (محتوى أو قسم) حسب الـ type والمعرّفات.
    String? payloadJson;
    try {
      payloadJson = jsonEncode(data);
    } catch (_) {
      payloadJson = null;
    }

    // ID مونوتوني: millisecondsSinceEpoch & 0x7FFFFFFF
    // ─────────────────────────────────────────────────────────────────
    // كان Random().nextInt(100000) يحتمل تصادماً مرئيّاً عند وصول
    // إشعارَين خلال نفس الإطار (انفجار FCM). الوقت بميلليثانية مونوتوني
    // فعلياً في الإقلاع الواحد، والـ AND مع 0x7FFFFFFF يحافظ على
    // صلاحيّة الـ int32 (`flutter_local_notifications` يتوقع int).
    final notifId = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    await _localNotifications.show(
      notifId,
      model.title,
      model.body,
      details,
      payload: payloadJson,
    );
  }

  /// Get FCM token (useful for server registration)
  Future<String?> getToken() => _messaging.getToken();

  // ── التحكّم المركزيّ بالإشعارات ────────────────────────────────────────
  //
  // هاتان الدالّتان هما ما يستدعيه مفتاح التبديل في صفحة الإعدادات.
  // نقسم العمل على طبقتين:
  //   1) تخزين التفضيل محليّاً (SharedPreferences) كي يُحترم في الإقلاعات
  //      اللاحقة.
  //   2) مخاطبة Firebase لتعديل الاشتراك بمواضيع البثّ حالاً، ومحو الـ token
  //      عند الإيقاف لمنع أيّ إرسال مستهدف للجهاز.

  /// تفعيل استقبال إشعارات FCM: يُحفظ التفضيل ثم يُشترك في موضوع البثّ.
  /// أيّ فشل شبكيّ لا يُرجَع كاستثناء لأنّ النيّة محفوظة محليّاً وسيُعاد
  /// محاولة الاشتراك في أوّل إقلاع تالٍ عبر [initialize].
  Future<void> enablePushNotifications() async {
    await NotificationsPreferences.setPushEnabled(true);
    try {
      await _messaging.subscribeToTopic(kBroadcastTopic);
      debugPrint('[FCM] Enabled — subscribed to $kBroadcastTopic');
    } catch (e) {
      debugPrint('[FCM] enablePushNotifications subscribe failed: $e');
    }
  }

  /// إيقاف استقبال إشعارات FCM: يُحفظ التفضيل، ثم يُلغى الاشتراك من موضوع
  /// البثّ، ويُحذف رمز FCM حتى لا تصل إشعارات مستهدفة. لا نلمس قناة
  /// الإشعارات المحليّة لأنّ المستخدم ما زال قادراً على تصفّح إشعاراته
  /// المحفوظة في شاشة الإشعارات داخل التطبيق.
  Future<void> disablePushNotifications() async {
    await NotificationsPreferences.setPushEnabled(false);
    try {
      await _messaging.unsubscribeFromTopic(kBroadcastTopic);
      debugPrint('[FCM] Disabled — unsubscribed from $kBroadcastTopic');
    } catch (e) {
      debugPrint('[FCM] unsubscribe failed: $e');
    }
    try {
      await _messaging.deleteToken();
      debugPrint('[FCM] Token deleted.');
    } catch (e) {
      debugPrint('[FCM] deleteToken failed: $e');
    }
  }

  Future<void> dispose() async {
    // إلغاء قنوات FCM أوّلًا كي لا تستقبل أحداثاً بعد إغلاق الـ controller
    // (وإلّا ينفجر `controller.add` بـ StateError في النسخة الثانية من
    // التطبيق بعد hot restart).
    await _onMessageSub?.cancel();
    _onMessageSub = null;
    await _onMessageOpenedAppSub?.cancel();
    _onMessageOpenedAppSub = null;
    await _controller.close();
  }
}
