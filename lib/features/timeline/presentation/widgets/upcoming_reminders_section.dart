import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The last valid day of [month] in [year] — Dart's DateTime constructor
/// silently rolls an out-of-range day into the next month instead of
/// clamping (e.g. DateTime(2026, 2, 29) becomes March 1st, 2026, since 2026
/// isn't a leap year), which would otherwise make a Feb 29th reminder fire
/// a day late and on the wrong month in every non-leap year. Mirrors
/// REMINDERS.md's server-side generator, which explicitly specifies firing
/// on Feb 28 in non-leap years rather than skipping the reminder.
int _lastDayOfMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

/// The reminder's next real-world occurrence — itself for a one-off, or
/// this year's (or next year's, if this year's has already passed)
/// month/day for a yearly-recurring reminder, with the day clamped to the
/// target month's actual length. Ported from
/// CouplesCalendarScreen._nextOccurrence.
DateTime nextOccurrence(ReminderModel reminder, {DateTime? now}) {
  if (!reminder.isRecurring) return reminder.remindAt;
  final today = now ?? DateTime.now();

  DateTime occurrenceInYear(int year) {
    final month = reminder.remindAt.month;
    final day = reminder.remindAt.day.clamp(1, _lastDayOfMonth(year, month));
    return DateTime(year, month, day);
  }

  var next = occurrenceInYear(today.year);
  if (next.isBefore(DateTime(today.year, today.month, today.day))) {
    next = occurrenceInYear(today.year + 1);
  }
  return next;
}

/// Reminders whose next occurrence falls within the next 3 months, i.e.
/// what belongs in the Upcoming section — a one-off reminder from the past
/// is excluded entirely rather than sorting to the top with a negative
/// countdown, and anything further out than 3 months is left off so the
/// section stays a near-term glance rather than a full future log.
List<ReminderModel> upcomingReminders(
  List<ReminderModel> reminders, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final horizon = DateTime(today.year, today.month + 3, today.day);
  return reminders.where((reminder) {
    final occurrence = nextOccurrence(reminder, now: now);
    return !occurrence.isBefore(startOfToday) && occurrence.isBefore(horizon);
  }).toList();
}

String _countdownLabel(DateTime occurrence, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(occurrence.year, occurrence.month, occurrence.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}

/// Timeline event ids that already have a reminder representing them —
/// a reminder created via AddEditReminderScreen's "Add to Timeline too?"
/// flow produces both a ReminderModel and a linked TimelineEventModel for
/// the same real-world date. Callers exclude these ids from the Timeline
/// section's past-moments log so the event isn't shown twice while its
/// reminder is still upcoming/active. Ported from
/// CalendarMonthView's linkedTimelineEventIds computation.
Set<String> linkedTimelineEventIds(List<ReminderModel> reminders) {
  return reminders
      .map((reminder) => reminder.linkedTimelineEventId)
      .whereType<String>()
      .toSet();
}

/// The "what's coming up" half of the merged Timeline screen — a sorted
/// list of upcoming reminders (soonest first), rendered above the existing
/// past-moments log. Ported from CouplesCalendarScreen._buildList's
/// reminder rows.
class UpcomingRemindersSection extends StatelessWidget {
  const UpcomingRemindersSection({
    super.key,
    required this.reminders,
    required this.onReminderTap,
  });

  final List<ReminderModel> reminders;
  final void Function(ReminderModel reminder)? onReminderTap;

  @override
  Widget build(BuildContext context) {
    final filtered = upcomingReminders(reminders);
    if (filtered.isEmpty) return const SizedBox.shrink();

    final sorted = [...filtered]
      ..sort(
        (a, b) => nextOccurrence(a).compareTo(nextOccurrence(b)),
      );

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final reminder = sorted[index];
        return CardInkWell(
          child: InfoRowWidget(
            subtitle: _countdownLabel(nextOccurrence(reminder)),
            title: reminder.title,
            icon:
                reminder.isRecurring
                    ? FontAwesomeIcons.repeat
                    : Icons.event_outlined,
            iconSize: 20.h,
            onTap:
                onReminderTap == null ? null : () => onReminderTap!(reminder),
            disableTrailing: true,
            showAvatar: false,
            showDivider: false,
            showTrailingArrow: false,
          ),
        );
      },
    );
  }
}
