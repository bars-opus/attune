import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/create_planning_goal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGateway implements PlanningRpcGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> handlers;
  _FakeGateway(this.handlers);

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    final handler = handlers[function];
    if (handler == null) throw StateError('No fake handler for $function');
    return handler(params);
  }
}

// planningGoalsProvider (invalidated via .notifier.refresh() after a
// successful save) and planningChangeSignalProvider both synchronously
// reach Supabase.instance.client — there is no Supabase.initialize() in
// this test host (see planning_notes_screen_test.dart's identical
// note), so the signal provider must be overridden to a harmless empty
// stream rather than left to hit the real ambient client.
Widget _wrap(Widget child, PlanningRepository repository) => ProviderScope(
  overrides: [
    planningRepositoryProvider.overrideWithValue(repository),
    planningChangeSignalProvider.overrideWith(
      (ref, relationshipId) => const Stream<void>.empty(),
    ),
  ],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('an unsaved draft survives a failed save, and offers retry', (
    tester,
  ) async {
    var attempts = 0;
    final gateway = _FakeGateway({
      'create_planning_goal': (params) {
        attempts++;
        throw StateError('network down');
      },
    });
    await tester.pumpWidget(_wrap(
      const CreatePlanningGoalScreen(relationshipId: 'r1'),
      PlanningRepository(gateway),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Plan the wedding');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Book a venue');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('Plan the wedding'), findsOneWidget);
    expect(find.text('Book a venue'), findsOneWidget);
    expect(find.textContaining('Could not save the goal'), findsOneWidget);

    final saveButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Save'),
    );
    expect(saveButton.onPressed, isNotNull);
  });

  testWidgets(
    'an unauthorized save failure fails closed: no retry is offered',
    (tester) async {
      var attempts = 0;
      final gateway = _FakeGateway({
        'create_planning_goal': (params) {
          attempts++;
          // 42501 is Postgres' "insufficient_privilege" SQLSTATE, which
          // PlanningRepository._mapError maps to PlanningUnauthorizedError
          // — the relationship-ended/not-a-member case. Per that error's
          // own doc comment, the UI "must fail closed... never retry
          // automatically".
          throw PostgrestException(message: 'permission denied', code: '42501');
        },
      });
      await tester.pumpWidget(_wrap(
        const CreatePlanningGoalScreen(relationshipId: 'r1'),
        PlanningRepository(gateway),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Plan the wedding');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'Book a venue');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(attempts, 1);
      // The draft text is preserved either way...
      expect(find.text('Plan the wedding'), findsOneWidget);
      expect(find.text('Book a venue'), findsOneWidget);
      // ...but unlike the transient/network case, this is NOT phrased
      // as retryable, and Save itself must be disabled so tapping it
      // again cannot even fire a second doomed attempt.
      expect(find.textContaining('Could not save the goal'), findsNothing);
      expect(find.textContaining('no longer available'), findsOneWidget);

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);

      // Confirm it's truly inert: tapping again must not re-invoke the
      // RPC (still exactly one attempt). onPressed is null so this tap
      // is a no-op, but assert the invariant explicitly anyway.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
    },
  );

  testWidgets(
    'tapping "Add another task" reveals a new task field, and Save '
    'creates the goal via create_planning_goal then adds every extra '
    'task via add_planning_goal_task',
    (tester) async {
      final createParamsSeen = <Map<String, dynamic>?>[];
      final addTaskParamsSeen = <Map<String, dynamic>?>[];
      final gateway = _FakeGateway({
        'create_planning_goal': (params) {
          createParamsSeen.add(params);
          return {
            'id': params!['p_goal_id'],
            'title': params['p_goal_title'],
            'note': null,
            'completed_at': null,
            'updated_at': DateTime.now().toIso8601String(),
          };
        },
        'add_planning_goal_task': (params) {
          addTaskParamsSeen.add(params);
          return {
            'id': params!['p_task_id'],
            'relationship_id': 'r1',
            'item_kind': 'task',
            'parent_goal_id': params['p_goal_id'],
            'title': params['p_title'],
            'note': params['p_note'],
            'assigned_to': null,
            'due_date': params['p_due_date'],
            'completed_at': null,
            'deleted_at': null,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
        },
      });

      await tester.pumpWidget(_wrap(
        const CreatePlanningGoalScreen(relationshipId: 'r1'),
        PlanningRepository(gateway),
      ));
      await tester.pumpAndSettle();

      // Only the goal title + first task fields exist before tapping
      // "Add another task".
      expect(find.byType(TextField), findsNWidgets(2));

      await tester.tap(find.text('Add another task'));
      await tester.pump();
      await tester.tap(find.text('Add another task'));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(4));

      await tester.enterText(find.byType(TextField).at(0), 'Plan the wedding');
      await tester.enterText(find.byType(TextField).at(1), 'Book a venue');
      await tester.enterText(find.byType(TextField).at(2), 'Hire a caterer');
      await tester.enterText(find.byType(TextField).at(3), 'Send invitations');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(createParamsSeen, hasLength(1));
      expect(createParamsSeen.single!['p_first_task_title'], 'Book a venue');

      // Both extra tasks were added, via the SAME RPC and goal id an
      // already-created goal's own "Add task" affordance uses — not a
      // separate/duplicated code path.
      expect(addTaskParamsSeen, hasLength(2));
      expect(
        addTaskParamsSeen.map((p) => p!['p_title']),
        ['Hire a caterer', 'Send invitations'],
      );
      final goalId = createParamsSeen.single!['p_goal_id'];
      for (final params in addTaskParamsSeen) {
        expect(params!['p_goal_id'], goalId);
      }
    },
  );

  testWidgets(
    'removing an extra task field before Save never sends that task',
    (tester) async {
      final addTaskParamsSeen = <Map<String, dynamic>?>[];
      final gateway = _FakeGateway({
        'create_planning_goal': (params) => {
              'id': params!['p_goal_id'],
              'title': params['p_goal_title'],
              'note': null,
              'completed_at': null,
              'updated_at': DateTime.now().toIso8601String(),
            },
        'add_planning_goal_task': (params) {
          addTaskParamsSeen.add(params);
          return {
            'id': params!['p_task_id'],
            'relationship_id': 'r1',
            'item_kind': 'task',
            'parent_goal_id': params['p_goal_id'],
            'title': params['p_title'],
            'note': null,
            'assigned_to': null,
            'due_date': null,
            'completed_at': null,
            'deleted_at': null,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
        },
      });

      await tester.pumpWidget(_wrap(
        const CreatePlanningGoalScreen(relationshipId: 'r1'),
        PlanningRepository(gateway),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add another task'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Plan the wedding');
      await tester.enterText(find.byType(TextField).at(1), 'Book a venue');
      await tester.enterText(find.byType(TextField).at(2), 'A task to remove');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(addTaskParamsSeen, isEmpty);
    },
  );

  testWidgets(
    'a blank extra task field is silently dropped, not sent or blocking '
    'Save',
    (tester) async {
      final addTaskParamsSeen = <Map<String, dynamic>?>[];
      final gateway = _FakeGateway({
        'create_planning_goal': (params) => {
              'id': params!['p_goal_id'],
              'title': params['p_goal_title'],
              'note': null,
              'completed_at': null,
              'updated_at': DateTime.now().toIso8601String(),
            },
        'add_planning_goal_task': (params) {
          addTaskParamsSeen.add(params);
          return {
            'id': params!['p_task_id'],
            'relationship_id': 'r1',
            'item_kind': 'task',
            'parent_goal_id': params['p_goal_id'],
            'title': params['p_title'],
            'note': null,
            'assigned_to': null,
            'due_date': null,
            'completed_at': null,
            'deleted_at': null,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
        },
      });

      await tester.pumpWidget(_wrap(
        const CreatePlanningGoalScreen(relationshipId: 'r1'),
        PlanningRepository(gateway),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add another task'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Plan the wedding');
      await tester.enterText(find.byType(TextField).at(1), 'Book a venue');
      // Leave the second task field blank.
      await tester.pump();

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save'),
      );
      expect(saveButton.onPressed, isNotNull);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(addTaskParamsSeen, isEmpty);
    },
  );

  testWidgets(
    'if an extra task fails to save, the goal (already created) and '
    'any tasks added before the failure are kept, and the Goals list '
    'is refreshed rather than left stale',
    (tester) async {
      var refreshed = false;
      final gateway = _FakeGateway({
        'create_planning_goal': (params) => {
              'id': params!['p_goal_id'],
              'title': params['p_goal_title'],
              'note': null,
              'completed_at': null,
              'updated_at': DateTime.now().toIso8601String(),
            },
        'add_planning_goal_task': (params) {
          throw StateError('network down');
        },
        'list_planning_goals': (params) {
          refreshed = true;
          return <dynamic>[];
        },
      });

      await tester.pumpWidget(_wrap(
        const CreatePlanningGoalScreen(relationshipId: 'r1'),
        PlanningRepository(gateway),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add another task'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Plan the wedding');
      await tester.enterText(find.byType(TextField).at(1), 'Book a venue');
      await tester.enterText(find.byType(TextField).at(2), 'Hire a caterer');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The screen stays open (a save-in-progress failure, not a
      // silent success) and the Goals list was refreshed so it picks
      // up the goal that DID get created server-side.
      expect(find.byType(CreatePlanningGoalScreen), findsOneWidget);
      expect(refreshed, isTrue);
      expect(find.textContaining('Could not save the goal'), findsOneWidget);
    },
  );
}
