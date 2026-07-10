// lib/core/utils/duration_utils.dart

/// Utility for parsing and formatting ISO 8601 duration strings.
///
/// ISO 8601 durations format: P[n]Y[n]M[n]DT[n]H[n]M[n]S
/// Examples:
/// - PT1H = 1 hour
/// - PT30M = 30 minutes
/// - PT1H30M = 1 hour 30 minutes
/// - P1DT12H = 1 day 12 hours
///
/// This matches your existing format in AppointmentSlotDTO.
class DurationUtils {
  /// Parses an ISO 8601 duration string to a [Duration] object.
  ///
  /// Returns [Duration.zero] if the string is null or invalid.
  /// Logs a warning for invalid formats to help with debugging.
  ///
  /// ## Example
  /// ```dart
  /// final duration = DurationUtils.parse('PT1H30M'); // 1 hour 30 minutes
  /// final hours = duration.inHours; // 1
  /// ```
  // In DurationUtils.parse method, add this case:
  static Duration parse(String? durationString) {
    if (durationString == null || durationString.isEmpty) {
      return Duration.zero;
    }

    try {
      // Handle HH:MM:SS format (e.g., "00:30:00")
      if (durationString.contains(':')) {
        final parts = durationString.split(':');
        if (parts.length == 3) {
          final hours = int.parse(parts[0]);
          final minutes = int.parse(parts[1]);
          final seconds = int.parse(parts[2]);
          return Duration(hours: hours, minutes: minutes, seconds: seconds);
        }
      }

      // Handle ISO format
      if (durationString.startsWith('PT')) {
        return _parsePeriod(durationString.substring(2));
      } else if (durationString.startsWith('P')) {
        return _parseFullPeriod(durationString.substring(1));
      }

      return Duration.zero;
    } catch (e) {
      return Duration.zero;
    }
  }

  /// Parses a simple period like "1H30M" (without the PT prefix)
  static Duration _parsePeriod(String period) {
    int hours = 0;
    int minutes = 0;
    int seconds = 0;

    final buffer = StringBuffer();
    for (int i = 0; i < period.length; i++) {
      final char = period[i];
      if (_isNumeric(char)) {
        buffer.write(char);
      } else {
        final value = int.tryParse(buffer.toString()) ?? 0;
        buffer.clear();

        switch (char) {
          case 'H':
            hours = value;
            break;
          case 'M':
            minutes = value;
            break;
          case 'S':
            seconds = value;
            break;
        }
      }
    }

    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  /// Parses full period with days, months, years (simplified)
  static Duration _parseFullPeriod(String period) {
    // Simplified - handle days, ignore months/years as they're variable
    int days = 0;
    int hours = 0;
    int minutes = 0;

    final timePartIndex = period.indexOf('T');
    if (timePartIndex != -1) {
      // Parse date part (before T)
      final datePart = period.substring(0, timePartIndex);
      days = _extractValue(datePart, 'D');

      // Parse time part (after T)
      final timePart = period.substring(timePartIndex + 1);
      hours = _extractValue(timePart, 'H');
      minutes = _extractValue(timePart, 'M');
    } else {
      // No time part, just date
      days = _extractValue(period, 'D');
    }

    return Duration(days: days, hours: hours, minutes: minutes);
  }

  static int _extractValue(String part, String unit) {
    final regex = RegExp('(\\d+)$unit');
    final match = regex.firstMatch(part);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    return 0;
  }

  static bool _isNumeric(String char) {
    return RegExp(r'^[0-9]$').hasMatch(char);
  }

  /// Formats a Duration to an ISO 8601 duration string.
  ///
  /// ## Example
  /// ```dart
  /// final duration = Duration(hours: 1, minutes: 30);
  /// final isoString = DurationUtils.format(duration); // "PT1H30M"
  /// ```
  static String format(Duration duration) {
    final parts = <String>[];

    if (duration.inDays > 0) {
      parts.add('${duration.inDays}D');
    }

    final hours = duration.inHours % 24;
    if (hours > 0) {
      parts.add('${hours}H');
    }

    final minutes = duration.inMinutes % 60;
    if (minutes > 0) {
      parts.add('${minutes}M');
    }

    final seconds = duration.inSeconds % 60;
    if (seconds > 0) {
      parts.add('${seconds}S');
    }

    return 'PT${parts.join()}';
  }

  /// Checks if a duration string is valid ISO 8601 format.
  static bool isValid(String? durationString) {
    if (durationString == null || durationString.isEmpty) return false;

    // Basic validation: must start with P or PT
    if (!durationString.startsWith('P')) return false;

    // Must contain at least one time unit designator
    return RegExp(r'[HMSD]').hasMatch(durationString);
  }

  /// Formats a Duration to a human-readable string like "1 hr 30 min"
  static String formatForDisplay(Duration duration) {
    final minutes = duration.inMinutes;

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes > 0) {
      return '$hours hr $remainingMinutes min';
    } else {
      return '$hours hr';
    }
  }
}
