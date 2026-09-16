// lib/features/planning/data/repositories/planning_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'planning_error.dart';
import '../models/planning_goal_model.dart';
import '../models/planning_task_model.dart';
import '../models/planning_event_model.dart';
import '../models/planning_note_model.dart';
import '../models/planning_calendar_entry_model.dart';
import '../models/planning_summary_model.dart';

/// The seam this repository calls through, so tests can fake it
/// instead of the real, heavily-generic SupabaseClient RPC builder —
/// the same reasoning story_repository.dart's own gateway interface
/// gives for doing this rather than mocking SupabaseClient directly.
abstract class PlanningRpcGateway {
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params});
}

class SupabasePlanningRpcGateway implements PlanningRpcGateway {
  final SupabaseClient _supabase;
  const SupabasePlanningRpcGateway(this._supabase);

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    return _supabase.rpc(function, params: params);
  }
}

class PlanningRepository {
  final PlanningRpcGateway _gateway;
  const PlanningRepository(this._gateway);

  Future<T> _call<T>(
    String function, {
    Map<String, dynamic>? params,
    required T Function(dynamic result) onResult,
  }) async {
    try {
      final result = await _gateway.rpc(function, params: params);
      return onResult(result);
    } catch (error) {
      throw _mapError(error);
    }
  }

  PlanningError _mapError(Object error) {
    if (error is PostgrestException) {
      // 42501 is Postgres' own "insufficient_privilege" SQLSTATE,
      // raised when RLS or a REVOKE refuses the call outright.
      if (error.code == '42501') return const PlanningUnauthorizedError();
      // Every RAISE EXCEPTION in Plan A's RPCs surfaces as SQLSTATE
      // P0001 (plpgsql's own generic "raised_exception" code) with the
      // RPC's own message text — that text is what distinguishes
      // "Planning unavailable" / "Not authenticated" (treat as
      // unauthorized: the RPCs use these exact generic messages
      // specifically to avoid forming an existence oracle) from every
      // other validation message (show it directly).
      if (error.code == 'P0001') {
        if (error.message == 'Planning unavailable' ||
            error.message == 'Not authenticated') {
          return const PlanningUnauthorizedError();
        }
        return PlanningValidationError(error.message);
      }
      return PlanningNetworkError(error);
    }
    return PlanningNetworkError(error);
  }

  // --- Tasks and Goals ---

