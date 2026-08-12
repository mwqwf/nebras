import 'dart:async';

import 'package:hive/hive.dart';
import 'package:nebras_mobile_app/features/notifications/data/firebase_notification_datasource.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';

/// Notification repository implementation
/// Listens to FCM datasource stream, saves to Hive, exposes Hive-backed queries
class NotificationRepoImpl implements NotificationRepo {
  final FirebaseNotificationDatasource datasource;
  final Box<NotificationModel> box;
  StreamSubscription<NotificationModel>? _subscription;

  NotificationRepoImpl(this.datasource, this.box) {
    // Listen to incoming notifications from FCM and save to Hive
    _subscription = datasource.notificationStream.listen((notification) {
      saveNotification(notification);
    });
  }

  @override
  Stream<NotificationModel> get notificationStream =>
      datasource.notificationStream;

  @override
  List<NotificationModel> getAllNotifications() {
    final items = box.values.toList();
    // Sort newest first
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> markAsRead(String id) async {
    final item = box.get(id);
    if (item != null && !item.isRead) {
      await box.put(id, item.copyWith(isRead: true));
    }
  }

  @override
  Future<void> markAllAsRead() async {
    for (final key in box.keys.toList()) {
      final item = box.get(key);
      if (item != null && !item.isRead) {
        await box.put(key, item.copyWith(isRead: true));
      }
    }
  }

  @override
  Future<void> deleteNotification(String id) async {
    await box.delete(id);
  }

  @override
  int getUnreadCount() {
    return box.values.where((item) => !item.isRead).length;
  }

  @override
  Future<void> saveNotification(NotificationModel notification) async {
    // Prevent duplicates
    if (!box.containsKey(notification.id)) {
      await box.put(notification.id, notification);
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
