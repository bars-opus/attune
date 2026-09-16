import 'package:attune/features/planning/data/models/planning_goal_model.dart';
import 'package:attune/features/planning/data/models/planning_task_model.dart';
import 'package:attune/features/planning/data/models/planning_event_model.dart';
import 'package:attune/features/planning/data/models/planning_note_model.dart';
import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/planning/data/models/planning_summary_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanningGoalModel', () {
    test('parses list_planning_goals row shape, including derived counts', () {
      final goal = PlanningGoalModel.fromRow({
        'id': 'g1',
        'title': 'Save for the trip',
        'note': null,
        'completed_at': null,
        'updated_at': '2026-09-14T10:00:00Z',
        'child_count': 2,
        'completed_child_count': 1,
      });
      expect(goal.id, 'g1');
      expect(goal.title, 'Save for the trip');
      expect(goal.isComplete, isFalse);
      expect(goal.childCount, 2);
      expect(goal.completedChildCount, 1);
      // Progress is derived from the row's own counts, never recomputed
      // client-side from a fetched child list that may not be loaded —
      // the Goals list screen shows progress WITHOUT expanding a goal.
      expect(goal.progressFraction, 0.5);
    });

    test('a goal with zero children reports zero progress, not NaN', () {
      final goal = PlanningGoalModel.fromRow({
        'id': 'g2', 'title': 'x', 'note': null, 'completed_at': null,
        'updated_at': '2026-09-14T10:00:00Z',
        'child_count': 0, 'completed_child_count': 0,
      });
      expect(goal.progressFraction, 0.0);
    });
  });

  group('PlanningTaskModel', () {
    test('parses planning_items row shape for a top-level task', () {
      final task = PlanningTaskModel.fromRow({
        'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
        'item_kind': 'task', 'parent_goal_id': null,
        'title': 'Book the venue', 'note': null,
        'assigned_to': null, 'due_date': '2026-12-01',
        'completed_at': null, 'celebrated_at': null,
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(task.id, 't1');
      expect(task.isTopLevel, isTrue);
      expect(task.isComplete, isFalse);
      expect(task.dueDate, DateTime.utc(2026, 12, 1));
    });

    test('a goal child task reports isTopLevel false', () {
      final task = PlanningTaskModel.fromRow({
        'id': 't2', 'relationship_id': 'r1', 'created_by': 'u1',
        'item_kind': 'task', 'parent_goal_id': 'g1',
        'title': 'Open account', 'note': null,
        'assigned_to': null, 'due_date': null,
        'completed_at': null, 'celebrated_at': null,
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(task.isTopLevel, isFalse);
      expect(task.parentGoalId, 'g1');
    });

    test('item_kind = goal is rejected — this model is Tasks only', () {
      expect(
        () => PlanningTaskModel.fromRow({
          'id': 't3', 'relationship_id': 'r1', 'created_by': 'u1',
          'item_kind': 'goal', 'parent_goal_id': null,
          'title': 'not a task', 'note': null,
          'assigned_to': null, 'due_date': null,
          'completed_at': null, 'celebrated_at': null,
          'created_at': '2026-09-14T09:00:00Z',
          'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PlanningEventModel', () {
    test('parses planning_events row shape', () {
      final event = PlanningEventModel.fromRow({
        'id': 'e1', 'relationship_id': 'r1', 'created_by': 'u1',
        'title': "Sarah's birthday dinner", 'note': 'Try the Italian place',
        'event_date': '2026-12-25',
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(event.eventDate, DateTime.utc(2026, 12, 25));
      expect(event.note, 'Try the Italian place');
    });
  });

  group('PlanningNoteModel', () {
    test('parses planning_notes row shape', () {
      final note = PlanningNoteModel.fromRow({
        'id': 'n1', 'relationship_id': 'r1', 'created_by': 'u1',
        'title': 'Restaurants to try', 'body': 'Thai place on 5th',
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(note.body, 'Thai place on 5th');
    });
  });

  group('PlanningCalendarEntryModel', () {
    test('parses a task entry and an event entry from the same RPC shape', () {
      final taskEntry = PlanningCalendarEntryModel.fromRow({
        'entry_kind': 'task', 'entry_id': 't1', 'entry_date': '2026-06-01',
        'title': 'Water the plants', 'is_complete': false,
      });
      expect(taskEntry.kind, PlanningCalendarEntryKind.task);
      expect(taskEntry.isComplete, isFalse);

      final eventEntry = PlanningCalendarEntryModel.fromRow({
        'entry_kind': 'event', 'entry_id': 'e1', 'entry_date': '2026-12-25',
        'title': "Sarah's birthday dinner", 'is_complete': false,
      });
      expect(eventEntry.kind, PlanningCalendarEntryKind.event);
    });
  });

  group('PlanningSummaryModel', () {
    test('parses each of the five summary kinds get_planning_summary can return', () {
      for (final kind in [
        'overdue_task', 'upcoming_task', 'upcoming_event', 'goal', 'task', 'event', 'note',
      ]) {
        final summary = PlanningSummaryModel.fromRow({
          'kind': kind, 'id': 'x1', 'title': 'something',
          'context_date': kind == 'goal' || kind == 'note' ? null : '2026-09-14',
        });
        expect(summary.kind, isNotNull, reason: 'kind "$kind" must parse');
      }
    });
  });
}
