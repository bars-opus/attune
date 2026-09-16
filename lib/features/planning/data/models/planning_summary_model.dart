// lib/features/planning/data/models/planning_summary_model.dart

/// One row from `get_planning_summary` — the single item the
/// conversations-screen entry row shows (spec §6.1). `kind` is one of
/// the seven values that RPC can return: overdue_task, upcoming_task,
/// upcoming_event, goal, task, event, note. Kept as a raw string rather
/// than an enum here because the entry row's display logic (§6.1's
/// priority list) branches on it directly and a seventh value added to
/// the RPC later should not require a matching Dart enum edit to avoid
/// a compile error — an unrecognized kind falls back to a generic
/// label rather than crashing.
class PlanningSummaryModel {
  final String kind;
  final String id;
  final String title;
  final DateTime? contextDate;

  const PlanningSummaryModel({
    required this.kind,
    required this.id,
    required this.title,
    this.contextDate,
  });

  factory PlanningSummaryModel.fromRow(Map<String, dynamic> row) {
    return PlanningSummaryModel(
      kind: row['kind'] as String,
      id: row['id'] as String,
      title: row['title'] as String,
      // context_date is a Postgres `date` (a task's due_date or an
      // event's event_date) — parse as UTC midnight explicitly, same
      // reasoning as the other date-only fields in this feature.
      contextDate: row['context_date'] == null
          ? null
          : _parseDateOnlyUtc(row['context_date'] as String),
    );
  }
}

DateTime _parseDateOnlyUtc(String value) =>
    DateTime.parse(value.contains('T') ? value : '${value}T00:00:00Z');
