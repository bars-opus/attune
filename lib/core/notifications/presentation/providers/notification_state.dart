// lib/features/notifications/presentation/providers/notification_state.dart

import 'package:attune/core/notifications/domain/entities/app_notification.dart';

/// State for notification list
class NotificationListState {
  final List<AppNotification> notifications;
  final bool isLoading;
  final String? error;
  final bool hasMore;

  const NotificationListState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.hasMore = true,
  });

  NotificationListState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
    String? error,
    bool? hasMore,
  }) {
    return NotificationListState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  factory NotificationListState.initial() => const NotificationListState();
}

/// State for notification settings
class NotificationSettingsState {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool marketingEnabled;
  final bool bookingRemindersEnabled;
  final bool newShopsNearbyEnabled;
  final bool chatMessagePreviewEnabled;
  final bool isLoading;
  final String? error;
  final bool isSaving;

  const NotificationSettingsState({
    this.pushEnabled = true,
    this.emailEnabled = false,
    this.marketingEnabled = true,
    this.bookingRemindersEnabled = true,
    this.newShopsNearbyEnabled = true,
    this.chatMessagePreviewEnabled = false,
    this.isLoading = false,
    this.error,
    this.isSaving = false,
  });

  NotificationSettingsState copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? marketingEnabled,
    bool? bookingRemindersEnabled,
    bool? newShopsNearbyEnabled,
    bool? chatMessagePreviewEnabled,
    bool? isLoading,
    String? error,
    bool? isSaving,
  }) {
    return NotificationSettingsState(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      marketingEnabled: marketingEnabled ?? this.marketingEnabled,
      bookingRemindersEnabled:
          bookingRemindersEnabled ?? this.bookingRemindersEnabled,
      newShopsNearbyEnabled:
          newShopsNearbyEnabled ?? this.newShopsNearbyEnabled,
      chatMessagePreviewEnabled:
          chatMessagePreviewEnabled ?? this.chatMessagePreviewEnabled,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}
