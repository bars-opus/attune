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
    expect(find.textContaining('Could not create the goal'), findsOneWidget);

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
      expect(find.textContaining('Could not create the goal'), findsNothing);
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
}
