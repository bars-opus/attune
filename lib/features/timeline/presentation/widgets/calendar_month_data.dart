import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/together/domain/together_item.dart';

/// Logged moments by calendar day (the calendar's moment avatars).
///
/// A moment logged from a reminder ("Add to your Timeline too?") is left
/// off any day where that reminder also falls, so one occasion shows once,
/// as its reminder; [remindersByDate] is the same month's reminders.
Map<DateTime, List<TimelineEventModel>> momentsByDay(
  List<TimelineEventModel> events, {
  Map<DateTime, List<ReminderModel>> remindersByDate = const {},
}) {
  final grouped = <DateTime, List<TimelineEventModel>>{};
  for (final event in events) {
    final at = event.occurredAt;
    final day = DateTime(at.year, at.month, at.day);
    final linked = remindersByDate[day]?.any(
      (r) => r.linkedTimelineEventId == event.id,
    );
    if (linked ?? false) continue;
    grouped.putIfAbsent(day, () => []).add(event);
  }
  return grouped;
}

/// Planning dates and to-dos plus Together events, by day: the calendar's
/// upcoming dots and the day sheet's Scheduled list.
Map<DateTime, List<Object>> scheduledByDay(
  List<PlanningCalendarEntry> entries,
  List<TogetherItem> together,
) {
  final grouped = <DateTime, List<Object>>{};
  for (final entry in entries) {
    final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
    grouped.putIfAbsent(date, () => []).add(entry);
  }
  for (final item in together) {
    if (item.kind != TogetherItemKind.event) continue;
    grouped.putIfAbsent(item.day, () => []).add(item);
  }
  return grouped;
}
