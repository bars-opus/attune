// lib/features/notifications/domain/usecases/schedule_booking_reminders.dart

import 'package:equatable/equatable.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';
import 'package:attune/core/notifications/domain/entities/scheduled_notification.dart';
import 'package:attune/core/notifications/utils/notification_date_time_utils.dart';

/// Parameters for scheduling booking reminders
class ScheduleBookingRemindersParams extends Equatable {
  final String bookingId;
  final String userId;
  final String shopId;
  final String shopOwnerId;
  final String userName;
  final String shopName;
  final List<String> serviceNames;
  final DateTime bookingDate;
  final DateTime startTime;
  final Duration duration;

  const ScheduleBookingRemindersParams({
    required this.bookingId,
    required this.userId,
    required this.shopId,
    required this.shopOwnerId,
    required this.userName,
    required this.shopName,
    required this.serviceNames,
    required this.bookingDate,
    required this.startTime,
    required this.duration,
  });

  @override
  List<Object?> get props => [
    bookingId, userId, shopId, shopOwnerId, userName, shopName, 
    serviceNames, bookingDate, startTime, duration
  ];
}

/// Use case for scheduling booking reminders
class ScheduleBookingRemindersUseCase {
  final NotificationRepositoryInterface repository;

  ScheduleBookingRemindersUseCase(this.repository);

  Future<List<ScheduledNotification>> call(ScheduleBookingRemindersParams params) async {
    // Combine date and time
    final appointmentDateTime = NotificationDateTimeUtils.combineDateAndTime(
      params.bookingDate,
      params.startTime,
    );

    final reminders = <ScheduledNotification>[];
    final serviceNames = params.serviceNames.join(', ');

    // 1. Client reminder: 24 hours before
    reminders.add(
      ScheduledNotification(
        id: '',
        notificationType: ScheduledNotificationType.bookingReminder24h.value, // Use .value to get String
        userId: params.userId,
        bookingId: params.bookingId,
        scheduledFor: appointmentDateTime.subtract(const Duration(hours: 24)),
        status: NotificationStatus.pending,
        metadata: {
          'title': 'Appointment Tomorrow',
          'body': 'Your appointment is tomorrow at ${NotificationDateTimeUtils.formatTime(params.startTime)}',
          'booking_id': params.bookingId,
          'shop_name': params.shopName,
          'service_names': serviceNames,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 2. Client reminder: 1 hour before
    reminders.add(
      ScheduledNotification(
        id: '',
        notificationType: ScheduledNotificationType.bookingReminder1h.value, // Use .value
        userId: params.userId,
        bookingId: params.bookingId,
        scheduledFor: appointmentDateTime.subtract(const Duration(hours: 1)),
        status: NotificationStatus.pending,
        metadata: {
          'title': 'Appointment in 1 Hour',
          'body': 'Your appointment is in 1 hour, please be on your way to ${params.shopName}',
          'booking_id': params.bookingId,
          'shop_name': params.shopName,
          'service_names': serviceNames,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 3. Client reminder: 5 minutes before
    reminders.add(
      ScheduledNotification(
        id: '',
        notificationType: ScheduledNotificationType.bookingReminder5min.value, // Use .value
        userId: params.userId,
        bookingId: params.bookingId,
        scheduledFor: appointmentDateTime.subtract(const Duration(minutes: 5)),
        status: NotificationStatus.pending,
        metadata: {
          'title': 'Appointment Starting Now',
          'body': 'Your appointment is about to start at ${params.shopName}',
          'booking_id': params.bookingId,
          'shop_name': params.shopName,
          'service_names': serviceNames,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 4. Shop reminder: 15 minutes before
    reminders.add(
      ScheduledNotification(
        id: '',
        notificationType: ScheduledNotificationType.shopReminder15min.value, // Use .value
        userId: params.shopOwnerId,
        bookingId: params.bookingId,
        shopId: params.shopId,
        scheduledFor: appointmentDateTime.subtract(const Duration(minutes: 15)),
        status: NotificationStatus.pending,
        metadata: {
          'title': 'Client Arriving Soon',
          'body': '${params.userName}\'s appointment starts in 15 minutes',
          'booking_id': params.bookingId,
          'client_name': params.userName,
          'service_names': serviceNames,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // 5. Review request: 30 minutes after appointment ends
    reminders.add(
      ScheduledNotification(
        id: '',
        notificationType: ScheduledNotificationType.reviewRequest.value, // Use .value
        userId: params.userId,
        bookingId: params.bookingId,
        scheduledFor: appointmentDateTime.add(params.duration).add(const Duration(minutes: 30)),
        status: NotificationStatus.pending,
        metadata: {
          'title': 'How was your appointment?',
          'body': 'Rate your experience at ${params.shopName}',
          'booking_id': params.bookingId,
          'shop_id': params.shopId,
          'shop_name': params.shopName,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Save all reminders to database
    return await repository.scheduleNotifications(reminders);
  }
}
