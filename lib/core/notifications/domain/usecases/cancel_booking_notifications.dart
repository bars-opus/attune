// lib/features/notifications/domain/usecases/cancel_booking_notifications.dart
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';

/// Use case for cancelling all notifications related to a booking
class CancelBookingNotificationsUseCase {
  final NotificationRepositoryInterface repository;

  CancelBookingNotificationsUseCase(this.repository);

  Future<int> call(String bookingId) async {
    return await repository.cancelBookingNotifications(bookingId);
  }
}
