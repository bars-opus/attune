// Spec 1 W4b (§3.8 R3, R4; Q7): under flow_couples_v2 the space names the
// partner from R1 (this phone only); "Send again" and "Invite your partner"
// open R1's share step; day 7 offers "Send a new invite" (old code gone, a
// new one made, counted); day 30 asks once; refusals are the app's words.
// Tab 2's first linked view on a phone is R4, "Welcome, {couple}" (the
// couple's chosen name, else "Couples": preflight F-1).
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment_gate.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/home/widgets/home_tab_two.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-r3v2';

final _pending = snapshotOf(homeJson(path: 'relationship', link: 'pending'));

Future<(FlowHarness, FakeInvites)> _pump(
  WidgetTester tester, {
  FakeInvites? invites,
  HomeSnapshot? home,
  bool couplesV2 = true,
  Map<String, Object> prefsValues = const {},
}) async {
  await tester.pumpWidget(const SizedBox());
  final fake = invites ?? FakeInvites();
  final h = await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(home: home ?? _pending),
    size: const Size(390, 2600),
    prefsValues: prefsValues,
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: 'relationship')),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(fake),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      flowCouplesV2Provider.overrideWithValue(couplesV2),
    ],
  );
  return (h, fake);
}

Future<FlowHarness> _pumpTabTwo(
  WidgetTester tester, {
  required HomeSnapshot home,
  bool couplesV2 = true,
  Map<String, Object> prefsValues = const {},
}) async {
  await tester.pumpWidget(const SizedBox());
  return pumpFlowScreen(
    tester,
    () => HomeTabTwo(
      tab: AppTab.chat,
      home: home,
      onInviteSent: () {},
      couplesV2: couplesV2,
    ),
    prefsValues: prefsValues,
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      // It reads Supabase directly; no chat name chosen yet.
      coupleNameProvider.overrideWith((ref, id) async => null),
    ],
  );
}

