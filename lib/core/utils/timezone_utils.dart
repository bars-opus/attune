// lib/core/utils/timezone_utils.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:intl/intl.dart';

class TimezoneUtils {
  static String? _cachedTimezone;

  /// Get device local timezone (cached for performance)
  static Future<String> getDeviceTimezone() async {
    if (_cachedTimezone != null) return _cachedTimezone!;
    
    try {
      if (kIsWeb) {
        _cachedTimezone = DateTime.now().timeZoneName.isNotEmpty
            ? DateTime.now().timeZoneName
            : 'UTC';
      } else {
        _cachedTimezone = await FlutterNativeTimezone.getLocalTimezone();
      }
      return _cachedTimezone!;
    } catch (e) {
      return 'UTC'; // Fallback
    }
  }

  /// Clear cached timezone (useful if user changes device settings)
  static void clearCache() {
    _cachedTimezone = null;
  }

  /// Convert UTC time to device local time
  static DateTime toDeviceLocalTime(DateTime utcTime) {
    return utcTime.toLocal();
  }

  /// Convert UTC time to any timezone (requires timezone package)
  static DateTime toTimezone(DateTime utcTime, String timezone) {
    // This requires the timezone package
    // For now, we'll just return local time
    return utcTime.toLocal();
  }

  /// Format time range in device local time
  static String formatTimeRange(DateTime startUtc, DateTime endUtc) {
    final localStart = toDeviceLocalTime(startUtc);
    final localEnd = toDeviceLocalTime(endUtc);
    final timeFormat = DateFormat.jm();
    return '${timeFormat.format(localStart)} - ${timeFormat.format(localEnd)}';
  }

  /// Format time range with timezone indicator
  static String formatTimeRangeWithTimezone(DateTime startUtc, DateTime endUtc) {
    final localStart = toDeviceLocalTime(startUtc);
    final localEnd = toDeviceLocalTime(endUtc);
    final timeFormat = DateFormat.jm();
    final tzAbbr = _getTimezoneAbbreviation(localStart);
    return '${timeFormat.format(localStart)} - ${timeFormat.format(localEnd)} $tzAbbr';
  }

  /// Format time range in UTC
  static String formatTimeRangeUtc(DateTime startUtc, DateTime endUtc) {
    final timeFormat = DateFormat.jm();
    return '${timeFormat.format(startUtc)} - ${timeFormat.format(endUtc)} UTC';
  }

  /// Get timezone abbreviation from offset
  static String _getTimezoneAbbreviation(DateTime time) {
    final offset = time.timeZoneOffset;
    
    // Common timezone abbreviations
    if (offset == Duration(hours: 0)) return 'GMT';
    if (offset == Duration(hours: 1)) return 'CET';  // Central European Time
    if (offset == Duration(hours: -5)) return 'EST'; // Eastern Standard Time
    if (offset == Duration(hours: -6)) return 'CST'; // Central Standard Time
    if (offset == Duration(hours: -7)) return 'MST'; // Mountain Standard Time
    if (offset == Duration(hours: -8)) return 'PST'; // Pacific Standard Time
    if (offset == Duration(hours: 5, minutes: 30)) return 'IST'; // Indian Standard Time
    if (offset == Duration(hours: 8)) return 'CST'; // China Standard Time
    if (offset == Duration(hours: 9)) return 'JST'; // Japan Standard Time
    if (offset == Duration(hours: 10)) return 'AEST'; // Australian Eastern Time
    
    // Generic fallback
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs();
    return 'GMT$sign$hours';
  }

  /// Check if a time is in daylight saving
  static bool isDaylightSaving(DateTime time) {
    // Simple check - in DST if offset is not standard
    // This is simplified; real DST detection is more complex
    final januaryOffset = DateTime(time.year, 1, 1).timeZoneOffset;
    final julyOffset = DateTime(time.year, 7, 1).timeZoneOffset;
    return januaryOffset != julyOffset;
  }
}
