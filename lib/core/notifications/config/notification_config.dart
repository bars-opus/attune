// Attune-specific notification configuration.
//
// When copying this engine to a new app, replace the contents of this file
// with your own notification types, templates, tap-navigation logic, and
// setting toggles. Everything else in core/notifications/ is generic and
// can be copied unchanged.
//
// See NOTIFICATION_ENGINE.md for the full integration guide.

import 'package:go_router/go_router.dart';
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/config/notification_setting_toggle.dart';
import 'package:attune/core/notifications/domain/entities/notification_template.dart';
import 'package:attune/core/notifications/domain/entities/notification_type.dart';

/// Returns the Attune [NotificationConfig],
///
/// Pass this to [notificationConfigProvider] in the root [ProviderScope].
NotificationConfig buildNanoEmbryoNotificationConfig() {
  return NotificationConfig(
    appName: 'Attune',
    defaultChannelId: 'attune_notifications',
    defaultChannelName: 'Attune Notifications',
    defaultReminderOffsets: const [
      Duration(hours: 24),
      Duration(hours: 1),
      Duration(minutes: 5),
      Duration(minutes: 15), // shop-owner reminder
    ],
    notificationTypes: {
      'new_message': NotificationType(
        value: 'new_message',
        priority: 9,
      ),
      'safety_resources': NotificationType(
        value: 'safety_resources',
        priority: 10,
      ),
      'booking_confirmation': NotificationType(
        value: 'booking_confirmation',
        priority: 8,
      ),
      'booking_reminder': NotificationType(
        value: 'booking_reminder',
        priority: 7,
      ),
      'new_review': NotificationType(value: 'new_review', priority: 6),
      'new_shop_nearby': NotificationType(
        value: 'new_shop_nearby',
        priority: 5,
      ),
    },
    templates: {
      'booking_confirmation_shop': NotificationTemplate(
        id: 'booking_confirmation_shop',
        titleTemplate: 'New Booking Received!',
        bodyTemplate: '{{user_name}} booked {{service_names}} at {{time}}',
      ),
      'booking_reminder_client': NotificationTemplate(
        id: 'booking_reminder_client',
        titleTemplate: 'Appointment {{offset_text}}',
        bodyTemplate:
            'Your {{service_names}} appointment is {{offset_text}} at {{time}}',
      ),
    },
    // ── Navigation from notification tap ──────────────────────────────────────
    // The router is obtained from GoRouter via context so we don't need
    // the global _appRouter here.
    onNotificationTap: (notification, context) {
      final type = notification.data?['type'] as String?;
      final shopId = notification.data?['shop_id'] as String?;

      switch (type) {
        case 'booking_reminder_24h':
        case 'booking_reminder_1h':
        case 'booking_reminder_5min':
        case 'shop_reminder_15min':
        case 'booking_created':
        case 'booking_confirmed':
        case 'booking_cancelled':
          GoRouter.of(context).go(RouteNames.calendar);
          return;

        case 'new_shop_nearby':
          if (shopId != null && shopId.isNotEmpty) {
            GoRouter.of(context).push(
              RouteNames.shopDetailsScreen,
              extra: {'shopId': shopId, 'coverImageUrl': ''},
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        case 'review_request':
        case 'new_message':
        case 'invite_accepted':
          final relationshipId =
              notification.data?['relationship_id'] as String?;
          if (relationshipId != null && relationshipId.isNotEmpty) {
            GoRouter.of(context).push(
              '${RouteNames.chatChannel}?relationshipId=${Uri.encodeComponent(relationshipId)}',
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        case 'safety_resources':
          GoRouter.of(context).go(RouteNames.safetyResources);
          return;

        case 'ask2_invite':
          final relationshipId = notification.data?['relationship_id'] as String?;
          if (relationshipId != null && relationshipId.isNotEmpty) {
            GoRouter.of(context).push(
              '/ask2/${Uri.encodeComponent(relationshipId)}',
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        default:
          GoRouter.of(context).go(RouteNames.home);
          return;
      }
    },
    // ── App-specific settings toggles ─────────────────────────────────────────
    settingToggles: [
      NotificationSettingToggle(
        label: 'Relationship Updates',
        description: 'Notifications about shared Attune activity',
        getValue: (state) => state.bookingRemindersEnabled,
        setValue: (notifier, value) =>
            notifier.setBookingRemindersEnabled(value),
      ),
      NotificationSettingToggle(
        label: 'Feature Announcements',
        description: 'Optional Attune updates and product notices',
        getValue: (state) => state.newShopsNearbyEnabled,
        setValue: (notifier, value) => notifier.setNewShopsNearbyEnabled(value),
      ),
    ],
  );
}
