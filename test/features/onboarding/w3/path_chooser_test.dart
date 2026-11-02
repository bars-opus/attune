// Spec 1 W3a (§3.12, D20, P-18): choosePath answers each set_my_path
// refusal with its confirmation, then asks again confirmed; offline it
// queues only a first Relationship or Just for me choice, never Dating.
import 'dart:async';

import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';

const _uid = 'u-choose';

class _Chooser {
  _Chooser(this.harness, this.gateway, this.outcomes);
  final FlowHarness harness;
  final FakeHomeStateGateway gateway;
  final List<PathChoiceOutcome> outcomes;

  OnboardingStore get store =>
      OnboardingStore(harness.prefs, scope: 'user.$_uid');
}

Future<_Chooser> _pump(
  WidgetTester tester, {
  required AppPath path,
  bool queueOffline = false,
  String? partnerName,
  void Function(FakeHomeStateGateway gateway)? setUp,
}) async {
  final gateway = FakeHomeStateGateway(
    state: homeJson(path: null, needs: ['path']),
  );
  setUp?.call(gateway);
  final outcomes = <PathChoiceOutcome>[];
  final harness = await pumpFlowScreen(
    tester,
    () => Consumer(
      builder:
          (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  outcomes.add(
                    await choosePath(
                      context,
                      ref,
                      userId: _uid,
                      path: path,
                      queueOffline: queueOffline,
                      partnerName: partnerName,
                    ),
                  );
                },
                child: const Text('CHOOSE'),
              ),
            ),
          ),
    ),
    overrides: [
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
    ],
  );
  return _Chooser(harness, gateway, outcomes);
}

Future<void> _choose(WidgetTester tester) async {
  await tester.tap(find.text('CHOOSE'));
  await tester.pumpAndSettle();
}

List<Object?> _confirmedFlags(FakeHomeStateGateway gateway) => [
  for (final call in gateway.calls)
    if (call.$1 == 'set_my_path') call.$2!['p_confirmed'],
];

