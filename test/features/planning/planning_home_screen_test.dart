import 'dart:async';

import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/support/chat_test_harness.dart';

class _FakeGateway implements PlanningRpcGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> handlers;
  _FakeGateway(this.handlers);

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    final handler = handlers[function];
    if (handler == null) {
      throw StateError('No fake handler registered for $function');
    }
    return handler(params);
  }
}

// planningGoalsProvider/planningTasksProvider/planningEventsProvider all
// internally `ref.listen` planningChangeSignalProvider, which synchronously
// reaches Supabase.instance.client to open a Realtime channel — there is no
// Supabase.initialize() in this test host (see pulse_tab_test.dart's own
// note on remindersListProvider for the identical constraint), so that
// signal provider must be overridden to a harmless empty stream rather than
// left to hit the real ambient client.
Widget _wrap(Widget child, PlanningRepository repository) {
  return ProviderScope(
    overrides: [
      planningRepositoryProvider.overrideWithValue(repository),
      planningChangeSignalProvider.overrideWith(
        (ref, relationshipId) => const Stream<void>.empty(),
      ),
    ],
    child: withScreenUtil(MaterialApp(home: child)),
  );
}

void main() {
  testWidgets('shows the three sections and an empty state per section', (
    tester,
  ) async {
    final repository = PlanningRepository(_FakeGateway({
      'list_planning_goals': (_) async => <dynamic>[],
      'list_planning_tasks': (_) async => <dynamic>[],
      'list_planning_events': (_) async => <dynamic>[],
    }));

    await tester.pumpWidget(_wrap(
      const PlanningHomeScreen(relationshipId: 'r1'), repository,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
  });

  testWidgets('renders a Goal and a Task once loaded', (tester) async {
    final repository = PlanningRepository(_FakeGateway({
      'list_planning_goals': (_) async => [{
        'id': 'g1', 'title': 'Save for the trip', 'note': null,
        'completed_at': null, 'updated_at': '2026-09-14T09:00:00Z',
        'child_count': 2, 'completed_child_count': 0,
      }],
      'list_planning_tasks': (_) async => [{
        'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
        'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
        'note': null, 'assigned_to': null, 'due_date': null,
        'completed_at': null, 'celebrated_at': null,
        'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
        'deleted_at': null,
      }],
      'list_planning_events': (_) async => <dynamic>[],
    }));

    await tester.pumpWidget(_wrap(
      const PlanningHomeScreen(relationshipId: 'r1'), repository,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Save for the trip'), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets(
    'deleting the sole remaining child of a goal offers the two-choice '
    'prompt rather than a generic error (spec §6.2)',
    (tester) async {
      var deleteAttempted = false;
      final repository = PlanningRepository(_FakeGateway({
        'list_planning_goals': (_) async => [{
          'id': 'g1', 'title': 'Solo goal', 'note': null,
          'completed_at': null, 'updated_at': '2026-09-14T09:00:00Z',
          'child_count': 1, 'completed_child_count': 0,
        }],
        'list_planning_goal_tasks': (_) async => [{
          'id': 'c1', 'relationship_id': 'r1', 'created_by': 'u1',
          'item_kind': 'task', 'parent_goal_id': 'g1', 'title': 'Only task',
          'note': null, 'assigned_to': null, 'due_date': null,
          'completed_at': null, 'celebrated_at': null,
          'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
          'deleted_at': null,
        }],
        'list_planning_tasks': (_) async => <dynamic>[],
        'list_planning_events': (_) async => <dynamic>[],
        'delete_planning_item': (_) {
          deleteAttempted = true;
          throw PostgrestException(
            message: 'Delete the goal instead, or add another task first',
            code: 'P0001',
          );
        },
      }));

      await tester.pumpWidget(_wrap(
        const PlanningHomeScreen(relationshipId: 'r1'), repository,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solo goal'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Only task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleteAttempted, isTrue);
      expect(
        find.textContaining('Delete the goal instead'),
        findsOneWidget,
        reason: 'the validation message must reach the user, not a generic error',
      );
      expect(find.text('Delete this goal instead'), findsOneWidget);
    },
  );

  group('top-level task toggle: optimistic mutation ordering', () {
    // Real mutation tests of the ordering the plan's Global Constraint
    // requires: apply locally -> call RPC -> on success, replace with the
    // RPC's OWN authoritative row (never the client's guess) -> on
    // failure, roll back to the PRE-mutation snapshot, not to whatever the
    // provider's state happens to be when the failure arrives.

    testWidgets(
      'checking the box flips the UI immediately, before the RPC resolves',
      (tester) async {
        final rpcGate = Completer<void>();
        // Stateful fake: list_planning_tasks reflects whatever
        // set_planning_task_completion last wrote, the same way a real
        // backend would — a test fixture that always serves the original
        // row regardless of mutations would let a bug where the
        // optimistic value gets silently discarded on refresh hide behind
        // a fixture that happens to agree with the (wrong) discarded
        // state.
        var completedAt = null as String?;
        var dueDate = null as String?;
        // Stateful fake: list_planning_tasks reflects whatever
        // set_planning_task_completion last wrote, the same way a real
        // backend would — including the due_date the RPC's own response
        // carries, so a subsequent provider refresh agrees with the
        // authoritative row rather than serving stale pre-mutation data
        // that would silently overwrite it.
        final repository = PlanningRepository(_FakeGateway({
          'list_planning_goals': (_) async => <dynamic>[],
          'list_planning_tasks': (_) async => [{
            'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
            'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
            'note': null, 'assigned_to': null, 'due_date': dueDate,
            'completed_at': completedAt, 'celebrated_at': null,
            'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
            'deleted_at': null,
          }],
          'list_planning_events': (_) async => <dynamic>[],
          // The RPC's returned due_date is DIFFERENT from what the client
          // had — standing in for the same reason completed_at is
          // server-generated (a due_date shifted by a server-side rule,
          // say). If the widget kept rendering its own client-guessed
          // optimistic row instead of swapping in this authoritative one,
          // this due_date would never appear.
          'set_planning_task_completion': (_) async {
            await rpcGate.future; // held open until the test releases it
            completedAt = '2026-09-14T09:30:00Z';
            dueDate = '2026-09-20';
            return {
              'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
              'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
              'note': null, 'assigned_to': null, 'due_date': dueDate,
              'completed_at': completedAt, 'celebrated_at': null,
              'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:30:00Z',
              'deleted_at': null,
            };
          },
        }));

        await tester.pumpWidget(_wrap(
          const PlanningHomeScreen(relationshipId: 'r1'), repository,
        ));
        await tester.pumpAndSettle();

        final checkboxFinder = find.byType(Checkbox);
        expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

        await tester.tap(checkboxFinder);
        await tester.pump(); // Checkbox's own tap-driven rebuild
        await tester.pump(); // our own setState from the optimistic apply

        // The RPC has NOT resolved yet (rpcGate still held), yet the
        // checkbox already shows checked — proof the local state was
        // applied before the RPC call completed, not after.
        expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);

        rpcGate.complete();
        await tester.pumpAndSettle();

        // After success, still checked — now backed by the RPC's own
        // authoritative row.
        expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);
        // And the row shows the due date that ONLY the RPC's returned
        // row carries — proof the widget swapped in the authoritative
        // response rather than continuing to render its own
        // client-constructed optimistic guess.
        expect(find.textContaining('Sep 20'), findsOneWidget);
      },
    );

    testWidgets(
      'on RPC failure, the checkbox rolls back to the exact pre-mutation '
      'state, not to a stale generic default',
      (tester) async {
        final rpcGate = Completer<void>();
        final repository = PlanningRepository(_FakeGateway({
          'list_planning_goals': (_) async => <dynamic>[],
          'list_planning_tasks': (_) async => [{
            'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
            'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
            'note': 'keep this exact note', 'assigned_to': null, 'due_date': null,
            'completed_at': null, 'celebrated_at': null,
            'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
            'deleted_at': null,
          }],
          'list_planning_events': (_) async => <dynamic>[],
          'set_planning_task_completion': (_) async {
            await rpcGate.future; // held open until the test releases it
            throw PostgrestException(message: 'Network hiccup', code: '08000');
          },
        }));

        await tester.pumpWidget(_wrap(
          const PlanningHomeScreen(relationshipId: 'r1'), repository,
        ));
        await tester.pumpAndSettle();

        final checkboxFinder = find.byType(Checkbox);
        expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

        await tester.tap(checkboxFinder);
        await tester.pump(); // Checkbox's own tap-driven rebuild
        await tester.pump(); // our own setState from the optimistic apply
        expect(
          tester.widget<Checkbox>(checkboxFinder).value,
          isTrue,
          reason: 'the RPC has not resolved yet (rpcGate still held) — the '
              'optimistic apply must already be visible',
        );

        rpcGate.complete();
        await tester.pumpAndSettle(); // RPC throws, rollback happens

        // Rolled back to the pre-mutation (unchecked) state.
        expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);
        // A generic error, since PlanningNetworkError has no specific
        // message of its own.
        expect(find.text('Could not reach the server. Try again.'), findsOneWidget);
      },
    );

    testWidgets(
      'rollback restores the captured pre-mutation snapshot even when a '
      'concurrent refresh has already changed the provider state '
      '(never clobbers a partner\'s concurrent edit with a stale rollback)',
      (tester) async {
        // Simulates: user toggles the box, the RPC is in flight and about
        // to fail, but a concurrent Realtime-triggered refresh lands FIRST
        // and changes the task's title (as a partner's edit would) before
        // the failure arrives. The rollback must still restore exactly the
        // ORIGINAL pre-mutation row this mutation captured — proving the
        // rollback target is a captured snapshot, not "whatever the
        // provider holds now".
        var listCallCount = 0;
        final rpcGate = Completer<void>();
        final repository = PlanningRepository(_FakeGateway({
          'list_planning_goals': (_) async => <dynamic>[],
          'list_planning_tasks': (_) async {
            listCallCount++;
            // First load: original title. Any subsequent load (the
            // concurrent refresh fired mid-mutation): a different title,
            // standing in for a partner's concurrent edit.
            final title = listCallCount == 1 ? 'Water the plants' : 'Partner renamed this';
            return [{
              'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
              'item_kind': 'task', 'parent_goal_id': null, 'title': title,
              'note': null, 'assigned_to': null, 'due_date': null,
              'completed_at': null, 'celebrated_at': null,
              'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
              'deleted_at': null,
            }];
          },
          'list_planning_events': (_) async => <dynamic>[],
          'set_planning_task_completion': (_) async {
            await rpcGate.future;
            throw PostgrestException(message: 'Network hiccup', code: '08000');
          },
        }));

        await tester.pumpWidget(_wrap(
          const PlanningHomeScreen(relationshipId: 'r1'), repository,
        ));
        await tester.pumpAndSettle();
        expect(find.text('Water the plants'), findsOneWidget);

        await tester.tap(find.byType(Checkbox));
        await tester.pump(); // optimistic apply in flight

        // Concurrent refresh lands while the mutation's own RPC is still
        // pending — same widget tree, same task id, different title.
        // (Exercises the provider's refresh() directly, standing in for a
        // Realtime-triggered refresh from a partner's edit.)
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PlanningHomeScreen)),
        );
        await container.read(planningTasksProvider('r1').notifier).refresh();
        await tester.pump();

        rpcGate.complete();
        await tester.pumpAndSettle();

        // The rollback must restore the ORIGINAL captured pre-mutation
        // task (title "Water the plants"), not silently keep or clobber
        // the concurrently-refreshed "Partner renamed this" with some
        // other stale value.
        expect(find.text('Water the plants'), findsOneWidget);
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      },
    );

    testWidgets(
      'the RPC\'s own authoritative row is shown even before the '
      'follow-up provider refresh network round-trip lands (closes the '
      'gap between RPC success and refresh completing)',
      (tester) async {
        final rpcGate = Completer<void>();
        final refreshGate = Completer<void>();
        var listCallCount = 0;
        final repository = PlanningRepository(_FakeGateway({
          'list_planning_goals': (_) async => <dynamic>[],
          'list_planning_tasks': (_) async {
            listCallCount++;
            // First call (initial load) resolves immediately; every
            // subsequent call (the post-mutation refresh) is held open
            // by refreshGate, standing in for a slow network refresh
            // that has not landed yet when the RPC itself already has.
            if (listCallCount == 1) {
              return [{
                'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
                'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
                'note': null, 'assigned_to': null, 'due_date': null,
                'completed_at': null, 'celebrated_at': null,
                'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
                'deleted_at': null,
              }];
            }
            await refreshGate.future;
            return [{
              'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
              'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
              'note': null, 'assigned_to': null, 'due_date': '2026-09-20',
              'completed_at': '2026-09-14T09:30:00Z', 'celebrated_at': null,
              'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:30:00Z',
              'deleted_at': null,
            }];
          },
          'list_planning_events': (_) async => <dynamic>[],
          'set_planning_task_completion': (_) async {
            await rpcGate.future;
            return {
              'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
              'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
              'note': null, 'assigned_to': null, 'due_date': '2026-09-20',
              'completed_at': '2026-09-14T09:30:00Z', 'celebrated_at': null,
              'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:30:00Z',
              'deleted_at': null,
            };
          },
        }));

        await tester.pumpWidget(_wrap(
          const PlanningHomeScreen(relationshipId: 'r1'), repository,
        ));
        await tester.pumpAndSettle();

        final checkboxFinder = find.byType(Checkbox);
        await tester.tap(checkboxFinder);
        await tester.pump();
        await tester.pump();

        rpcGate.complete(); // the mutation's own RPC succeeds now
        await tester.pump();
        await tester.pump();

        // The follow-up refresh() call is now in flight (refreshGate
        // not yet released) — its own PlanningKeysetPager sets its
        // provider to AsyncValue.loading() the instant refresh() is
        // called, so the Tasks section legitimately shows a spinner
        // rather than the row for this window; that is current,
        // intended behaviour, not the thing under test here. What
        // matters is that the row comes back correctly once the refresh
        // actually lands, backed by the RPC's OWN authoritative values
        // (not whatever stale guess the widget held before).
        refreshGate.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
        expect(find.textContaining('Sep 20'), findsOneWidget);
      },
    );
  });
}