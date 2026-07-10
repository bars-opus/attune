// lib/features/notifications/data/repositories/notification_repository_impl.dart
import 'package:attune/core/notifications/data/models/push_token_model.dart';
import 'package:attune/core/notifications/data/models/scheduled_notification_model.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/domain/entities/scheduled_notification.dart';
import 'package:attune/core/notifications/exceptions/notification_exceptions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase implementation of notification repository
class NotificationRepositoryImpl implements NotificationRepositoryInterface {
  final SupabaseClient _supabase;

  NotificationRepositoryImpl(this._supabase);

  @override
  Future<List<ScheduledNotification>> scheduleNotifications(
    List<ScheduledNotification> notifications,
  ) async {
    try {
      // Convert to models
      final models =
          notifications
              .map((n) => ScheduledNotificationModel.fromDomain(n).toJson())
              .toList();

      // Insert all notifications
      final response =
          await _supabase
              .from('scheduled_notifications')
              .insert(models)
              .select();

      // Convert back to domain entities
      return (response as List)
          .map((json) => ScheduledNotificationModel.fromJson(json).toDomain())
          .toList();
    } catch (e) {
      throw NotificationSchedulingException(
        'Failed to schedule notifications: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<int> cancelBookingNotifications(String bookingId) async {
    try {
      final response = await _supabase.rpc(
        'cancel_booking_notifications',
        params: {'p_booking_id': bookingId},
      );

      return response as int;
    } catch (e) {
      throw NotificationSchedulingException(
        'Failed to cancel booking notifications: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<void> queueImmediateNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String priority = 'normal',
  }) async {
    try {
      // Inserted with scheduled_for = now() so the cron picks it up on its
      // next run (typically within 1 minute). The metadata shape matches what
      // process-scheduled-notifications expects: {title, body, ...extra}.
      final now = DateTime.now().toIso8601String();
      await _supabase.from('scheduled_notifications').insert({
        'user_id': userId,
        'notification_type': 'immediate',
        'scheduled_for': now,
        'status': 'pending',
        'metadata': {
          'title': title,
          'body': body,
          ...?data,
        },
        'created_at': now,
        'updated_at': now,
      });
    } catch (e) {
      throw PushNotificationException(
        'Failed to queue notification: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<void> savePushToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    try {
      // Check if token already exists
      final existing =
          await _supabase
              .from('push_tokens')
              .select()
              .eq('token', token)
              .maybeSingle();

      final now = DateTime.now();

      if (existing != null) {
        // Update existing token
        await _supabase
            .from('push_tokens')
            .update({
              'user_id': userId,
              'platform': platform,
              'is_active': true,
              'updated_at': now.toIso8601String(),
            })
            .eq('token', token);
      } else {
        // Insert new token
        final model = PushTokenModel(
          userId: userId,
          token: token,
          platform: platform,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );

        await _supabase.from('push_tokens').insert(model.toJson());
      }
    } catch (e) {
      throw PushNotificationException(
        'Failed to save push token: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<void> removePushToken(String token) async {
    try {
      await _supabase
          .from('push_tokens')
          .update({'is_active': false})
          .eq('token', token);
    } catch (e) {
      throw PushNotificationException(
        'Failed to remove push token: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

 @override
Future<List<AppNotification>> getUserNotifications(String userId) async {
  try {
    final response = await _supabase
        .from('in_app_notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    
    return (response as List).map((json) {
      return AppNotification(
        id: json['id'],
        title: json['title'],
        body: json['body'],
        data: json['data'] as Map<String, dynamic>?,
        isRead: json['is_read'] as bool? ?? false,
        readAt: json['read_at'] != null 
            ? DateTime.parse(json['read_at'] as String) 
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
    }).toList();
  } catch (e) {
    throw NotificationException('Failed to get notifications: $e');
  }
}

  @override
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _supabase
          .from('in_app_notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId);
    } catch (e) {
      throw NotificationException('Failed to mark notification as read: $e');
    }
  }

  @override
  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      await _supabase
          .from('in_app_notifications')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      throw NotificationException('Failed to mark all notifications as read: $e');
    }
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _supabase
          .from('in_app_notifications')
          .delete()
          .eq('id', notificationId);
    } catch (e) {
      throw NotificationException('Failed to delete notification: $e');
    }
  }

  @override
  Future<int> getUnreadCount(String userId) async {
    try {
      // Fetch only the IDs of unread notifications (lightweight)
      final response = await _supabase
          .from('in_app_notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      // Return the count by checking the list length
      return (response as List).length;
    } catch (e) {
      return 0; // Return 0 on error
    }
  }

  @override
  Future<List<String>> getNearbyUsers({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_nearby_users',
        params: {
          'shop_lat': latitude,
          'shop_lng': longitude,
          'radius_km': radiusKm,
        },
      );

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => json['user_id'] as String).toList();
    } catch (e) {
      throw LocationNotificationException(
        'Failed to get nearby users: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getNotificationSettings(String userId) async {
    try {
      final response =
          await _supabase
              .from('notification_settings')
              .select()
              .eq('user_id', userId)
              .maybeSingle();

      if (response == null) {
        // Create default settings
        final defaultSettings = {
          'user_id': userId,
          'push_enabled': true,
          'email_enabled': false,
          'marketing_enabled': true,
          'booking_reminders_enabled': true,
          'new_shops_nearby_enabled': true,
          'chat_message_preview_enabled': false,
          'updated_at': DateTime.now().toIso8601String(),
        };

        await _supabase.from('notification_settings').insert(defaultSettings);

        return defaultSettings;
      }

      return response;
    } catch (e) {
      throw NotificationSettingsException(
        'Failed to get notification settings: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<void> updateNotificationSettings({
    required String userId,
    bool? pushEnabled,
    bool? emailEnabled,
    bool? marketingEnabled,
    bool? bookingRemindersEnabled,
    bool? newShopsNearbyEnabled,
    bool? chatMessagePreviewEnabled,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (pushEnabled != null) {
        updates['push_enabled'] = pushEnabled;
      }
      if (emailEnabled != null) {
        updates['email_enabled'] = emailEnabled;
      }
      if (marketingEnabled != null) {
        updates['marketing_enabled'] = marketingEnabled;
      }
      if (bookingRemindersEnabled != null) {
        updates['booking_reminders_enabled'] = bookingRemindersEnabled;
      }
      if (newShopsNearbyEnabled != null) {
        updates['new_shops_nearby_enabled'] = newShopsNearbyEnabled;
      }
      if (chatMessagePreviewEnabled != null) {
        updates['chat_message_preview_enabled'] = chatMessagePreviewEnabled;
      }

      await _supabase
          .from('notification_settings')
          .update(updates)
          .eq('user_id', userId);
    } catch (e) {
      throw NotificationSettingsException(
        'Failed to update notification settings: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }

  @override
  Future<void> updateUserLocation({
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _supabase.from('user_locations').upsert({
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw LocationNotificationException(
        'Failed to update user location: $e',
        code: e is PostgrestException ? e.code : null,
      );
    }
  }
}
