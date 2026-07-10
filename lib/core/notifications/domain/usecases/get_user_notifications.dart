// lib/features/notifications/domain/usecases/get_user_notifications.dart
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';

/// Use case for getting user's in-app notifications
class GetUserNotificationsUseCase {
  final NotificationRepositoryInterface repository;

  GetUserNotificationsUseCase(this.repository);

  Future<List<AppNotification>> call(String userId) async {
    return await repository.getUserNotifications(userId);
  }
}
