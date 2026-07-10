// lib/core/network/exceptions/notification_exceptions.dart

/// Base exception for all notification-related errors
class NotificationException implements Exception {
  final String message;
  final String? code;

  NotificationException(this.message, {this.code});

  @override
  String toString() =>
      'NotificationException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Thrown when scheduling a notification fails
class NotificationSchedulingException extends NotificationException {
  NotificationSchedulingException(String message, {String? code})
    : super(message, code: code);
}

/// Thrown when sending a push notification fails
class PushNotificationException extends NotificationException {
  PushNotificationException(String message, {String? code})
    : super(message, code: code);
}

/// Thrown when a push token is expired or invalid
class TokenExpiredException extends NotificationException {
  TokenExpiredException(String message, {String? code})
    : super(message, code: code);
}

/// Thrown when notification settings cannot be retrieved
class NotificationSettingsException extends NotificationException {
  NotificationSettingsException(String message, {String? code})
    : super(message, code: code);
}

/// Thrown when location-based notification fails
class LocationNotificationException extends NotificationException {
  LocationNotificationException(String message, {String? code})
    : super(message, code: code);
}
