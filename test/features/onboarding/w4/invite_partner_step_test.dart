// Spec 1 W4b (§3.8 R1, R2; §2.3): under flow_couples_v2, R1 is the
// registers step: the first name stays on this phone and names the
// preview; Simple and Casual only (Pidgin waits for its review); every
// way of sending carries the code and is counted; R2 asks after a send;
// refusals are the app's words; it meets the guidelines at every size.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_partner_step.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-r1';

Future<
  (FlowHarness, FakeInvites, FakeShareActions, FakePushAsker, List<String>)
>
_pump(
  WidgetTester tester, {
  FakeInvites? invites,
  FakeShareActions? share,
  bool couplesV2 = true,
  Map<String, Object> prefsValues = const {},
  double textScale = 1.0,
  Size size = const Size(390, 2000),
}) async {
  await tester.pumpWidget(const SizedBox());
  final fakeInvites = invites ?? FakeInvites();
  final actions = share ?? FakeShareActions();
  final asker = FakePushAsker();
  final done = <String>[];
  final h = await pumpFlowScreen(
    tester,
    () => InvitePartnerScreen(
      onDone: () => done.add('done'),
      onAlreadyInvited: () => done.add('already'),
    ),
    textScale: textScale,
    size: size,
    prefsValues: prefsValues,
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: 'relationship')),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(fakeInvites),
      inviteShareActionsProvider.overrideWithValue(actions),
      pushAskerProvider.overrideWithValue(asker),
      flowCouplesV2Provider.overrideWithValue(couplesV2),
    ],
  );
  return (h, fakeInvites, actions, asker, done);
}

void main() {
  testWidgets('flow_couples_v2 off: today\'s R1, no registers', (tester) async {
    await _pump(tester, couplesV2: false);
    expect(find.byType(InvitePartnerStep), findsNothing);
    expect(find.text('Create my invite'), findsOneWidget);
  });

  testWidgets('on: the invite is made on opening; Simple and Casual only', (
    tester,
  ) async {
    final (_, invites, _, _, _) = await _pump(tester);
    expect(find.byType(InvitePartnerStep), findsOneWidget);
    expect(invites.creates, 1);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.text('Pidgin'), findsNothing);
    expect(find.text('What your partner will see'), findsOneWidget);
    expect(find.textContaining('K7P2QM'), findsOneWidget);
    expect(
      find.text('Used in your message and on this phone only.'),
      findsOneWidget,
    );
  });

  testWidgets('the first name names the preview and stays on this phone', (
    tester,
  ) async {
    final (h, _, _, _, _) = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Ama');
    await tester.pumpAndSettle();
    expect(find.text('What Ama will see'), findsOneWidget);
    expect(
      find.text('Send a link. When Ama joins, your private space opens.'),
      findsOneWidget,
    );
    expect(find.textContaining("Hi Ama, I'd like us"), findsOneWidget);
    expect(h.prefs.getString('attune.flow.$_uid.partner_first_name'), 'Ama');
  });

  testWidgets('a name saved before is there when R1 opens again', (
    tester,
  ) async {
    await _pump(
      tester,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Kofi'},
    );
    expect(find.text('What Kofi will see'), findsOneWidget);
  });

  testWidgets('Casual and the optional line change the message', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Casual'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hey! I found an app for couples'),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        "I found this myself. I just thought it'd be nice.\nGet it here:",
      ),
      findsOneWidget,
    );
  });

  testWidgets('WhatsApp when installed: the message with the code, counted', (
    tester,
  ) async {
    final share = FakeShareActions(whatsApp: true);
    final (h, _, _, _, _) = await _pump(tester, share: share);
    await tester.tap(find.text('Send on WhatsApp'));
    await tester.pumpAndSettle();
    expect(
      share.whatsAppTexts.single,
      contains('Open Attune \u2192 I have an invite \u2192 K7P2QM'),
    );
    expect(h.metrics, contains('invite_shared:whatsapp'));
  });

  testWidgets('WhatsApp that does not open falls back to the share sheet', (
    tester,
  ) async {
    final share = FakeShareActions(whatsApp: true, whatsAppOpens: false);
    await _pump(tester, share: share);
    await tester.tap(find.text('Send on WhatsApp'));
    await tester.pumpAndSettle();
    expect(share.shared.single, contains('K7P2QM'));
  });

  testWidgets('no WhatsApp: share, QR and copy, each counted', (tester) async {
    final share = FakeShareActions();
    final (h, _, _, _, _) = await _pump(tester, share: share);
    expect(find.text('Send on WhatsApp'), findsNothing);
    await tester.tap(find.text('Share another way'));
    await tester.pumpAndSettle();
    expect(share.shared.single, contains('K7P2QM'));
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(share.copied, ['K7P2QM']);
    expect(find.text('Code copied.'), findsOneWidget);
    await tester.tap(find.text('Show QR code'));
    await tester.pumpAndSettle();
    expect(find.text('Your invite code'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      h.metrics,
      containsAll([
        'invite_shared:share',
        'invite_shared:copy',
        'invite_shared:qr',
      ]),
    );
  });

  testWidgets('R2: after a send, the heads-up names the partner', (
    tester,
  ) async {
    final (_, _, _, asker, _) = await _pump(tester);
    expect(find.textContaining('Get a heads-up'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Ama');
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(find.text('Get a heads-up when Ama joins'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(asker.asked, [PushAskContext.r2]);
  });

  testWidgets('a refusal is the app\'s words, never the server\'s', (
    tester,
  ) async {
    await _pump(
      tester,
      invites: FakeInvites(
        createError: const RelationshipInviteException(
          'You already have the maximum number of pending invites',
          kind: InviteRefusalKind.cap,
        ),
      ),
    );
    expect(
      find.text(
        'You already have 3 invites waiting. Cancel one before you send another.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('maximum number'), findsNothing);
  });

  testWidgets('"Invite later" and "My partner already invited me"', (
    tester,
  ) async {
    final (_, _, _, _, done) = await _pump(tester);
    await tester.tap(find.text('Invite later'));
    await tester.tap(find.text('My partner already invited me'));
    expect(done, ['done', 'already']);
  });

  testWidgets('meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('R1 goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'w4_r1',
      () => InvitePartnerScreen(onDone: () {}, onAlreadyInvited: () {}),
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'relationship')),
          ),
        ),
        invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
        inviteShareActionsProvider.overrideWithValue(
          FakeShareActions(whatsApp: true),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
        flowCouplesV2Provider.overrideWithValue(true),
      ],
    );
  });
}
