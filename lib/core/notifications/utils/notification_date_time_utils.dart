// lib/core/utils/date_time_utils.dart

/// Utility class for date and time operations
class NotificationDateTimeUtils {
  NotificationDateTimeUtils._();
  
  /// Combine a date and time into a single DateTime
  static DateTime combineDateAndTime(DateTime date, DateTime time) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
      time.second,
    );
  }
  
  /// Format time for display (e.g., "2:30 PM")
  static String formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }
  
  /// Format date for display (e.g., "Monday, Jan 15")
  static String formatDate(DateTime date) {
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
  
  /// Calculate reminder times for a booking
  static Map<String, DateTime> calculateBookingReminders({
    required DateTime appointmentDateTime,
    required Duration appointmentDuration,
  }) {
    return {
      '24h': appointmentDateTime.subtract(const Duration(hours: 24)),
      '1h': appointmentDateTime.subtract(const Duration(hours: 1)),
      '5min': appointmentDateTime.subtract(const Duration(minutes: 5)),
      'shop_15min': appointmentDateTime.subtract(const Duration(minutes: 15)),
      'review': appointmentDateTime.add(appointmentDuration).add(const Duration(minutes: 30)),
    };
  }
  
  /// Check if a DateTime is in the past
  static bool isInPast(DateTime dateTime) {
    return dateTime.isBefore(DateTime.now());
  }
  
  /// Get time difference in human-readable format
  static String timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    
    if (difference.inDays > 7) {
      return formatDate(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}
