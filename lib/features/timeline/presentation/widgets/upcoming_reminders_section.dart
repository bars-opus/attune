import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The reminder's next real-world occurrence — itself for a one-off, or
/// this year's (or next year's, if this year's has already passed)
/// month/day for a yearly-recurring reminder. Ported from
/// CouplesCalendarScreen._nextOccurrence.
DateTime nextOccurrence(ReminderModel reminder, {DateTime? now}) {
  if (!reminder.isRecurring) return reminder.remindAt;
  final today = now ?? DateTime.now();
  var next = DateTime(today.year, reminder.remindAt.month, reminder.remindAt.day);
  if (next.isBefore(DateTime(today.year, today.month, today.day))) {
    next = DateTime(today.year + 1, reminder.remindAt.month, reminder.remindAt.day);
  }
  return next;
}

/// Reminders whose next occurrence has not yet passed, i.e. what belongs in
/// the Upcoming section — a one-off reminder from the past is excluded
/// entirely rather than sorting to the top with a negative countdown.
List<ReminderModel> upcomingReminders(
  List<ReminderModel> reminders, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  return reminders
      .where(
        (reminder) => !nextOccurrence(reminder, now: now).isBefore(startOfToday),
      )
      .toList();
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
