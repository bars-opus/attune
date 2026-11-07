// Spec 2 W2 final review I-1: the readiness result's success styling (the
// primary-colour ring and score, and "Continue to journey completion →")
// follows the server's is_eligible, which is now "a completed journey with
// a score above 70". A low score gets the neutral ring and "Back to
// journey", right under its gentle message. The screen itself is unchanged
// (P-8); this pins how it reads the answer.
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_readiness_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/flow_harness.dart';
import '../../helpers/tap_in_reach.dart';
import 'w9e/support/healing_fakes.dart';

const _low =
    'Your answers suggest there may be more you want to explore. Go at your own pace.';
const _high =
    'Your check-in is complete. Healing stays here whenever you want it.';

/// Answers the readiness submit with [result].
class _Repo extends FakeHealingRepository {
  _Repo(this.result);

  final Map<String, dynamic> result;

  @override
  Future<Map<String, dynamic>> submitReadiness({
    required String journeyId,
    required Map<String, dynamic> answers,
  }) async => result;
}

Future<ColorScheme> _submit(WidgetTester t, Map<String, dynamic> result) async {
  await pumpFlowScreen(
    t,
    () => HealingReadinessScreen(journey: testJourney(stage: 5)),
    size: const Size(900, 1600),
    overrides: [healingRepositoryProvider.overrideWithValue(_Repo(result))],
  );
  await t.pumpAndSettle();
  for (var i = 0; i < 7; i++) {
    await tapInReach(t, find.text('3').at(i));
    await t.pump();
  }
  await tapInReach(t, find.text('Submit'));
  await t.pumpAndSettle();
  return Theme.of(t.element(find.text('Check-in score'))).colorScheme;
}

BoxDecoration _ring(WidgetTester t) =>
    t
            .widget<Container>(
              find.ancestor(
                of: find.text('Check-in score'),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Container &&
                      w.decoration is BoxDecoration &&
                      (w.decoration as BoxDecoration).shape == BoxShape.circle,
                ),
              ),
            )
            .decoration
        as BoxDecoration;

void main() {
  testWidgets('a low score: the neutral ring and "Back to journey", never '
      'the success styling', (t) async {
    final colors = await _submit(t, {
      'score': 40,
      'is_eligible': false,
      'message': _low,
    });
    expect(find.text(_low), findsOneWidget);
    expect(find.text('Back to journey'), findsOneWidget);
    expect(find.text('Continue to journey completion →'), findsNothing);
    expect(t.widget<Text>(find.text('40')).style?.color, isNot(colors.primary));
    expect((_ring(t).border! as Border).top.color, isNot(colors.primary));
  });

  testWidgets('no is_eligible (an older server): never the success styling', (
    t,
  ) async {
    await _submit(t, {'score': 40, 'message': _low});
    expect(find.text('Back to journey'), findsOneWidget);
    expect(find.text('Continue to journey completion →'), findsNothing);
  });

  testWidgets('a completed journey above 70: the success ring and "Continue '
      'to journey completion →"', (t) async {
    final colors = await _submit(t, {
      'score': 86,
      'is_eligible': true,
      'message': _high,
    });
    expect(find.text(_high), findsOneWidget);
    expect(find.text('Continue to journey completion →'), findsOneWidget);
    expect(find.text('Back to journey'), findsNothing);
    expect(t.widget<Text>(find.text('86')).style?.color, colors.primary);
    expect((_ring(t).border! as Border).top.color, colors.primary);
  });
}