  Future<PlanningTaskModel> createTask({
    required String id,
    required String relationshipId,
    required String title,
    String? note,
    String? assignedTo,
    DateTime? dueDate,
  }) => _call(
    'create_planning_task',
    params: {
      'p_id': id,
      'p_relationship_id': relationshipId,
      'p_title': title,
      'p_note': note,
      'p_assigned_to': assignedTo,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    },
    onResult: (r) =>
        PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<PlanningGoalModel> createGoal({
    required String goalId,
    required String firstTaskId,
    required String relationshipId,
    required String goalTitle,
    required String firstTaskTitle,
  }) => _call(
    'create_planning_goal',
    params: {
      'p_goal_id': goalId,
      'p_first_task_id': firstTaskId,
      'p_relationship_id': relationshipId,
      'p_goal_title': goalTitle,
      'p_first_task_title': firstTaskTitle,
    },
    onResult: (r) {
      final row = Map<String, dynamic>.from(r as Map);
      return PlanningGoalModel(
        id: row['id'] as String,
        title: row['title'] as String,
        note: row['note'] as String?,
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.parse(row['completed_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        // A freshly created goal always has exactly one child, not
        // complete — the RPC's return row has no child_count column
        // (it returns the raw planning_items row, not the
        // list_planning_goals aggregate shape), so this is filled in
        // from what create_planning_goal's own invariant guarantees
        // rather than from a column that is not there.
        childCount: 1,
        completedChildCount: 0,
      );
    },
  );

  Future<PlanningTaskModel> addGoalTask({
    required String taskId,
    required String goalId,
    required String title,
    String? note,
    DateTime? dueDate,
  }) => _call(
    'add_planning_goal_task',
    params: {
      'p_task_id': taskId,
      'p_goal_id': goalId,
      'p_title': title,
      'p_note': note,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    },
    onResult: (r) =>
        PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  /// Fields not accepted here: `itemKind`, `parentGoalId`. Both are
  /// immutable once a `planning_items` row exists (Plan A) — there is
  /// no RPC to change them and this method deliberately has no
  /// parameter for either, so a caller cannot even attempt it client-
  /// side.
  Future<PlanningTaskModel> updateItem({
    required String id,
    String? title,
    String? note,
    String? assignedTo,
    DateTime? dueDate,
  }) => _call(
    'update_planning_item',
    params: {
      'p_id': id,
      'p_title': title,
      'p_note': note,
      'p_assigned_to': assignedTo,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    },
    onResult: (r) =>
        PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<PlanningTaskModel> setTaskCompletion({
    required String taskId,
    required bool isComplete,
  }) => _call(
    'set_planning_task_completion',
    params: {'p_task_id': taskId, 'p_is_complete': isComplete},
    onResult: (r) =>
        PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<bool> deleteItem({required String id}) => _call(
    'delete_planning_item',
    params: {'p_id': id},
    onResult: (r) => r as bool,
  );

  // --- Events and links ---

  Future<PlanningEventModel> upsertEvent({
    required String id,
    required String relationshipId,
    required String title,
    String? note,
    required DateTime eventDate,
  }) => _call(
    'upsert_planning_event',
    params: {
      'p_id': id,
      'p_relationship_id': relationshipId,
      'p_title': title,
      'p_note': note,
      'p_event_date': eventDate.toIso8601String().split('T').first,
    },
    onResult: (r) =>
        PlanningEventModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<bool> deleteEvent({required String id}) => _call(
    'delete_planning_event',
    params: {'p_id': id},
    onResult: (r) => r as bool,
  );

  Future<bool> linkEventTask({
    required String eventId,
    required String itemId,
  }) => _call(
    'link_planning_event_task',
    params: {'p_event_id': eventId, 'p_item_id': itemId},
    onResult: (r) => r as bool,
  );

  Future<bool> unlinkEventTask({
    required String eventId,
    required String itemId,
  }) => _call(
    'unlink_planning_event_task',
    params: {'p_event_id': eventId, 'p_item_id': itemId},
    onResult: (r) => r as bool,
  );

  // --- Notes ---

  Future<PlanningNoteModel> upsertNote({
    required String id,
    required String relationshipId,
    required String title,
    required String body,
  }) => _call(
    'upsert_planning_note',
    params: {
      'p_id': id,
      'p_relationship_id': relationshipId,
      'p_title': title,
      'p_body': body,
    },
    onResult: (r) =>
        PlanningNoteModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<bool> deleteNote({required String id}) => _call(
    'delete_planning_note',
    params: {'p_id': id},
    onResult: (r) => r as bool,
  );

  // --- Reads ---

  Future<List<PlanningGoalModel>> listGoals({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 30,
  }) => _call(
    'list_planning_goals',
    params: {
      'p_relationship_id': relationshipId,
      'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map(
          (row) =>
              PlanningGoalModel.fromRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false),
  );

  Future<List<PlanningTaskModel>> listGoalTasks({
    required String goalId,
    DateTime? afterCreatedAt,
    String? afterId,
    int limit = 50,
  }) => _call(
    'list_planning_goal_tasks',
    params: {
      'p_goal_id': goalId,
      'p_after_created_at': afterCreatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map(
          (row) =>
              PlanningTaskModel.fromRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false),
  );

  /// `list_planning_tasks`'s ORDER BY is mixed-direction —
  /// `(completed_at IS NOT NULL) ASC, due_date ASC, updated_at DESC,
  /// id DESC` — and its cursor predicate (the OR-chain in
  /// `20260941060000_planning_read_rpcs.sql`) advances by re-reading
  /// ALL FOUR of the last row's own key values via `p_after_id`, not
  /// by the client supplying them: the SQL does
  /// `SELECT completed_at IS NOT NULL ... WHERE id = p_after_id` for
  /// each branch. So the only cursor state this method needs from the
  /// caller is [afterUpdatedAt] and [afterId] — `p_after_due_date` is
  /// accepted for forward-compatibility with the RPC signature but is
  /// deliberately unused by the SQL's own cursor predicate today; do
  /// not remove it without re-reading that migration first.
  Future<List<PlanningTaskModel>> listTasks({
    required String relationshipId,
    DateTime? afterDueDate,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 50,
  }) => _call(
    'list_planning_tasks',
    params: {
      'p_relationship_id': relationshipId,
      'p_after_due_date': afterDueDate?.toIso8601String().split('T').first,
      'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map(
          (row) =>
              PlanningTaskModel.fromRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false),
  );

  Future<List<PlanningEventModel>> listEvents({
    required String relationshipId,
    required DateTime today,
    required bool upcoming,
    DateTime? afterDate,
    String? afterId,
    int limit = 50,
  }) => _call(
    'list_planning_events',
    params: {
      'p_relationship_id': relationshipId,
      'p_today': today.toIso8601String().split('T').first,
      'p_upcoming': upcoming,
      'p_after_date': afterDate?.toIso8601String().split('T').first,
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map(
          (row) =>
              PlanningEventModel.fromRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false),
  );

  Future<List<PlanningNoteModel>> listNotes({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 30,
  }) => _call(
    'list_planning_notes',
    params: {
      'p_relationship_id': relationshipId,
      'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map(
          (row) =>
              PlanningNoteModel.fromRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false),
  );

  Future<List<PlanningCalendarEntryModel>> listCalendarEntries({
    required String relationshipId,
    required DateTime startDate,
    required DateTime endDate,
  }) => _call(
    'list_planning_calendar_entries',
    params: {
      'p_relationship_id': relationshipId,
      'p_start_date': startDate.toIso8601String().split('T').first,
      'p_end_date': endDate.toIso8601String().split('T').first,
    },
    onResult: (r) => (r as List)
        .map(
          (row) => PlanningCalendarEntryModel.fromRow(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false),
  );

  Future<PlanningSummaryModel?> getSummary({
    required String relationshipId,
    required DateTime today,
  }) => _call(
    'get_planning_summary',
    params: {
      'p_relationship_id': relationshipId,
      'p_today': today.toIso8601String().split('T').first,
    },
    onResult: (r) {
      final rows = r as List;
      if (rows.isEmpty) return null;
      return PlanningSummaryModel.fromRow(
        Map<String, dynamic>.from(rows.first as Map),
      );
    },
  );
}
