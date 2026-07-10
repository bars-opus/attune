// lib/features/notifications/services/notification_service.dart (REFACTORED)

import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';
import 'package:attune/core/notifications/domain/entities/notification_params.dart';
import 'package:attune/core/notifications/domain/entities/scheduled_notification.dart';

/// Generic notification service - works with any app
class NotificationService {
  final NotificationRepositoryInterface _repository;

  // Optional callbacks for app-specific behavior
  void Function(String type, Map<String, dynamic> data)? onNotificationTap;
  String Function(String template, Map<String, dynamic> data)? templateRenderer;

  NotificationService({
    required NotificationRepositoryInterface repository,
    this.onNotificationTap,
    this.templateRenderer,
  }) : _repository = repository;

  /// Schedule a single notification
  Future<void> schedule(ScheduleNotificationParams params) async {
    final scheduledNotification = ScheduledNotification(
      id: '',
      notificationType: params.type.value, // Extract the string value
      userId: params.userId,
      scheduledFor: params.scheduledFor,
      status: NotificationStatus.pending,
      metadata: {
        'data': params.data,
        'title_override': params.titleOverride,
        'body_override': params.bodyOverride,
        'type': params.type.value,
      },
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _repository.scheduleNotifications([scheduledNotification]);
  }

  /// Schedule multiple reminders with offsets
  Future<void> scheduleReminders(ScheduleRemindersParams params) async {
    final notifications = <ScheduledNotification>[];

    for (final offset in params.offsets) {
      final scheduledFor = DateTime.now().add(offset);

      // Generate title and body using template system
      final title =
          params.titleTemplate != null
              ? _renderTemplate(params.titleTemplate!, params.templateData)
              : '${params.baseType.value}_reminder';

      final body =
          params.bodyTemplate != null
              ? _renderTemplate(params.bodyTemplate!, params.templateData)
              : '';

      notifications.add(
        ScheduledNotification(
          id: '',
          notificationType:
              '${params.baseType.value}_${offset.inHours}h', // String value
          userId: params.userId,
          scheduledFor: scheduledFor,
          status: NotificationStatus.pending,
          metadata: {
            'reference_id': params.referenceId,
            'offset_hours': offset.inHours,
            'data': params.templateData,
            'title': title,
            'body': body,
          },
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    await _repository.scheduleNotifications(notifications);
  }

  /// Send immediate notification
  Future<void> sendImmediate(ImmediateNotificationParams params) async {
    await _repository.queueImmediateNotification(
      userId: params.userId,
      title: params.title,
      body: params.body,
      data: {
        'type': params.type.value,/// In the Dart code snippet you provided, the `null` value is
        /// being passed as an argument to the `NotificationService`
        /// constructor when initializing the
        /// `notificationServiceProvider` provider.
        
        'priority': params.priority,
        ...params.data,
      },
      priority: params.priority >= 7 ? 'high' : 'normal',
    );
  }

  /// Cancel all notifications for a reference (booking, order, etc.)
  Future<void> cancelByReference(String referenceId) async {
    // Implementation depends on your repository
    // You may need to add this method
  }

  /// Generic template renderer
  String _renderTemplate(String template, Map<String, dynamic> data) {
    if (templateRenderer != null) {
      return templateRenderer!(template, data);
    }

    // Simple default renderer
    var result = template;
    for (final entry in data.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value.toString());
    }
    return result;
  }
}
