// lib/features/notifications/domain/usecases/get_unread_count.dart
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

/// Use case for getting unread notification count
class GetUnreadCountUseCase {
  final NotificationRepositoryInterface repository;

  GetUnreadCountUseCase(this.repository);

  Future<int> call(String userId) async {
    return await repository.getUnreadCount(userId);
  }
}
