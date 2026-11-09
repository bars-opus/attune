// Spec 2 W3a (W2 carry, batch-5 M-3): D0 names "not eligible" and "confirm
// it's you" as their own states, and an untrusted phone can still clear.
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';

Future<FakeWait> _open(WidgetTester t, {Object? readError}) async {
  final wait = FakeWait()..readError = readError;
  await pumpFlowScreen(
    t,
    () => GentleWaitScreen(onSetUp: () {}),
    overrides: datingShellOverrides(wait: wait),
  );
  await t.pumpAndSettle();
  return wait;
}

void main() {
  testWidgets('a save refused as not eligible says so, not "went wrong"', (
    t,
  ) async {
    final wait = await _open(t);
    wait.result = GentleWaitSave.notEligible;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Calm');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text(
        "Dating isn't available on this account right now, so your answers "
        "weren't saved.",
      ),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Try again.'), findsNothing);
  });

  testWidgets('a save on an untrusted phone asks to confirm it\'s you', (
    t,
  ) async {
    final wait = await _open(t);
    wait.result = GentleWaitSave.reverifyDevice;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Calm');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text("Confirm it's you on this phone to see Dating."),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable reflection on an untrusted phone still offers '
      'the clear, which needs no device', (t) async {
    final wait = await _open(
      t,
      readError: const GentleWaitUnavailable('reverify_device'),
    );
    expect(
      find.text("Confirm it's you on this phone to see Dating."),
      findsOneWidget,
    );
    expect(find.text('Patience with myself'), findsNothing);
    await tapInReach(t, find.text('Clear my answers'));
    await t.pumpAndSettle();
    expect(wait.clears, 1);
    expect(wait.saves, isEmpty);
    expect(find.text('Your answers are cleared.'), findsOneWidget);
    await expectFlowGuidelines(t);
  });
}
