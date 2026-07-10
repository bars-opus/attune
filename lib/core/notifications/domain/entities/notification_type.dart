// lib/features/notifications/domain/entities/notification_type.dart

/// Generic notification type - completely flexible for any app
class NotificationType {
  final String value;
  final String? titleTemplate;
  final String? bodyTemplate;
  final Duration? defaultOffset; // For scheduled notifications
  final int priority; // 1-10, higher = more important

  // ✅ Remove the extra 'String s' parameter
  const NotificationType({
    required this.value,
    this.titleTemplate,
    this.bodyTemplate,
    this.defaultOffset,
    this.priority = 5,
  });

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationType && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  /// Create from JSON (for database storage)
  factory NotificationType.fromJson(Map<String, dynamic> json) {
    return NotificationType(
      value: json['value'] as String,
      titleTemplate: json['title_template'] as String?,
      bodyTemplate: json['body_template'] as String?,
      defaultOffset: json['default_offset_minutes'] != null
          ? Duration(minutes: json['default_offset_minutes'] as int)
          : null,
      priority: json['priority'] as int? ?? 5,
    );
  }

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'value': value,
      if (titleTemplate != null) 'title_template': titleTemplate,
      if (bodyTemplate != null) 'body_template': bodyTemplate,
      if (defaultOffset != null) 'default_offset_minutes': defaultOffset!.inMinutes,
      'priority': priority,
    };
  }
}

/// Predefined common types (apps can extend/override)
class CommonNotificationTypes {
  static const reminder = NotificationType(value: 'reminder', priority: 5);
  static const alert = NotificationType(value: 'alert', priority: 8);
  static const promotion = NotificationType(value: 'promotion', priority: 3);
  static const system = NotificationType(value: 'system', priority: 10);

  /// Booking app specific (example - not hardcoded in core)
  static NotificationType bookingReminder(Duration offset) => NotificationType(
    value: 'booking_reminder',
    defaultOffset: offset,
    priority: 7,
  );
}
