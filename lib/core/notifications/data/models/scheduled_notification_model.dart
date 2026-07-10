// lib/features/notifications/data/models/scheduled_notification_model.dart
import 'package:attune/core/notifications/domain/entities/scheduled_notification.dart';

/// Data model for scheduled notifications (matches Supabase schema)
class ScheduledNotificationModel {
  final String id;
  final String notificationType;
  final String? userId;
  final String? guestProfileId;
  final String? bookingId;
  final String? shopId;
  final DateTime scheduledFor;
  final String status;
  final int retryCount;
  final String? lastError;
  final Map<String, dynamic> metadata;
  final String deliveryChannel;
  final String? whatsappTemplate;
  final Map<String, dynamic>? whatsappParams;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScheduledNotificationModel({
    required this.id,
    required this.notificationType,
    this.userId,
    this.guestProfileId,
    this.bookingId,
    this.shopId,
    required this.scheduledFor,
    required this.status,
    required this.retryCount,
    this.lastError,
    required this.metadata,
    this.deliveryChannel = 'push',
    this.whatsappTemplate,
    this.whatsappParams,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create from JSON (Supabase response)
  factory ScheduledNotificationModel.fromJson(Map<String, dynamic> json) {
    return ScheduledNotificationModel(
      id: json['id'] as String,
      notificationType: json['notification_type'] as String,
      userId: json['user_id'] as String?,
      guestProfileId: json['guest_profile_id'] as String?,
      bookingId: json['booking_id'] as String?,
      shopId: json['shop_id'] as String?,
      scheduledFor: DateTime.parse(json['scheduled_for'] as String),
      status: json['status'] as String,
      retryCount: json['retry_count'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      deliveryChannel: json['delivery_channel'] as String? ?? 'push',
      whatsappTemplate: json['whatsapp_template'] as String?,
      whatsappParams: json['whatsapp_params'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'notification_type': notificationType,
      'user_id': userId,
      'guest_profile_id': guestProfileId,
      'booking_id': bookingId,
      'shop_id': shopId,
      'scheduled_for': scheduledFor.toIso8601String(),
      'status': status,
      'retry_count': retryCount,
      'last_error': lastError,
      'metadata': metadata,
      'delivery_channel': deliveryChannel,
      'whatsapp_template': whatsappTemplate,
      'whatsapp_params': whatsappParams,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to domain entity
  ScheduledNotification toDomain() {
    return ScheduledNotification(
      id: id,
      notificationType: notificationType, // Keep as String, not enum
      userId: userId,
      guestProfileId: guestProfileId,
      bookingId: bookingId,
      shopId: shopId,
      scheduledFor: scheduledFor,
      status: NotificationStatus.fromValue(status),
      retryCount: retryCount,
      lastError: lastError,
      metadata: metadata,
      deliveryChannel: deliveryChannel,
      whatsappTemplate: whatsappTemplate,
      whatsappParams: whatsappParams,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Create from domain entity
  factory ScheduledNotificationModel.fromDomain(
    ScheduledNotification notification,
  ) {
    return ScheduledNotificationModel(
      id: notification.id,
      notificationType:
          notification.notificationType, // Use the String property directly
      userId: notification.userId,
      guestProfileId: notification.guestProfileId,
      bookingId: notification.bookingId,
      shopId: notification.shopId,
      scheduledFor: notification.scheduledFor,
      status: notification.status.name,
      retryCount: notification.retryCount,
      lastError: notification.lastError,
      metadata: notification.metadata,
      deliveryChannel: notification.deliveryChannel,
      whatsappTemplate: notification.whatsappTemplate,
      whatsappParams: notification.whatsappParams,
      createdAt: notification.createdAt,
      updatedAt: notification.updatedAt,
    );
  }
}
