import 'package:intl/intl.dart';

class MyDateFormat {
  /// Between a date and anything shown with it on the same line, e.g.
  /// "Tuesday, October 4, 2026 - 0 of 4 done".
  static const String separator = ' - ';

  /// Joins a date with its details using [separator]; empty parts drop out.
  static String join(Iterable<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(separator);

  static String toDate(DateTime dateTime) {
    final date = DateFormat.yMMMMEEEEd().format(dateTime);
    return '$date';
  }

  static String toDateShort(DateTime dateTime) {
    final date = DateFormat('EEE, d MMM').format(dateTime);
    return '$date';
  }

  /// Abbreviated weekday, full month name, no day number or year — e.g.
  /// "Sun, November". For a UI spot (the focused message menu) where
  /// [toDate]'s full "Sunday, November 8, 2026" ran too long next to a
  /// time stamp on the same line.
  static String toWeekdayMonth(DateTime dateTime) {
    return DateFormat('EEE, MMMM').format(dateTime);
  }

  static String toTime(DateTime dateTime) {
    final time = DateFormat('hh:mm a').format(dateTime);
    return '$time';
  }

  static List<DateTime> getDatesInRange(DateTime startDate, DateTime endDate) {
    List<DateTime> dates = [];
    for (int i = 0; i <= endDate.difference(startDate).inDays; i++) {
      dates.add(startDate.add(Duration(days: i)));
    }
    return dates;
  }
}
