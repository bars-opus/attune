// lib/features/planning/data/models/planning_task_model.dart

/// A Task row from `planning_items` (`item_kind = 'task'`). Rejects a
/// Goal row rather than silently misrepresenting it — this model's
/// entire contract is "this is a Task," so a caller that accidentally
/// hands it a Goal row has a bug worth failing loudly on rather than
/// producing a Task with nonsensical isTopLevel/assignedTo semantics.
///
/// `itemKind` and `parentGoalId` are immutable in the backend (Plan A):
/// once a row is created, `item_kind` never changes and `parent_goal_id`
/// is set once at creation and never reparented. There is deliberately
/// no client-side mutator for either — every field this model exposes
/// for editing (title/note/assignedTo/dueDate/completedAt) is exactly
/// the set `update_planning_item`/`set_planning_task_completion` can
/// change; parentage and kind are read-only for the lifetime of this
/// model.
class PlanningTaskModel {
  final String id;
  final String relationshipId;
  final String? createdBy;
  final String? parentGoalId;
  final String title;
  final String? note;
  final String? assignedTo;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlanningTaskModel({
    required this.id,
    required this.relationshipId,
    this.createdBy,
    this.parentGoalId,
    required this.title,
    this.note,
    this.assignedTo,
    this.dueDate,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTopLevel => parentGoalId == null;
  bool get isComplete => completedAt != null;

  factory PlanningTaskModel.fromRow(Map<String, dynamic> row) {
    if (row['item_kind'] != 'task') {
      throw ArgumentError(
        'PlanningTaskModel.fromRow received item_kind="${row['item_kind']}", expected "task"',
      );
    }
    return PlanningTaskModel(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      createdBy: row['created_by'] as String?,
      parentGoalId: row['parent_goal_id'] as String?,
      title: row['title'] as String,
      note: row['note'] as String?,
      assignedTo: row['assigned_to'] as String?,
      // due_date is a Postgres `date` column with no time zone of its
      // own; DateTime.parse on a bare "YYYY-MM-DD" string parses it as
      // LOCAL midnight, not UTC midnight, which would silently shift
      // the date by a day for any client not in UTC. Force UTC
      // explicitly rather than relying on the runner's local zone.
      dueDate: row['due_date'] == null
          ? null
          : _parseDateOnlyUtc(row['due_date'] as String),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

/// Parses a bare `date` string (no time-of-day, no offset) as UTC
/// midnight rather than local midnight — see the note at [dueDate]'s
/// assignment above.
DateTime _parseDateOnlyUtc(String value) =>
    DateTime.parse(value.contains('T') ? value : '${value}T00:00:00Z');
