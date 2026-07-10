import 'package:attune/core/notifications/presentation/providers/notification_settings_notifier.dart';
import 'package:attune/core/notifications/presentation/providers/notification_state.dart';

/// Declares a single configurable toggle in the notification settings screen.
///
/// Apps pass a list of these into [NotificationConfig.settingToggles] to drive
/// the "Notification Types" section without modifying the screen source.
///
/// Example:
/// ```dart
/// NotificationSettingToggle(
///   label: 'Booking Reminders',
///   description: 'Get reminders before upcoming appointments',
///   getValue: (state) => state.bookingRemindersEnabled,
///   setValue: (notifier, value) => notifier.setBookingRemindersEnabled(value),
/// )
/// ```
class NotificationSettingToggle {
  final String label;
  final String? description;

  /// Reads the current value from the settings state snapshot.
  final bool Function(NotificationSettingsState state) getValue;

  /// Applies the new value via the notifier.
  final void Function(NotificationSettingsNotifier notifier, bool value) setValue;

  const NotificationSettingToggle({
    required this.label,
    this.description,
    required this.getValue,
    required this.setValue,
  });
}
