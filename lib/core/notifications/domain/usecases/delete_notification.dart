import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

class DeleteNotificationUseCase {
  final NotificationRepositoryInterface repository;

  DeleteNotificationUseCase(this.repository);

  Future<void> call(String notificationId) async {
    await repository.deleteNotification(notificationId);
  }
}
