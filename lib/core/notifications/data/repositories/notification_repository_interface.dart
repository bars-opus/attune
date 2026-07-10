// lib/features/notifications/domain/repositories/notification_repository_interface.dart
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/domain/entities/scheduled_notification.dart';

/// Interface for notification repository
abstract class NotificationRepositoryInterface {
  /// Schedule one or more notifications
  Future<List<ScheduledNotification>> scheduleNotifications(
    List<ScheduledNotification> notifications,
  );

  /// Cancel all pending notifications for a booking
  Future<int> cancelBookingNotifications(String bookingId);

  /// Queue an immediate push notification
  Future<void> queueImmediateNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String priority = 'normal',
  });

  /// Save a push token for a user
  Future<void> savePushToken({
    required String userId,
    required String token,
    required String platform,
  });

  /// Remove/disable a push token
  Future<void> removePushToken(String token);

  /// Get all in-app notifications for a user
  Future<List<AppNotification>> getUserNotifications(String userId);

  /// Mark a notification as read
  Future<void> markNotificationAsRead(String notificationId);

  /// Mark all notifications as read for a user (single batch query)
  Future<void> markAllNotificationsAsRead(String userId);

  /// Permanently delete a notification
  Future<void> deleteNotification(String notificationId);

  /// Get unread notification count
  Future<int> getUnreadCount(String userId);

  /// Get nearby users for a shop location
  Future<List<String>> getNearbyUsers({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  });

  /// Get or create notification settings for a user
  Future<Map<String, dynamic>> getNotificationSettings(String userId);

  /// Update notification settings
  Future<void> updateNotificationSettings({
    required String userId,
    bool? pushEnabled,
    bool? emailEnabled,
    bool? marketingEnabled,
    bool? bookingRemindersEnabled,
    bool? newShopsNearbyEnabled,
    bool? chatMessagePreviewEnabled,
  });

  /// Save or update user location for geo-notifications
  Future<void> updateUserLocation({
    required String userId,
    required double latitude,
    required double longitude,
  });
}