void main() {
  testWidgets('the partner named from R1, on this phone only', (tester) async {
    await _pump(
      tester,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    expect(find.text('Get a heads-up when Ama joins'), findsOneWidget);
    expect(
      find.text(
        'When your partner joins, read receipts start off. You and Ama can '
        'each turn them on later.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Send again" opens R1\'s share step', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();
    expect(find.text('at /invite-partner'), findsOneWidget);
  });

  testWidgets('no invite: "Invite your partner" opens R1\'s share step', (
    tester,
  ) async {
    final (_, invites) = await _pump(
      tester,
      home: snapshotOf(homeJson(path: 'relationship')),
    );
    await tester.tap(find.text('Invite your partner'));
    await tester.pumpAndSettle();
    expect(find.text('at /invite-partner'), findsOneWidget);
    expect(invites.creates, 0);
  });

  testWidgets('day 7: keep waiting, send a new invite, on my own', (
    tester,
  ) async {
    final invites = FakeInvites()..age = const Duration(days: 7, hours: 1);
    final (h, _) = await _pump(
      tester,
      invites: invites,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    expect(find.text("It's been a week"), findsOneWidget);
    expect(
      find.text(
        'Your invite to Ama has run its week. What would you like to do?',
      ),
      findsOneWidget,
    );
    expect(find.text('Keep waiting'), findsOneWidget);
    expect(
      find.text('Send it to the same number or a different one.'),
      findsOneWidget,
    );
    expect(find.text('Use Attune on my own for now'), findsOneWidget);
    expect(find.text('Invite someone else'), findsNothing);
    final before = invites.creates;
    await tester.tap(
      find.descendant(
        of: find.byType(PendingInviteGuide),
        matching: find.text('Send a new invite'),
      ),
    );
    await tester.pumpAndSettle();
    expect(invites.withdrawals, 1);
    expect(invites.creates, before + 1);
    expect(h.metrics, contains('invite_new_day7'));
    expect(find.text('at /invite-partner'), findsOneWidget);
  });

  testWidgets('day 30: asked once, counted; never again on this phone', (
    tester,
  ) async {
    final invites = FakeInvites()..age = const Duration(days: 31);
    final (h, _) = await _pump(tester, invites: invites);
    expect(
      find.text('Want to send your partner a new invite?'),
      findsOneWidget,
    );
    expect(h.metrics, contains('invite_day30_shown'));
    expect(h.prefs.getBool('attune.flow.$_uid.invite_day30'), isTrue);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Want to send your partner a new invite?'), findsNothing);
    final (_, _) = await _pump(
      tester,
      invites: FakeInvites()..age = const Duration(days: 32),
      prefsValues: {'attune.flow.$_uid.invite_day30': true},
    );
    expect(find.text('Want to send your partner a new invite?'), findsNothing);
  });

  // Ruling (B6 review M-6): from day 7 R3 never mints a code by itself;
  // a new one comes only from "Send a new invite".
  testWidgets('day 7 on: R3 never mints a code by itself', (tester) async {
    final invites = FakeInvites()..age = const Duration(days: 8);
    await _pump(tester, invites: invites);
    expect(invites.creates, 0);
    await tester.tap(find.text('Keep waiting'));
    await tester.pumpAndSettle();
    expect(invites.creates, 0);
    expect(invites.withdrawals, 0);
  });

  // Final review #3: "Keep waiting" is never a dead control: it snoozes
  // the day-7 prompt for this visit (the waiting state), keeps the code
  // there is and makes no new one.
  testWidgets('day 7: "Keep waiting" snoozes the prompt, mints nothing', (
    tester,
  ) async {
    final invites = FakeInvites()..age = const Duration(days: 8);
    await _pump(tester, invites: invites);
    expect(find.text("It's been a week"), findsOneWidget);
    await tester.tap(find.text('Keep waiting'));
    await tester.pumpAndSettle();
    expect(find.text("It's been a week"), findsNothing);
    expect(find.text('A private space while you wait'), findsOneWidget);
    expect(invites.creates, 0);
    expect(invites.withdrawals, 0);
  });

  // Review M-1: day 30 is counted when shown (invite_day30_shown); its
  // send is not a day-7 send.
  testWidgets('day 30: its "Send a new invite" is not counted as day 7', (
    tester,
  ) async {
    final invites = FakeInvites()..age = const Duration(days: 31);
    final (h, _) = await _pump(tester, invites: invites);
    final day30 = find.ancestor(
      of: find.text('Want to send your partner a new invite?'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: day30, matching: find.text('Send a new invite')),
    );
    await tester.pumpAndSettle();
    expect(invites.withdrawals, 1);
    expect(invites.creates, 1);
    expect(h.metrics, contains('invite_day30_shown'));
    expect(h.metrics, isNot(contains('invite_new_day7')));
    expect(find.text('at /invite-partner'), findsOneWidget);
  });

  // Review M-2: the old code went and the new one failed: said in words,
  // even as the space turns to "no invite".
  testWidgets('a failed new invite after the withdraw is said, not wiped', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final gateway = FakeHomeStateGateway(state: homeJson(path: 'relationship'));
    final invites = FakeInvites(
      createError: const RelationshipInviteException(
        'You already have the maximum number of pending invites',
        kind: InviteRefusalKind.cap,
      ),
    )..age = const Duration(days: 8);
    await pumpFlowScreen(
      tester,
      () => Consumer(
        builder: (_, ref, __) {
          final live = ref.watch(homeStateProvider(_uid));
          // Pending until the server's first answer (no invite: none).
          return RelationshipSpaceScreen(
            home: gateway.count('get_my_home_state') == 0 ? _pending : live,
          );
        },
      ),
      size: const Size(390, 2600),
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
        homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
        invitePartnerServiceProvider.overrideWithValue(invites),
        relationshipLifecycleProvider.overrideWith((ref) async => null),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
        flowCouplesV2Provider.overrideWithValue(true),
      ],
    );
    await tester.tap(
      find.descendant(
        of: find.byType(PendingInviteGuide),
        matching: find.text('Send a new invite'),
      ),
    );
    await tester.pumpAndSettle();
    expect(invites.withdrawals, 1);
    expect(find.text('Invite your partner'), findsWidgets);
    expect(find.text("It's been a week"), findsNothing);
    expect(
      find.text(
        'You already have 3 invites waiting. Cancel one before you send another.',
      ),
      findsOneWidget,
    );
  });

  // Review M-5 (§3.8 R3): "Invite {name}" when R1's name is on the phone.
  testWidgets('no invite: "Invite Ama" when R1 kept the name', (tester) async {
    final (_, invites) = await _pump(
      tester,
      home: snapshotOf(homeJson(path: 'relationship')),
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    expect(find.text('Invite your partner'), findsNothing);
    await tester.tap(find.text('Invite Ama'));
    await tester.pumpAndSettle();
    expect(find.text('at /invite-partner'), findsOneWidget);
    expect(invites.creates, 0);
  });

  testWidgets('a refusal is the app\'s words', (tester) async {
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

  testWidgets('flag off: today\'s guide, no "Send again"', (tester) async {
    await _pump(
      tester,
      couplesV2: false,
      invites: FakeInvites()..age = const Duration(days: 8),
    );
    expect(find.text('Invite someone else'), findsOneWidget);
    expect(find.text('Send again'), findsNothing);
  });

  testWidgets('day 7 and day 30 meet the three guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      invites: FakeInvites()..age = const Duration(days: 7, hours: 1),
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    await expectFlowGuidelines(tester);
    await _pump(tester, invites: FakeInvites()..age = const Duration(days: 31));
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  // Review M-7: day 7 framed from its title; the card with "Send again".
  for (final (name, days, scrollTo) in [
    ('r3_v2_day7', 8, "It's been a week"),
    ('r3_v2_day30', 31, 'Want to send Ama a new invite?'),
    ('r3_v2_card', null, 'Invite your partner'),
  ]) {
    testWidgets('$name goldens', (tester) async {
      await expectFlowGoldens(
        tester,
        name,
        () => RelationshipSpaceScreen(home: _pending),
        prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(FakeHomeStateGateway()),
          ),
          invitePartnerServiceProvider.overrideWithValue(
            FakeInvites()..age = days == null ? null : Duration(days: days),
          ),
          relationshipLifecycleProvider.overrideWith((ref) async => null),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
          flowCouplesV2Provider.overrideWithValue(true),
        ],
        before: (tester) async {
          await tester.scrollUntilVisible(
            find.text(scrollTo),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await Scrollable.ensureVisible(
            tester.element(find.text(scrollTo)),
            alignment: 0.1,
          );
          await tester.pumpAndSettle();
        },
      );
    });
  }

  testWidgets('Tab 2, linked, first time on this phone: R4, then the chat', (
    tester,
  ) async {
    final home = snapshotOf(
      homeJson(
        path: 'relationship',
        link: 'linked',
        relationshipId: 'r1',
        partnerFirstName: 'Ama',
      ),
    );
    final h = await _pumpTabTwo(
      tester,
      home: home,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    expect(find.byType(LinkedMomentGate), findsOneWidget);
    expect(find.text('Welcome, Couples'), findsOneWidget);
    expect(find.text('Get notified when Ama messages you'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(h.prefs.getBool('attune.linked_moment:$_uid:r1'), isTrue);
    expect(
      h.prefs.containsKey('attune.flow.$_uid.partner_first_name'),
      isFalse,
    );
    expect(find.text('Welcome, Couples'), findsNothing);
  });

  testWidgets('Tab 2, linked, already seen on this phone: no R4', (
    tester,
  ) async {
    final home = snapshotOf(
      homeJson(path: 'relationship', link: 'linked', relationshipId: 'r1'),
    );
    await _pumpTabTwo(
      tester,
      home: home,
      prefsValues: {'attune.linked_moment:$_uid:r1': true},
    );
    expect(find.byType(LinkedMomentGate), findsOneWidget);
    expect(find.text('Welcome, Couples'), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('Tab 2, linked, flag off: no R4', (tester) async {
    final home = snapshotOf(
      homeJson(path: 'relationship', link: 'linked', relationshipId: 'r1'),
    );
    await _pumpTabTwo(tester, home: home, couplesV2: false);
    expect(find.byType(LinkedMomentGate), findsNothing);
    expect(find.text('Welcome, Couples'), findsNothing);
  });
}
