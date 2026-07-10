import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

class MarkAllNotificationsAsReadUseCase {
  final NotificationRepositoryInterface repository;

  MarkAllNotificationsAsReadUseCase(this.repository);

  Future<void> call(String userId) async {
    await repository.markAllNotificationsAsRead(userId);
  }
}
