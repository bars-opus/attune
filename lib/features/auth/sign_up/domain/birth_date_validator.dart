import 'dart:ui' show Locale;

import 'package:intl/date_time_patterns.dart';

/// A2's date-of-birth rules (Spec 1 §3.3).
enum BirthDateOrder { dayMonthYear, monthDayYear }

enum BirthDateError {
  dayRange,
  monthRange,
  yearDigits,
  noSuchDate,
  future,
  tooOld,
}

/// Regions that write the month first when intl has no pattern for the
/// exact locale (its table has no en_GH, en_NG or en_KE, and plain `en` is
/// the US order).
const _monthFirstRegions = {
  'US',
  'PR',
  'GU',
  'AS',
  'MP',
  'UM',
  'VI',
  'FM',
  'MH',
  'PW',
  'PH',
};

/// Day · Month · Year or Month · Day · Year, from the locale's
/// `DateFormat.yMd` pattern. A year-first pattern (y-MM-dd) reads day
/// first. Without an exact pattern: month first only for the regions that
/// write it so, day first everywhere else.
BirthDateOrder birthDateOrderFor(Locale locale) {
  final patterns = dateTimePatternMap();
  final region = locale.countryCode;
  final key =
      region == null || region.isEmpty
          ? locale.languageCode
          : '${locale.languageCode}_$region';
  final exact = patterns[key]?['yMd'];
  if (exact != null) {
    if (exact.startsWith('y')) return BirthDateOrder.dayMonthYear;
    return exact.indexOf('M') < exact.indexOf('d')
        ? BirthDateOrder.monthDayYear
        : BirthDateOrder.dayMonthYear;
  }
  return region != null && _monthFirstRegions.contains(region)
      ? BirthDateOrder.monthDayYear
      : BirthDateOrder.dayMonthYear;
}

/// Checks the three fields in the order the person reads the errors.
/// [todayUtc] is today's UTC date (spec: stricter at the day boundary).
({DateTime? date, BirthDateError? error}) validateBirthDate({
  required String day,
  required String month,
  required String year,
  required DateTime todayUtc,
}) {
  final d = int.tryParse(day.trim());
  final m = int.tryParse(month.trim());
  if (d == null || d < 1 || d > 31) {
    return (date: null, error: BirthDateError.dayRange);
  }
  if (m == null || m < 1 || m > 12) {
    return (date: null, error: BirthDateError.monthRange);
  }
  if (!RegExp(r'^[0-9]{4}$').hasMatch(year.trim())) {
    return (date: null, error: BirthDateError.yearDigits);
  }
  final y = int.parse(year.trim());
  final date = DateTime.utc(y, m, d);
  if (date.month != m || date.day != d) {
    return (date: null, error: BirthDateError.noSuchDate);
  }
  final today = DateTime.utc(todayUtc.year, todayUtc.month, todayUtc.day);
  if (date.isAfter(today)) return (date: null, error: BirthDateError.future);
  if (date.isBefore(DateTime.utc(today.year - 120, today.month, today.day))) {
    return (date: null, error: BirthDateError.tooOld);
  }
  return (date: date, error: null);
}

/// Whole years on [todayUtc], the server's rule (private.age_on_utc_today):
/// a 29 February birthday turns a year older on 1 March in other years.
int ageOn(DateTime birthDate, DateTime todayUtc) {
  var years = todayUtc.year - birthDate.year;
  final beforeBirthday =
      todayUtc.month < birthDate.month ||
      (todayUtc.month == birthDate.month && todayUtc.day < birthDate.day);
  if (beforeBirthday) years--;
  return years;
}

/// "27 3 1996" or "3 27 1996", for A2's example line.
String birthDateExample(BirthDateOrder order) =>
    order == BirthDateOrder.dayMonthYear ? '27 3 1996' : '3 27 1996';
