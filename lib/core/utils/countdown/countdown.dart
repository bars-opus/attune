/// Countdowns to a date (or a date range) and to a moment, computed from an
/// injected "now" so they are exact, testable, and app-agnostic.
library;

/// Whole calendar days from [from] to [to] in local time, ignoring the time
/// of day. Computed on UTC midnights so a 23- or 25-hour day (daylight
/// saving) still counts as exactly one day.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

enum CountdownPhase {
  /// Still ahead.
  upcoming,

  /// Today, or (for a range) within it.
  current,

  /// Over.
  past,
}

/// Where "now" stands relative to the target, with a ready-made label.
class CountdownSnapshot {
  const CountdownSnapshot({
    required this.phase,
    required this.label,
    required this.days,
    required this.remaining,
    this.dayOfRange,
    this.rangeDays,
  });

  final CountdownPhase phase;

  /// "In 12 days", "Tomorrow", "Day 2 of 5", "In 4h 10m", "3 days ago"…
  final String label;

  /// Calendar days to the start (negative once it has passed). For a moment,
  /// whole days of [remaining].
  final int days;

  /// Exact time left (negative once passed). For a date, to its midnight.
  final Duration remaining;

  /// Within a range: which day it is (1-based) and how many days it spans.
  final int? dayOfRange;
  final int? rangeDays;
}

abstract final class Countdown {
  /// A whole-day date, or a range from [start] to [end] inclusive.
  static CountdownSnapshot toDate({required DateTime start, DateTime? end, required DateTime now}) {
    final range = end != null && calendarDaysBetween(start, end) > 0;
    final toStart = calendarDaysBetween(now, start);
    final remaining = DateTime(start.year, start.month, start.day).difference(now);

    if (toStart > 0) {
      return CountdownSnapshot(
        phase: CountdownPhase.upcoming,
        label: toStart == 1 ? 'Tomorrow' : 'In $toStart days',
        days: toStart,
        remaining: remaining,
      );
    }
    if (!range) {
      final ago = -toStart;
      return CountdownSnapshot(
        phase: ago == 0 ? CountdownPhase.current : CountdownPhase.past,
        label: switch (ago) { 0 => 'Today', 1 => 'Yesterday', _ => '$ago days ago' },
        days: toStart,
        remaining: remaining,
      );
    }
    final span = calendarDaysBetween(start, end) + 1;
    final pastEnd = calendarDaysBetween(end, now);
    if (pastEnd <= 0) {
      final day = -toStart + 1;
      return CountdownSnapshot(
        phase: CountdownPhase.current,
        label: 'Day $day of $span',
        days: toStart,
        remaining: remaining,
        dayOfRange: day,
        rangeDays: span,
      );
    }
    return CountdownSnapshot(
      phase: CountdownPhase.past,
      label: pastEnd == 1 ? 'Ended yesterday' : 'Ended $pastEnd days ago',
      days: toStart,
      remaining: remaining,
      rangeDays: span,
    );
  }

  /// An exact moment: "In 2d 4h", "In 10m 5s", "Now", "3h 2m ago".
  static CountdownSnapshot toMoment({required DateTime target, required DateTime now}) {
    final remaining = target.difference(now);
    final left = remaining.abs();
    if (left < const Duration(seconds: 1)) {
      return CountdownSnapshot(phase: CountdownPhase.current, label: 'Now', days: 0, remaining: remaining);
    }
    final parts = _twoLargestUnits(left);
    final future = !remaining.isNegative;
    return CountdownSnapshot(
      phase: future ? CountdownPhase.upcoming : CountdownPhase.past,
      label: future ? 'In $parts' : '$parts ago',
      days: remaining.inDays,
      remaining: remaining,
    );
  }

  static String _twoLargestUnits(Duration d) {
    final units = [
      (d.inDays, 'd'),
      (d.inHours % 24, 'h'),
      (d.inMinutes % 60, 'm'),
      (d.inSeconds % 60, 's'),
    ];
    final first = units.indexWhere((u) => u.$1 > 0);
    final shown = [
      units[first],
      if (first + 1 < units.length && units[first + 1].$1 > 0) units[first + 1],
    ];
    return shown.map((u) => '${u.$1}${u.$2}').join(' ');
  }
}
