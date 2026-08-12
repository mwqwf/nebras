import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';

class GetUnreadCountUseCase {
  final NotificationRepo repository;
  GetUnreadCountUseCase(this.repository);

  int call() {
    return repository.getUnreadCount();
  }
}
