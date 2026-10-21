/// Will we make it? A goal's pace: what's done since it began, at that rate,
/// against the date it's due by. Steps or amounts alike ([done] of
/// [total]); counted in whole days on the device's calendar.
sealed class PlanningPace {
  const PlanningPace();
}

/// All of it done.
class PaceReached extends PlanningPace {
  const PaceReached();
}

/// Nothing done yet, so no pace to speak of.
class PaceNotStarted extends PlanningPace {
  const PaceNotStarted();
}

/// The date has passed with some still to do.
class PaceOverdue extends PlanningPace {
  const PaceOverdue();
}

/// The date is today; [left] still to do.
class PaceDueToday extends PlanningPace {
  const PaceDueToday(this.left);
  final int left;
}

/// At this rate it's done by the date [by], but not well before.
class PaceOnTrack extends PlanningPace {
  const PaceOnTrack(this.by);
  final DateTime by;
}

/// At this rate it's done well before the date, on [finish].
class PaceAhead extends PlanningPace {
  const PaceAhead(this.finish);
  final DateTime finish;
}

/// At this rate it misses the date; [amount] a week ([perDay]: a day, with
/// under a week to go) would get there.
class PaceBehind extends PlanningPace {
  const PaceBehind(this.amount, {required this.perDay});
  final int amount;
  final bool perDay;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
int _days(DateTime from, DateTime to) => _day(to).difference(_day(from)).inDays;

/// Null when there's no pace to tell: nothing to do ([total] 0) or no date.
PlanningPace? planningGoalPace({
  required int done,
  required int total,
  required DateTime? startedOn,
  required DateTime? targetDate,
  required DateTime today,
}) {
  if (total <= 0) return null;
  if (done >= total) return const PaceReached();
  if (targetDate == null) return null;
  final daysLeft = _days(today, targetDate);
  if (daysLeft < 0) return const PaceOverdue();
  final left = total - done;
  if (daysLeft == 0) return PaceDueToday(left);
  if (done <= 0) return const PaceNotStarted();
  // A goal made today has had one day.
  final elapsed =
      startedOn == null ? 1 : _days(startedOn, today).clamp(1, 1 << 30);
  final needed = (left * elapsed / done).ceil();
  final finish = _day(today).add(Duration(days: needed));
  if (needed <= daysLeft) {
    // Well ahead: a fifth of the time left early, and at least three days.
    final margin = (daysLeft / 5).ceil() < 3 ? 3 : (daysLeft / 5).ceil();
    return needed <= daysLeft - margin
        ? PaceAhead(finish)
        : PaceOnTrack(_day(targetDate));
  }
  if (daysLeft < 7) return PaceBehind((left / daysLeft).ceil(), perDay: true);
  return PaceBehind((left / (daysLeft / 7)).ceil(), perDay: false);
}
