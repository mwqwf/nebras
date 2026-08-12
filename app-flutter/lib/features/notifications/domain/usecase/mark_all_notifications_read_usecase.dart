import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';

class MarkAllNotificationsReadUseCase {
  final NotificationRepo repository;
  MarkAllNotificationsReadUseCase(this.repository);

  Future<void> call() {
    return repository.markAllAsRead();
  }
}
