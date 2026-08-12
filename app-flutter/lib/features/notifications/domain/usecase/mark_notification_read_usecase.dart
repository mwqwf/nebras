import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';

class MarkNotificationReadUseCase {
  final NotificationRepo repository;
  MarkNotificationReadUseCase(this.repository);

  Future<void> call(String id) {
    return repository.markAsRead(id);
  }
}
