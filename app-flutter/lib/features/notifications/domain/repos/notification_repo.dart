import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';

/// Abstract contract for notification repository
abstract class NotificationRepo {
  /// Get all stored notifications
  List<NotificationModel> getAllNotifications();

  /// Mark a single notification as read
  Future<void> markAsRead(String id);

  /// Mark all notifications as read
  Future<void> markAllAsRead();

  /// Delete a notification
  Future<void> deleteNotification(String id);

  /// Get count of unread notifications
  int getUnreadCount();

  /// Stream of new incoming notifications
  Stream<NotificationModel> get notificationStream;

  /// Save a notification to local storage
  Future<void> saveNotification(NotificationModel notification);
}
