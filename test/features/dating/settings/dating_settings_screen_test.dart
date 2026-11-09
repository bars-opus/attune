// Spec 2 W3a (§3.12 lock row; carry 5): the settings shell: the Dating lock
// (Spec 1's setting), the notice while asked for, and the reflection's clear
// in every home state.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

void main() {
  for (final state in DatingHomeState.values) {
    testWidgets('carry 5: the clear is there when the home is ${state.wire}', (
      t,
    ) async {
      final wait = FakeWait();
      await pumpFlowScreen(
        t,
        () => const DatingSettingsScreen(),
        overrides: datingShellOverrides(
          home: FakeDatingHomeGateway(home: DatingHome(state: state)),
          wait: wait,
        ),
      );
      await tapInReach(t, find.text('Clear my answers to the three questions'));
      await t.pumpAndSettle();
      expect(wait.clears, 1);
      expect(wait.saves, isEmpty);
      expect(find.text('Your answers are cleared.'), findsOneWidget);
    });
  }

  testWidgets('a busy clear says so calmly', (t) async {
    final wait = FakeWait()..result = GentleWaitSave.busy;
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(wait: wait),
    );
    await tapInReach(t, find.text('Clear my answers to the three questions'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try clearing again in a moment.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the notice row shows while asked for; off cancels it', (
    t,
  ) async {
    final home = FakeDatingHomeGateway(
      home: const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true, requested: true),
      ),
    );
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text('Tell me when Dating opens'));
    await t.pumpAndSettle();
    expect(home.cancels, 1);
  });

  testWidgets('the Dating lock row is Spec 1\'s setting', (t) async {
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(),
    );
    expect(find.text('Dating lock'), findsOneWidget);
    expect(
      find.text('Ask for your Safety PIN before showing Dating.'),
      findsOneWidget,
    );
    await expectFlowGuidelines(t);
  });
}
