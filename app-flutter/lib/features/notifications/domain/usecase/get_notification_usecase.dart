import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';

class GetNotificationsUseCase {
  final NotificationRepo repository;

  GetNotificationsUseCase(this.repository);

  List<NotificationModel> call() {
    return repository.getAllNotifications();
  }
}
