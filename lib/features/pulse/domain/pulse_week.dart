// lib/features/pulse/domain/pulse_week.dart

/// The UTC Sunday on or after the UTC date of [now]; a Sunday is its own
/// week ending. Mirrors compute-pulse's getWeekEnding exactly, so a check-in
/// is filed under the week the server computes.
DateTime pulseWeekEnding(DateTime now) {
  final u = now.toUtc();
  final day = DateTime.utc(u.year, u.month, u.day);
  return day.add(Duration(days: (DateTime.sunday - day.weekday) % 7));
}

/// `yyyy-MM-dd`, the `week_ending` key.
String pulseWeekEndingKey(DateTime now) =>
    pulseWeekEnding(now).toIso8601String().split('T').first;
