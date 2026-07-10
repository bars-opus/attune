// lib/features/notifications/domain/entities/notification_params.dart

import 'notification_type.dart';

/// Generic parameters for scheduling a notification
// lib/core/notifications/domain/entities/notification_params.dart

class ScheduleNotificationParams {
  final String userId;
  final NotificationType type;  // Keep as NotificationType for convenience
  final DateTime scheduledFor;
  final Map<String, dynamic> data;
  final String? titleOverride;
  final String? bodyOverride;
  final int priority;
  final String? referenceId;  // Optional reference for cancellation
  
  const ScheduleNotificationParams({
    required this.userId,
    required this.type,
    required this.scheduledFor,
    this.data = const {},
    this.titleOverride,
    this.bodyOverride,
    this.priority = 5,
    this.referenceId,
  });


  /// Create a copy with modifications
  ScheduleNotificationParams copyWith({
    String? userId,
    NotificationType? type,
    DateTime? scheduledFor,
    Map<String, dynamic>? data,
    String? titleOverride,
    String? bodyOverride,
    int? priority,
  }) {
    return ScheduleNotificationParams(
      userId: userId ?? this.userId,
      type: type ?? this.type,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      data: data ?? this.data,
      titleOverride: titleOverride ?? this.titleOverride,
      bodyOverride: bodyOverride ?? this.bodyOverride,
      priority: priority ?? this.priority,
    );
  }
}

/// Generic parameters for immediate notification
class ImmediateNotificationParams {
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final int priority;

  const ImmediateNotificationParams({
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.priority = 5,
  });
}

/// Parameters for scheduling multiple reminders
class ScheduleRemindersParams {
  final String userId;
  final String referenceId; // booking_id, order_id, etc.
  final NotificationType baseType;
  final List<Duration> offsets; // When to send each reminder
  final Map<String, dynamic> templateData;
  final String? titleTemplate;
  final String? bodyTemplate;

  const ScheduleRemindersParams({
    required this.userId,
    required this.referenceId,
    required this.baseType,
    required this.offsets,
    required this.templateData,
    this.titleTemplate,
    this.bodyTemplate,
  });
}
