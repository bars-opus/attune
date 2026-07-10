import 'package:intl/intl.dart';

class MyDateFormat {
  static String toDate(DateTime dateTime) {
    final date = DateFormat.yMMMMEEEEd().format(dateTime);
    return '$date';
  }

  static String toDateShort(DateTime dateTime) {
    final date = DateFormat('EEE, d MMM').format(dateTime);
    return '$date';
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
