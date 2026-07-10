// lib/core/utils/notification_utils.dart

import 'package:flutter/material.dart';

/// Utility class for notification formatting and helpers
class NotificationUtils {
  NotificationUtils._();

  /// Get icon for notification type
  static IconData getIconForType(String type) {
    switch (type) {
      case 'booking_reminder_24h':
      case 'booking_reminder_1h':
      case 'booking_reminder_5min':
        return Icons.event_available;
      case 'shop_reminder_15min':
        return Icons.storefront;
      case 'review_request':
        return Icons.rate_review;
      case 'new_booking_shop':
        return Icons.book_online;
      case 'new_shop_nearby':
        return Icons.store;
      case 'new_review_shop':
        return Icons.star;
      default:
        return Icons.notifications;
    }
  }

  /// Get color for notification type based on theme
  static Color getColorForType(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'booking_reminder_24h':
      case 'booking_reminder_1h':
      case 'booking_reminder_5min':
        return colorScheme.primary;
      case 'shop_reminder_15min':
        return colorScheme.secondary;
      case 'review_request':
        return colorScheme.tertiary;
      case 'new_booking_shop':
        return Colors.green;
      case 'new_shop_nearby':
        return Colors.blue;
      case 'new_review_shop':
        return Colors.amber;
      default:
        return colorScheme.primary;
    }
  }

  /// Format notification body with parameters
  static String formatMessage(String template, Map<String, String> params) {
    String message = template;
    params.forEach((key, value) {
      message = message.replaceAll('{$key}', value);
    });
    return message;
  }
}
