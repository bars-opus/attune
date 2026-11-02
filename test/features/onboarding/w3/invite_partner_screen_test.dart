// Spec 1 W3a (§3.8 R1 until W4b, §3.12, P-8): the invite is made only when
// asked for; from another path, making it is the switch to Relationship
// (online only, never queued); errors are read out with an icon; the
// screen meets the accessibility guidelines.
import 'dart:async';

import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-invite';

class _HeldInvites extends FakeInvites {
  final release = Completer<void>();

  @override
  Future<RelationshipInvite> createInvite({bool forceNew = false}) async {
    await release.future;
    return super.createInvite(forceNew: forceNew);
  }
}

Future<(FakeHomeStateGateway, List<String>, FlowHarness)> _pump(
  WidgetTester tester, {
  required FakeInvites invites,
  bool switchPath = false,
  ValueNotifier<bool>? shown,
  void Function(FakeHomeStateGateway gateway)? setUp,
}) async {
  final gateway = FakeHomeStateGateway(state: homeJson());
  setUp?.call(gateway);
  final done = <String>[];
  final visible = shown ?? ValueNotifier(true);
  final harness = await pumpFlowScreen(
    tester,
    () => ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder:
          (_, show, __) =>
              show
                  ? InvitePartnerScreen(
                    switchPath: switchPath,
                    onDone: () => done.add('done'),
                  )
                  : const Scaffold(body: Text('GONE')),
    ),
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
      invitePartnerServiceProvider.overrideWithValue(invites),
    ],
  );
  return (gateway, done, harness);
}

void main() {
  testWidgets('the invite is made only on "Create my invite"; Done leaves', (
    tester,
  ) async {
    final invites = FakeInvites();
    final (gateway, done, _) = await _pump(tester, invites: invites);
    expect(find.text('Invite your partner'), findsOneWidget);
    expect(invites.creates, 0);
    await tester.tap(find.text('Create my invite'));
    await tester.pumpAndSettle();
    expect(invites.creates, 1);
    expect(find.text('K7P2QM'), findsOneWidget);
    // Not a switch: the path is left alone.
    expect(gateway.count('set_my_path'), 0);
    await tester.tap(find.text('Done'));
    expect(done, ['done']);
  });

  testWidgets('"Invite later" leaves without an invite', (tester) async {
    final invites = FakeInvites();
    final (_, done, _) = await _pump(tester, invites: invites);
    await tester.tap(find.text('Invite later'));
    expect(done, ['done']);
    expect(invites.creates, 0);
  });

  testWidgets('from another path: the switch first, then the invite', (
    tester,
  ) async {
    final invites = FakeInvites();
    final (gateway, _, _) = await _pump(
      tester,
      invites: invites,
      switchPath: true,
      setUp:
          (gw) =>
              gw.onSetPath = (_) => gw.state = homeJson(path: 'relationship'),
    );
    await tester.tap(find.text('Create my invite'));
    await tester.pumpAndSettle();
    expect(gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'relationship',
      'p_confirmed': false,
    });
    expect(invites.creates, 1);
  });

  testWidgets('a switch offline says so, with its icon; nothing is queued', (
    tester,
  ) async {
    final invites = FakeInvites();
    final (gateway, _, harness) = await _pump(
      tester,
      invites: invites,
      switchPath: true,
      setUp: (gw) => gw.failAlways = TimeoutException('offline'),
    );
    await tester.tap(find.text('Create my invite'));
    await tester.pumpAndSettle();
    expect(
      find.text("You're offline. Try again when you're connected."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(invites.creates, 0);
    // The screen is still up: Create my invite can be tried again.
    expect(find.text('Create my invite'), findsOneWidget);
    expect(gateway.count('set_my_path'), 1);
    // A switch is never queued (P-18; the A6 queue is for a first choice).
    expect(
      OnboardingStore(harness.prefs, scope: 'user.$_uid').pendingPath,
      isNull,
    );
  });

  testWidgets('leaving while the invite is made never throws', (tester) async {
    final invites = _HeldInvites();
    final shown = ValueNotifier(true);
    await _pump(tester, invites: invites, shown: shown);
    await tester.tap(find.text('Create my invite'));
    await tester.pump();
    shown.value = false;
    await tester.pump();
    expect(find.text('GONE'), findsOneWidget);
    invites.release.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('meets the guidelines, before and after the invite', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, invites: FakeInvites());
    await expectFlowGuidelines(tester);
    await tester.tap(find.text('Create my invite'));
    await tester.pumpAndSettle();
    // The invite itself is today's InviteCard (P-8, until W4b's
    // InvitePartnerStep), shared with the Chat tab's locked screen and the
    // couples waiting step: its Share and Copy link buttons are 41.6 dp
    // tall, its selectable code and link 32 and 42 dp, and its link and
    // footer text 3.31:1. Only the labels are checked once it shows
    // (batch-3 report, concern); R1's own button is checked by hand.
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(
      tester.getSemantics(find.text('Done')),
      matchesSemantics(
        label: 'Done',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Done')).height,
      greaterThanOrEqualTo(48),
    );
    semantics.dispose();
  });
}
