// lib/features/notifications/presentation/providers/notification_settings_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';
import 'notification_state.dart';

/// Notifier for managing notification settings
class NotificationSettingsNotifier
    extends StateNotifier<NotificationSettingsState> {
  final NotificationRepositoryInterface _repository;
  final String _userId;

  NotificationSettingsNotifier({
    required NotificationRepositoryInterface repository,
    required String userId,
  }) : _repository = repository,
       _userId = userId,
       super(const NotificationSettingsState());

  /// Load settings from server
  Future<void> loadSettings() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final settings = await _repository.getNotificationSettings(_userId);

      state = state.copyWith(
        pushEnabled: settings['push_enabled'] as bool? ?? true,
        emailEnabled: settings['email_enabled'] as bool? ?? false,
        marketingEnabled: settings['marketing_enabled'] as bool? ?? true,
        bookingRemindersEnabled:
            settings['booking_reminders_enabled'] as bool? ?? true,
        newShopsNearbyEnabled:
            settings['new_shops_nearby_enabled'] as bool? ?? true,
        chatMessagePreviewEnabled:
            settings['chat_message_preview_enabled'] as bool? ?? false,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load settings: $e',
      );
    }
  }

  /// Update push enabled setting
  Future<void> setPushEnabled(bool enabled) async {
    await _updateSetting(pushEnabled: enabled);
  }

  /// Update email enabled setting
  Future<void> setEmailEnabled(bool enabled) async {
    await _updateSetting(emailEnabled: enabled);
  }

  /// Update marketing enabled setting
  Future<void> setMarketingEnabled(bool enabled) async {
    await _updateSetting(marketingEnabled: enabled);
  }

  /// Update booking reminders setting
  Future<void> setBookingRemindersEnabled(bool enabled) async {
    await _updateSetting(bookingRemindersEnabled: enabled);
  }

  /// Update new shops nearby setting
  Future<void> setNewShopsNearbyEnabled(bool enabled) async {
    await _updateSetting(newShopsNearbyEnabled: enabled);
  }

  /// Update chat message preview setting
  Future<void> setChatMessagePreviewEnabled(bool enabled) async {
    await _updateSetting(chatMessagePreviewEnabled: enabled);
  }

  /// Generic method to update settings
  Future<void> _updateSetting({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? marketingEnabled,
    bool? bookingRemindersEnabled,
    bool? newShopsNearbyEnabled,
    bool? chatMessagePreviewEnabled,
  }) async {
    final previousState = state;
    state = state.copyWith(
      pushEnabled: pushEnabled ?? state.pushEnabled,
      emailEnabled: emailEnabled ?? state.emailEnabled,
      marketingEnabled: marketingEnabled ?? state.marketingEnabled,
      bookingRemindersEnabled:
          bookingRemindersEnabled ?? state.bookingRemindersEnabled,
      newShopsNearbyEnabled:
          newShopsNearbyEnabled ?? state.newShopsNearbyEnabled,
      chatMessagePreviewEnabled:
          chatMessagePreviewEnabled ?? state.chatMessagePreviewEnabled,
      isSaving: true,
      error: null,
    );

    try {
      await _repository.updateNotificationSettings(
        userId: _userId,
        pushEnabled: pushEnabled,
        emailEnabled: emailEnabled,
        marketingEnabled: marketingEnabled,
        bookingRemindersEnabled: bookingRemindersEnabled,
        newShopsNearbyEnabled: newShopsNearbyEnabled,
        chatMessagePreviewEnabled: chatMessagePreviewEnabled,
      );

      state = state.copyWith(isSaving: false);
    } catch (e) {
      state = previousState.copyWith(
        error: 'Failed to save settings: $e',
        isSaving: false,
      );
    }
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    await _updateSetting(
      pushEnabled: true,
      emailEnabled: false,
      marketingEnabled: true,
      bookingRemindersEnabled: true,
      newShopsNearbyEnabled: true,
      chatMessagePreviewEnabled: false,
    );
  }
}