void main() {
  testWidgets('accepted at once: done, and the answer reaches the home', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      path: AppPath.justMe,
      setUp: (gw) => gw.onSetPath = (_) => gw.state = homeJson(),
    );
    await _choose(tester);
    expect(c.outcomes, [PathChoiceOutcome.done]);
    expect(_confirmedFlags(c.gateway), [false]);
    final container = ProviderScope.containerOf(
      tester.element(find.text('CHOOSE')),
    );
    expect(container.read(homeStateProvider(_uid)).path, AppPath.justMe);
  });

  testWidgets('confirm_withdraw: "Cancel invite and switch" asks again', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      path: AppPath.justMe,
      partnerName: 'Kofi',
      setUp:
          (gw) =>
              gw
                ..failNext = FakeHomeStateGateway.refusal(
                  'path:confirm_withdraw',
                )
                ..onSetPath = (_) => gw.state = homeJson(),
    );
    await _choose(tester);
    expect(find.text('Cancel your invite?'), findsOneWidget);
    expect(
      find.text("Your invite code will stop working. Kofi won't be told."),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel invite and switch'));
    await tester.pumpAndSettle();
    expect(c.outcomes, [PathChoiceOutcome.done]);
    expect(_confirmedFlags(c.gateway), [false, true]);
  });

  testWidgets('confirm_withdraw: "Keep invite" changes nothing', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      path: AppPath.justMe,
      setUp:
          (gw) =>
              gw.failNext = FakeHomeStateGateway.refusal(
                'path:confirm_withdraw',
              ),
    );
    await _choose(tester);
    expect(
      find.text(
        "Your invite code will stop working. Your partner won't be told.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep invite'));
    await tester.pumpAndSettle();
    expect(c.outcomes, [PathChoiceOutcome.cancelled]);
    expect(_confirmedFlags(c.gateway), [false]);
  });

  testWidgets('confirm_pause_dating: the pause is asked first', (tester) async {
    final c = await _pump(
      tester,
      path: AppPath.relationship,
      setUp:
          (gw) =>
              gw
                ..failNext = FakeHomeStateGateway.refusal(
                  'path:confirm_pause_dating',
                )
                ..onSetPath = (_) => gw.state = homeJson(path: 'relationship'),
    );
    await _choose(tester);
    expect(find.text('Inviting a partner pauses Dating'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(c.outcomes, [PathChoiceOutcome.done]);
    expect(_confirmedFlags(c.gateway), [false, true]);
  });

  testWidgets('relationship_open and needs_signup are answered, not retried', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      path: AppPath.justMe,
      setUp:
          (gw) =>
              gw.failNext = FakeHomeStateGateway.refusal(
                'path:relationship_open',
              ),
    );
    await _choose(tester);
    c.gateway.failNext = FakeHomeStateGateway.refusal('path:needs_signup');
    await _choose(tester);
    expect(c.outcomes, [
      PathChoiceOutcome.relationshipOpen,
      PathChoiceOutcome.needsSignUp,
    ]);
    expect(_confirmedFlags(c.gateway), [false, false]);
  });

  testWidgets('a confirmed first choice that goes offline is queued as '
      'confirmed', (tester) async {
    final c = await _pump(
      tester,
      path: AppPath.justMe,
      queueOffline: true,
      setUp:
          (gw) =>
              gw.failNext = FakeHomeStateGateway.refusal(
                'path:confirm_withdraw',
              ),
    );
    await tester.tap(find.text('CHOOSE'));
    await tester.pumpAndSettle();
    c.gateway.failAlways = TimeoutException('offline');
    await tester.tap(find.text('Cancel invite and switch'));
    await tester.pumpAndSettle();
    expect(c.outcomes, [PathChoiceOutcome.done]);
    expect(c.store.pendingPath, AppPath.justMe);
    expect(c.store.pendingPathConfirmed, isTrue);
  });

  testWidgets('offline, not queued: nothing is kept (P-18, a switch)', (
    tester,
  ) async {
    final c = await _pump(
      tester,
      path: AppPath.justMe,
      setUp: (gw) => gw.failAlways = TimeoutException('offline'),
    );
    await _choose(tester);
    expect(c.outcomes, [PathChoiceOutcome.offline]);
    expect(c.store.pendingPath, isNull);
  });

  testWidgets('offline, queued: Just for me is kept; Dating never (D20)', (
    tester,
  ) async {
    var c = await _pump(
      tester,
      path: AppPath.dating,
      queueOffline: true,
      setUp: (gw) => gw.failAlways = TimeoutException('offline'),
    );
    await _choose(tester);
    expect(c.outcomes, [PathChoiceOutcome.datingOffline]);
    expect(c.store.pendingPath, isNull);
    for (final key in c.harness.prefs.getKeys()) {
      expect(
        '${c.harness.prefs.get(key)}'.toLowerCase(),
        isNot(contains('dating')),
      );
    }

    c = await _pump(
      tester,
      path: AppPath.justMe,
      queueOffline: true,
      setUp: (gw) => gw.failAlways = TimeoutException('offline'),
    );
    await _choose(tester);
    expect(c.outcomes, [PathChoiceOutcome.done]);
    expect(c.store.pendingPath, AppPath.justMe);
    final container = ProviderScope.containerOf(
      tester.element(find.text('CHOOSE')),
    );
    expect(container.read(homeStateProvider(_uid)).tab, AppTab.me);
  });

  testWidgets('the confirmation sheet meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => Scaffold(
        body: FlowConfirmSheetBody(
          title: 'Cancel your invite?',
          body:
              "Your invite code will stop working. Your partner won't be told.",
          actions: [
            ('Cancel invite and switch', () {}),
            ('Keep invite', () {}),
          ],
        ),
      ),
    );
    expect(
      tester
          .getSemantics(find.text('Cancel your invite?'))
          .hasFlag(SemanticsFlag.isHeader),
      isTrue,
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });
}
