// Spec 2 W2 batch 4 fix round 1 (I-1; §2.1, R7): the v1 Dating dashboard's
// fallback copy never names Healing as a gate. It shows whenever the
// eligibility answer carries no message (a non-Map answer, an unknown
// enrolment state). W3 replaces this screen.
import 'dart:io';

import 'package:attune/features/dating/data/models/dating_enrollment.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/flow_harness.dart';

const _fallback =
    'You always opt in separately, and nothing starts until you do.';

Future<void> _pump(WidgetTester t, {DatingEnrollment? enrollment}) =>
    pumpFlowScreen(
      t,
      () => const DatingDashboardScreen(),
      overrides: [
        datingModeEnabledProvider.overrideWith((ref) async => true),
        datingEnrollmentProvider.overrideWith((ref) async => enrollment),
        // What dating_repository.dart answers for a non-Map reply: no message.
        datingEligibilityProvider.overrideWith(
          (ref) async => <String, dynamic>{
            'is_eligible': false,
            'reason': 'unknown',
          },
        ),
      ],
    );

void main() {
  testWidgets('no enrolment and no message: the fallback never names '
      'Healing', (t) async {
    await _pump(t);
    expect(find.textContaining('Healing'), findsNothing);
    expect(find.text(_fallback), findsOneWidget);
  });

  testWidgets('an unknown enrolment state: the fallback never names '
      'Healing', (t) async {
    await _pump(
      t,
      enrollment: DatingEnrollment.fromJson({
        'user_id': 'ama',
        'state': 'ineligible',
      }),
    );
    expect(find.textContaining('Healing'), findsNothing);
    expect(find.text(_fallback), findsOneWidget);
  });

  test('the screen names no Healing gate anywhere', () {
    final source =
        File(
          'lib/features/dating/presentation/screens/dating_dashboard_screen.dart',
        ).readAsStringSync();
    expect(source, isNot(contains('Healing eligibility')));
    expect(source, isNot(contains('unlocks only after')));
    expect(source, isNot(contains('eligible through Healing')));
  });
}
