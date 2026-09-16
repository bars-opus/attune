import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/planning_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGateway implements PlanningRpcGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> handlers;
  _FakeGateway(this.handlers);
  Map<String, dynamic>? lastParams;
  String? lastFunction;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    lastFunction = function;
    lastParams = params;
    final handler = handlers[function];
    if (handler == null) throw StateError('No fake handler for $function');
    return handler(params);
  }
}

// planningNotesProvider internally `ref.listen`s planningChangeSignalProvider,
// which synchronously reaches Supabase.instance.client to open a Realtime
// channel — there is no Supabase.initialize() in this test host (see
// planning_home_screen_test.dart's identical note), so that signal provider
// must be overridden to a harmless empty stream rather than left to hit the
// real ambient client.
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
  testWidgets('shows a note with its title and first body line', (tester) async {
    final gateway = _FakeGateway({
      'list_planning_notes': (_) async => [{
        'id': 'n1', 'relationship_id': 'r1', 'created_by': 'u1',
        'title': 'Restaurants to try', 'body': 'Thai place on 5th\nramen spot',
        'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
        'deleted_at': null,
      }],
    });
    await tester.pumpWidget(_wrap(
      const PlanningNotesScreen(relationshipId: 'r1'),
      PlanningRepository(gateway),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Restaurants to try'), findsOneWidget);
    expect(find.textContaining('Thai place on 5th'), findsOneWidget);
  });

  testWidgets('an unsaved draft survives a failed save, and offers retry', (
    tester,
  ) async {
    var attempts = 0;
    final gateway = _FakeGateway({
      'list_planning_notes': (_) async => <dynamic>[],
      'upsert_planning_note': (params) {
        attempts++;
        throw StateError('network down');
      },
    });
    await tester.pumpWidget(_wrap(
      const PlanningNotesScreen(relationshipId: 'r1'),
      PlanningRepository(gateway),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Packing list');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    // The draft text must still be in the field, not cleared by the
    // failed save — the user should be able to just tap Save again.
    expect(find.text('Packing list'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets(
    'an unauthorized save failure fails closed: no retry is offered',
    (tester) async {
      var attempts = 0;
      final gateway = _FakeGateway({
        'list_planning_notes': (_) async => <dynamic>[],
        'upsert_planning_note': (params) {
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
        const PlanningNotesScreen(relationshipId: 'r1'),
        PlanningRepository(gateway),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Packing list');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(attempts, 1);
      // The draft text is preserved either way...
      expect(find.text('Packing list'), findsOneWidget);
      // ...but unlike the transient/network case, this is NOT phrased
      // as retryable, and the Save action itself must be disabled so
      // tapping it again cannot even fire a second doomed attempt.
      expect(find.textContaining('Could not save'), findsNothing);
      expect(find.textContaining('no longer available'), findsOneWidget);

      final saveButton = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
      expect(saveButton.onPressed, isNull);

      // Confirm it's truly inert: tapping again must not re-invoke the
      // RPC (still exactly one attempt).
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
    },
  );
}
