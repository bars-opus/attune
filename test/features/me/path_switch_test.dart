// Spec 1 W3b (§3.12, P-18, D20): switchPath, the one way a screen inside
// the app changes the path. Dating -> Just for me asks first (unless it is
// a one-tap undo with nothing enrolled); a switch is never queued offline;
// every refusal is shown in words.
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

const _uid = 'u-switch';

class _Switcher {
  _Switcher(this.harness, this.gateway, this.outcomes);
  final FlowHarness harness;
  final FakeHomeStateGateway gateway;
  final List<PathChoiceOutcome> outcomes;

  int get setPaths => gateway.count('set_my_path');
}

Future<_Switcher> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> from,
  required AppPath to,
  bool oneTap = false,
  bool signedIn = true,
}) async {
  await tester.pumpWidget(const SizedBox());
  final gateway = FakeHomeStateGateway(state: from);
  final outcomes = <PathChoiceOutcome>[];
  final home = snapshotOf(from);
  final harness = await pumpFlowScreen(
    tester,
    () => Consumer(
      builder:
          (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  outcomes.add(
                    await switchPath(
                      context,
                      ref,
                      to: to,
                      oneTap: oneTap,
                      home: home,
                    ),
                  );
                },
                child: const Text('SWITCH'),
              ),
            ),
          ),
    ),
    overrides: [
      homeAuthProvider.overrideWithValue(
        FakeHomeAuth(signedIn ? testUser(_uid) : null),
      ),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
    ],
  );
  return _Switcher(harness, gateway, outcomes);
}

Future<void> _switch(WidgetTester tester) async {
  await tester.tap(find.text('SWITCH'));
  await tester.pumpAndSettle();
}

void main() {
  final dating = homeJson(path: 'dating', datingEnabled: true);
  final datingEnrolled = homeJson(
    path: 'dating',
    datingEnabled: true,
    datingEnrolled: true,
  );

  testWidgets('Dating -> Just for me asks first; Cancel changes nothing', (
    tester,
  ) async {
    final s = await _pump(tester, from: dating, to: AppPath.justMe);
    await _switch(tester);
    expect(find.text('Use Attune just for you?'), findsOneWidget);
    expect(
      find.text(
        'Dating will be paused and hidden. Nobody is told. You can delete '
        'your Dating profile from Dating settings.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.setPaths, 0);
    expect(s.outcomes, [PathChoiceOutcome.cancelled]);
  });

  testWidgets('Dating -> Just for me: "Switch" sends it', (tester) async {
    final s = await _pump(tester, from: dating, to: AppPath.justMe);
    s.gateway.onSetPath = (_) => s.gateway.state = homeJson(path: 'just_me');
    await _switch(tester);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(s.gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'just_me',
      'p_confirmed': false,
    });
    expect(s.outcomes, [PathChoiceOutcome.done]);
  });

  testWidgets(
    'one tap with nothing enrolled: no sheet (a wrong first choice)',
    (tester) async {
      final s = await _pump(
        tester,
        from: dating,
        to: AppPath.justMe,
        oneTap: true,
      );
      await _switch(tester);
      expect(find.text('Use Attune just for you?'), findsNothing);
      expect(s.setPaths, 1);
      expect(s.outcomes, [PathChoiceOutcome.done]);
    },
  );

  testWidgets('one tap while enrolled still asks first', (tester) async {
    final s = await _pump(
      tester,
      from: datingEnrolled,
      to: AppPath.justMe,
      oneTap: true,
    );
    await _switch(tester);
    expect(find.text('Use Attune just for you?'), findsOneWidget);
    expect(s.setPaths, 0);
  });

  testWidgets('Just for me -> Dating: no sheet, sent at once', (tester) async {
    final s = await _pump(
      tester,
      from: homeJson(path: 'just_me'),
      to: AppPath.dating,
    );
    await _switch(tester);
    expect(find.text('Use Attune just for you?'), findsNothing);
    expect(s.gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'dating',
      'p_confirmed': false,
    });
  });

  testWidgets('to Relationship: R1 makes the switch (no set_my_path here)', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      from: homeJson(path: 'just_me'),
      to: AppPath.relationship,
    );
    await _switch(tester);
    expect(find.text('at /invite-partner?switch=1'), findsOneWidget);
    expect(s.setPaths, 0);
  });

  testWidgets('offline: said in words, with nothing queued (P-18)', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      from: homeJson(path: 'dating'),
      to: AppPath.justMe,
      oneTap: true,
    );
    s.gateway.failAlways = const HomeOffline();
    await _switch(tester);
    expect(
      find.text("You're offline. Try again when you're connected."),
      findsOneWidget,
    );
    expect(s.outcomes, [PathChoiceOutcome.offline]);
    final store = OnboardingStore(
      s.harness.prefs,
      scope: '${OnboardingStore.userScopePrefix}.$_uid',
    );
    expect(store.pendingPath, isNull, reason: 'a switch is never queued');
  });

  testWidgets('Dating offline: never queued, and says why (D20)', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      from: homeJson(path: 'just_me'),
      to: AppPath.dating,
    );
    s.gateway.failAlways = const HomeOffline();
    await _switch(tester);
    expect(
      find.text("Dating needs a connection. Try again when you're online."),
      findsOneWidget,
    );
    expect(s.outcomes, [PathChoiceOutcome.datingOffline]);
    expect(
      s.harness.prefs.getKeys().where((k) => k.contains('dating')),
      isEmpty,
    );
  });

  testWidgets('an account that is not ready is told, never silent', (
    tester,
  ) async {
    final s = await _pump(
      tester,
      from: homeJson(path: 'just_me'),
      to: AppPath.dating,
    );
    s.gateway.failNext = FakeHomeStateGateway.refusal('path:needs_signup');
    await _switch(tester);
    expect(s.outcomes, [PathChoiceOutcome.needsSignUp]);
    expect(find.text("We couldn't save that. Try again."), findsOneWidget);
  });

  testWidgets('signed out: nothing is sent', (tester) async {
    final s = await _pump(
      tester,
      from: homeJson(path: 'just_me'),
      to: AppPath.dating,
      signedIn: false,
    );
    await _switch(tester);
    expect(s.outcomes, [PathChoiceOutcome.failed]);
    expect(s.gateway.calls, isEmpty);
  });

  testWidgets('"Use Attune just for you?" meets the guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, from: dating, to: AppPath.justMe);
    await _switch(tester);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });
}
