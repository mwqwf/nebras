import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:nebras_mobile_app/features/notifications/data/firebase_notification_datasource.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';
import 'package:nebras_mobile_app/features/notifications/service/notifications_preferences.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/get_notification_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/mark_notification_read_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/mark_all_notifications_read_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/delete_notification_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/get_unread_count_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';

/// Notification provider
/// Manages notification state, listens to repository stream for live updates
/// No Firebase logic here — pure state management
class NotificationProvider extends ChangeNotifier {
  final GetNotificationsUseCase _getNotificationsUseCase;
  final MarkNotificationReadUseCase _markReadUseCase;
  final MarkAllNotificationsReadUseCase _markAllReadUseCase;
  final DeleteNotificationUseCase _deleteUseCase;
  final GetUnreadCountUseCase _getUnreadCountUseCase;
  final NotificationRepo _repository;
  final FirebaseNotificationDatasource _fcmDatasource;

  StreamSubscription<NotificationModel>? _subscription;

  NotificationProvider(
    this._getNotificationsUseCase,
    this._markReadUseCase,
    this._markAllReadUseCase,
    this._deleteUseCase,
    this._getUnreadCountUseCase,
    this._repository,
    this._fcmDatasource,
  ) {
    // Listen to new incoming notifications
    _subscription = _repository.notificationStream.listen((_) {
      // Reload from Hive whenever a new notification arrives
      load();
    });
    // تحميل تفضيل الاستقبال من التخزين المحليّ حتى تُظهر الواجهة الحالة
    // الصحيحة فور فتح شاشة الإعدادات. لا ننتظر النتيجة لئلّا نُبطئ الإقلاع.
    _loadPushPreference();
  }

  // ── State ────────────────────────────────────────────────
  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  // الحالة الافتراضيّة مفعَّلة كي لا تظهر الواجهة بشكل خاطئ قبل اكتمال
  // قراءة SharedPreferences؛ ستُحدَّث تلقائيّاً عبر [_loadPushPreference].
  bool _pushEnabled = true;
  bool _isTogglingPush = false;

  List<NotificationModel> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  bool get isEmpty => _notifications.isEmpty;
  bool get isPushEnabled => _pushEnabled;
  bool get isTogglingPush => _isTogglingPush;

  // ── Load ─────────────────────────────────────────────────
  void load() {
    _isLoading = true;
    _notifySafely();

    try {
      _notifications = _getNotificationsUseCase();
      _unreadCount = _getUnreadCountUseCase();
    } catch (e) {
      debugPrint('Failed to load notifications: $e');
    } finally {
      _isLoading = false;
      _notifySafely();
    }
  }

  // ── Mark as Read ─────────────────────────────────────────
  Future<void> markAsRead(String id) async {
    await _markReadUseCase(id);
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _unreadCount = _getUnreadCountUseCase();
      _notifySafely();
    }
  }

  // ── Mark All as Read ─────────────────────────────────────
  Future<void> markAllAsRead() async {
    await _markAllReadUseCase();
    _notifications = _notifications
        .map((n) => n.copyWith(isRead: true))
        .toList();
    _unreadCount = 0;
    _notifySafely();
  }

  // ── Delete ─────────────────────────────────────────────
  Future<void> delete(String id) async {
    await _deleteUseCase(id);
    _notifications.removeWhere((n) => n.id == id);
    _unreadCount = _getUnreadCountUseCase();
    _notifySafely();
  }

  // ── Restore (Undo) ─────────────────────────────────────
  //
  // يُستخدم من زرّ "تراجع" في شاشة الإشعارات بعد السحب. نعيد كتابة
  // الإشعار في Hive عبر المستودع ثم نُعيد تحميل القائمة للحفاظ على
  // الترتيب الصحيح (الأحدث أوّلاً).
  Future<void> restore(NotificationModel item) async {
    await _repository.saveNotification(item);
    load();
  }

  // ── Push Notifications Toggle ──────────────────────────
  //
  // تُستخدم من مفتاح التبديل في صفحة الإعدادات. تعتمد سياسة (ائتمان
  // التفضيل أوّلاً): نُحدّث الحالة محليّاً فوراً ليستجيب مفتاح التبديل،
  // ثم نطلب من مصدر البيانات تنفيذ الاشتراك/الإلغاء في الخلفيّة.
  Future<void> _loadPushPreference() async {
    final enabled = await NotificationsPreferences.isPushEnabled();
    if (enabled == _pushEnabled) return;
    _pushEnabled = enabled;
    _notifySafely();
  }

  /// تبديل حالة الإشعارات مع إدارة مواضيع FCM.
  /// - عند التفعيل: يُعاد الاشتراك في موضوع البثّ العموميّ ويُستعاد الرمز.
  /// - عند الإيقاف: يُلغى الاشتراك ويُحذف الرمز كي لا يصل أيّ إشعار.
  Future<void> setPushEnabled(bool enabled) async {
    if (_isTogglingPush || _pushEnabled == enabled) return;
    _isTogglingPush = true;
    _pushEnabled = enabled;
    _notifySafely();
    try {
      if (enabled) {
        await _fcmDatasource.enablePushNotifications();
      } else {
        await _fcmDatasource.disablePushNotifications();
      }
    } catch (e) {
      debugPrint('Failed to toggle push notifications: $e');
      // نُرجع الواجهة إلى الحالة السابقة حتى لا يظنّ المستخدم أنّ الأمر
      // نُفِّذ عند فشل الشبكة مثلاً.
      _pushEnabled = !enabled;
    } finally {
      _isTogglingPush = false;
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (!hasListeners) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
