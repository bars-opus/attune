// lib/features/notifications/domain/usecases/mark_notification_as_read.dart
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

/// Use case for marking a notification as read
class MarkNotificationAsReadUseCase {
  final NotificationRepositoryInterface repository;

  MarkNotificationAsReadUseCase(this.repository);

  Future<void> call(String notificationId) async {
    await repository.markNotificationAsRead(notificationId);
  }
}
