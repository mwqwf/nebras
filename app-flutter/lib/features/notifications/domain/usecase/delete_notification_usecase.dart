import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';

class DeleteNotificationUseCase {
  final NotificationRepo repository;
  DeleteNotificationUseCase(this.repository);

  Future<void> call(String id) {
    return repository.deleteNotification(id);
  }
}
