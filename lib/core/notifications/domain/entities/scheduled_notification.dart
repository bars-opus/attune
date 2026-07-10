// lib/features/notifications/domain/entities/scheduled_notification.dart

import 'package:equatable/equatable.dart';

/// Types of notifications that can be scheduled
enum ScheduledNotificationType {
  bookingReminder24h('booking_reminder_24h'),
  bookingReminder1h('booking_reminder_1h'),
  bookingReminder5min('booking_reminder_5min'),
  shopReminder15min('shop_reminder_15min'),
  reviewRequest('review_request'),
  newBookingShop('new_booking_shop'),
  newShopNearby('new_shop_nearby'),
  newReviewShop('new_review_shop');

  final String value;
  const ScheduledNotificationType(this.value);

  static ScheduledNotificationType fromValue(String value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => bookingReminder24h,
    );
  }
}

/// Status of a scheduled notification
enum NotificationStatus {
  pending,
  sent,
  failed,
  cancelled;

  static NotificationStatus fromValue(String value) {
    return values.firstWhere((e) => e.name == value, orElse: () => pending);
  }
}

/// Domain entity for scheduled notifications
class ScheduledNotification extends Equatable {
  final String id;
  final String notificationType;  // Change from NotificationType to String
  final String? userId;
  final String? guestProfileId;
  final String? bookingId;
  final String? shopId;
  final DateTime scheduledFor;
  final NotificationStatus status;
  final int retryCount;
  final String? lastError;
  final Map<String, dynamic> metadata;
  final String deliveryChannel;
  final String? whatsappTemplate;
  final Map<String, dynamic>? whatsappParams;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScheduledNotification({
    required this.id,
    required this.notificationType,  // Now String
    this.userId,
    this.guestProfileId,
    this.bookingId,
    this.shopId,
    required this.scheduledFor,
    this.status = NotificationStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.metadata = const {},
    this.deliveryChannel = 'push',
    this.whatsappTemplate,
    this.whatsappParams,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
    id,
    notificationType,
    userId,
    guestProfileId,
    bookingId,
    shopId,
    scheduledFor,
    status,
    retryCount,
    deliveryChannel,
    whatsappTemplate,
    whatsappParams,
    createdAt,
    updatedAt,
  ];
}
