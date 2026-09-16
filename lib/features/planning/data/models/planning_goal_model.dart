// lib/features/planning/data/models/planning_goal_model.dart

/// A Goal, as `list_planning_goals` returns it — title plus the two
/// derived counts the RPC computes from live children (Plan A, Task 4).
/// Progress is a property of THIS row, not recomputed from a fetched
/// child list: the Goals list screen shows progress WITHOUT expanding a
/// goal (spec §6.2).
class PlanningGoalModel {
  final String id;
  final String title;
  final String? note;
  final DateTime? completedAt;
  final DateTime updatedAt;
  final int childCount;
  final int completedChildCount;

  const PlanningGoalModel({
    required this.id,
    required this.title,
    this.note,
    this.completedAt,
    required this.updatedAt,
    required this.childCount,
    required this.completedChildCount,
  });

  bool get isComplete => completedAt != null;

  /// 0.0 when childCount is 0 (a state Plan A's invariants make
  /// transient/impossible in practice, but this must never divide by
  /// zero if it is ever observed mid-mutation).
  double get progressFraction =>
      childCount == 0 ? 0.0 : completedChildCount / childCount;

  factory PlanningGoalModel.fromRow(Map<String, dynamic> row) {
    return PlanningGoalModel(
      id: row['id'] as String,
      title: row['title'] as String,
      note: row['note'] as String?,
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      childCount: (row['child_count'] as num).toInt(),
      completedChildCount: (row['completed_child_count'] as num).toInt(),
    );
  }
}
