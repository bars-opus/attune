import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/notifications/config/notification_setting_toggle.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/domain/entities/notification_template.dart';
import 'package:attune/core/notifications/domain/entities/notification_type.dart';

/// The single configuration object for the notification engine.
///
/// Drop this into any Flutter + Supabase + OneSignal app.
/// Override [notificationConfigProvider] in your root [ProviderScope] with an
/// instance customised for your app — see NOTIFICATION_ENGINE.md for the full
/// integration guide.
class NotificationConfig {
  /// Your app's display name (used in log messages and default channel names).
  final String appName;

  /// Android notification channel ID (required for Android 8+).
  final String defaultChannelId;

  /// Android notification channel display name.
  final String defaultChannelName;

  /// Map of notification type keys to their [NotificationType] definitions.
  final Map<String, NotificationType> notificationTypes;

  /// Map of template IDs to [NotificationTemplate] definitions.
  final Map<String, NotificationTemplate> templates;

  /// Default reminder offsets used by [ScheduleBookingRemindersUseCase]
  /// (or whatever scheduling use case your app provides).
  final List<Duration> defaultReminderOffsets;

  /// Called when the user taps a notification in the inbox.
  ///
  /// Use this to perform app-specific navigation. The [AppNotification.data]
  /// map will contain whatever `data` payload was sent with the push.
  ///
  /// Example:
  /// ```dart
  /// onNotificationTap: (notification, context) {
  ///   final type = notification.data?['type'] as String?;
  ///   if (type == 'booking_reminder') context.go('/calendar');
  /// }
  /// ```
  final void Function(AppNotification notification, BuildContext context)?
  onNotificationTap;

  /// Optional custom template renderer. Defaults to `{{key}}` substitution.
  final String Function(String template, Map<String, dynamic> data)?
  templateRenderer;

  /// App-specific toggles shown in the "Notification Types" section of the
  /// settings screen. The master push toggle and email/marketing toggles are
  /// always present; these are the per-feature toggles your app needs.
  ///
  /// Leave empty for apps that don't need per-type granularity.
  final List<NotificationSettingToggle> settingToggles;

  const NotificationConfig({
    required this.appName,
    this.defaultChannelId = 'default_notifications',
    this.defaultChannelName = 'Notifications',
    this.notificationTypes = const {},
    this.templates = const {},
    this.defaultReminderOffsets = const [
      Duration(hours: 24),
      Duration(hours: 1),
      Duration(minutes: 5),
    ],
    this.onNotificationTap,
    this.templateRenderer,
    this.settingToggles = const [],
  });

  factory NotificationConfig.defaults() {
    return const NotificationConfig(
      appName: 'App',
    );
  }

  NotificationType? getType(String key) => notificationTypes[key];
  NotificationTemplate? getTemplate(String id) => templates[id];
}

/// Override this in your root [ProviderScope] with your app's [NotificationConfig].
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     notificationConfigProvider.overrideWithValue(
///       NotificationConfig(appName: 'MyApp', ...),
///     ),
///   ],
///   child: MyApp(),
/// )
/// ```
final notificationConfigProvider = Provider<NotificationConfig>((ref) {
  return NotificationConfig.defaults();
});
