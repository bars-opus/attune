// lib/features/planning/data/models/planning_calendar_entry_model.dart

enum PlanningCalendarEntryKind { task, event }

/// One row from `list_planning_calendar_entries` — a Task's due date OR
/// an Event's date, composed by the Timeline screen alongside timeline
/// events and reminders (spec §7). Deliberately its own type, never
/// coerced into `TimelineEventModel` (spec §7's explicit rule).
class PlanningCalendarEntryModel {
  final PlanningCalendarEntryKind kind;
  final String id;
  final DateTime date;
  final String title;
  final bool isComplete;

  const PlanningCalendarEntryModel({
    required this.kind,
    required this.id,
    required this.date,
    required this.title,
    required this.isComplete,
  });

  factory PlanningCalendarEntryModel.fromRow(Map<String, dynamic> row) {
    return PlanningCalendarEntryModel(
      kind: row['entry_kind'] == 'task'
          ? PlanningCalendarEntryKind.task
          : PlanningCalendarEntryKind.event,
      id: row['entry_id'] as String,
      // entry_date is a Postgres `date` (a task's due_date or an
      // event's event_date, both dateless-of-timezone) — parse as UTC
      // midnight explicitly, same reasoning as the other date-only
      // fields in this feature.
      date: _parseDateOnlyUtc(row['entry_date'] as String),
      title: row['title'] as String,
      isComplete: row['is_complete'] as bool,
    );
  }
}

DateTime _parseDateOnlyUtc(String value) =>
    DateTime.parse(value.contains('T') ? value : '${value}T00:00:00Z');
