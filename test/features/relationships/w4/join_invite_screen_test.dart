// Spec 1 W4b (§3.8 RI-2, RI-3, RI-4, R4; D9): a stored code is joined only
// after "Join {name}"; the name comes from the preview; each state has its
// words; every way out but a retryable failure drops the code; the joined
// moment asks for message notifications; it meets the guidelines.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/screens/join_invite_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';

const _uid = 'u-join';
const _slot = 'attune.onboarding.user.$_uid.pending_invite';

String _stored(String code) =>
    '{"code":"$code","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}';

class _Out {
  final events = <String>[];
}

Future<(FlowHarness, FakeInvites, FakeShareActions, FakePushAsker, _Out)> _pump(
  WidgetTester tester, {
  FakeInvites? invites,
  String? code = 'K7P2QM',
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(const SizedBox());
  final fakeInvites = invites ?? FakeInvites();
  final share = FakeShareActions(whatsApp: true);
  final asker = FakePushAsker();
  final out = _Out();
  final h = await pumpFlowScreen(
    tester,
    () => JoinInviteScreen(
      onDone: () => out.events.add('done'),
      onJoined: () => out.events.add('joined'),
      onChooseAnotherWay: (first) => out.events.add('other:$first'),
      onNeedsAccount: () => out.events.add('needs'),
    ),
    textScale: textScale,
    prefsValues: {if (code != null) _slot: _stored(code)},
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: null, needs: ['path'])),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(fakeInvites),
      inviteShareActionsProvider.overrideWithValue(share),
      pushAskerProvider.overrideWithValue(asker),
      coupleNameProvider.overrideWith((ref, id) async => null),
    ],
  );
  return (h, fakeInvites, share, asker, out);
}

String? _code(FlowHarness h) =>
    OnboardingStore(h.prefs, scope: 'user.$_uid').pendingInviteCode;

void main() {
  testWidgets('RI-3: "Join Yaw?", nothing accepted before the tap (D9)', (
    tester,
  ) async {
    final (_, invites, _, _, _) = await _pump(tester);
    expect(invites.previewed, ['K7P2QM']);
    expect(invites.accepted, isEmpty);
    expect(find.text('Join Yaw?'), findsOneWidget);
    expect(
      find.text('Yaw invited you to a private space on Attune.'),
      findsOneWidget,
    );
    expect(find.text('Join Yaw'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      find.text('Not what you expected? Choose another way to use Attune'),
      findsOneWidget,
    );
  });

  testWidgets('Join: accepted once, then R4 with the R4 ask, then the chat', (
    tester,
  ) async {
    final (h, invites, _, asker, out) = await _pump(tester);
    await tester.tap(find.text('Join Yaw'));
    await tester.pumpAndSettle();
    expect(invites.accepted, ['K7P2QM']);
    expect(_code(h), isNull);
    expect(find.text('Welcome, Couples'), findsOneWidget);
    expect(find.text('Your private space with Yaw is open.'), findsOneWidget);
    expect(h.prefs.getBool('attune.linked_moment:$_uid:r-joined'), isTrue);
    await tapInReach(tester, find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(asker.asked, [PushAskContext.r4]);
    await tester.tap(find.text('Continue'));
    expect(out.events, ['joined']);
  });

  testWidgets('"Not now" drops the code (no later silent accept)', (
    tester,
  ) async {
    final (h, invites, _, _, out) = await _pump(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(_code(h), isNull);
    expect(invites.accepted, isEmpty);
    expect(out.events, ['done']);
  });

  testWidgets('"Choose another way" drops the code; A6 when no path yet', (
    tester,
  ) async {
    final (h, _, _, _, out) = await _pump(tester);
    await tester.tap(
      find.text('Not what you expected? Choose another way to use Attune'),
    );
    await tester.pumpAndSettle();
    expect(_code(h), isNull);
    expect(out.events, ['other:true']);
  });

  testWidgets('RI-4: expired names the inviter and asks on WhatsApp', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(
            state: InvitePreviewState.expired,
            inviterFirstName: 'Yaw',
          );
    final (h, _, share, _, _) = await _pump(tester, invites: invites);
    expect(find.text('This invite has expired.'), findsOneWidget);
    expect(find.text('Ask Yaw to send a new one.'), findsOneWidget);
    expect(_code(h), isNull);
    await tester.tap(find.text('Ask Yaw on WhatsApp'));
    await tester.pumpAndSettle();
    expect(
      share.whatsAppTexts.single,
      'Hi Yaw, my Attune invite expired. Could you send me a new one?',
    );
    expect(invites.accepted, isEmpty);
  });

  testWidgets('invalid: the words, then "Enter the code again" (RI-2)', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.invalid);
    await _pump(tester, invites: invites);
    expect(
      find.text(
        "We couldn't find that invite. Check the code with the person who sent it.",
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Enter the code again'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your invite code'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('own invite: the words, no accept', (tester) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.own);
    await _pump(tester, invites: invites);
    expect(
      find.text('This is your own invite. Send it to your partner instead.'),
      findsOneWidget,
    );
    expect(invites.accepted, isEmpty);
  });

  testWidgets('no stored code: RI-2, then the preview of the typed code', (
    tester,
  ) async {
    final (h, invites, _, _, _) = await _pump(tester, code: null);
    expect(find.text('Enter your invite code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'k7p2 qm');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(invites.previewed, ['K7P2QM']);
    expect(_code(h), 'K7P2QM');
    expect(find.text('Join Yaw?'), findsOneWidget);
  });

  testWidgets('a malformed typed code is refused in words', (tester) async {
    await _pump(tester, code: null);
    await tester.enterText(find.byType(TextField), 'K7');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Codes have 6 letters and numbers. Check it with the person who sent it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('already in a relationship: the spec\'s words; code dropped', (
    tester,
  ) async {
    final invites = FakeInvites(
      acceptError: const RelationshipInviteException(
        "You're already in a relationship on Attune. End it first to join a new one.",
        alreadyInRelationship: true,
        kind: InviteRefusalKind.alreadyInRelationship,
      ),
    );
    final (h, _, _, _, _) = await _pump(tester, invites: invites);
    await tester.tap(find.text('Join Yaw'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "You're already in a relationship on Attune. End it first to join a new one.",
      ),
      findsOneWidget,
    );
    expect(_code(h), isNull);
  });

  testWidgets(
    'an age refusal is neutral; no date of birth goes to A2, code kept',
    (tester) async {
      final minor = FakeInvites(
        acceptError: const RelationshipInviteException(
          'invite:not_possible',
          kind: InviteRefusalKind.notPossible,
        ),
      );
      await _pump(tester, invites: minor);
      await tester.tap(find.text('Join Yaw'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "We couldn't link these accounts. If you think this is wrong, contact support.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('18'), findsNothing);

      final noDob = FakeInvites(
        acceptError: const RelationshipInviteException(
          'invite:age_required',
          retryable: true,
          kind: InviteRefusalKind.ageRequired,
        ),
      );
      final (h, _, _, _, out) = await _pump(tester, invites: noDob);
      await tester.tap(find.text('Join Yaw'));
      await tester.pumpAndSettle();
      expect(out.events, ['needs']);
      expect(_code(h), 'K7P2QM');
    },
  );

  testWidgets('offline: said in words, the code kept, Try again', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            retryable: true,
            kind: InviteRefusalKind.unavailable,
          );
    final (h, _, _, _, _) = await _pump(tester, invites: invites);
    expect(
      find.text("We couldn't check that code. Try again when you're online."),
      findsOneWidget,
    );
    expect(_code(h), 'K7P2QM');
    invites.previewError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Join Yaw?'), findsOneWidget);
  });

  testWidgets('too many tries: said in words', (tester) async {
    final invites =
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            retryable: true,
            kind: InviteRefusalKind.tryLater,
          );
    await _pump(tester, invites: invites);
    expect(
      find.text("You've checked a lot of codes. Try again in a little while."),
      findsOneWidget,
    );
  });

  testWidgets('no name from the server: "your partner", never a placeholder', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.ok);
    await _pump(tester, invites: invites);
    expect(find.text('Join your partner?'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('RI-3 and R4 meet the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await expectFlowGuidelines(tester);
    await tester.tap(find.text('Join Yaw'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('RI-3, RI-4 and R4 goldens', (tester) async {
    List<Override> overrides(FakeInvites invites) => [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson())),
      ),
      invitePartnerServiceProvider.overrideWithValue(invites),
      inviteShareActionsProvider.overrideWithValue(
        FakeShareActions(whatsApp: true),
      ),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      coupleNameProvider.overrideWith((ref, id) async => null),
    ];
    Widget screen() => JoinInviteScreen(
      onDone: () {},
      onJoined: () {},
      onChooseAnotherWay: (_) {},
      onNeedsAccount: () {},
    );
    await expectFlowGoldens(
      tester,
      'w4_ri3',
      screen,
      prefsValues: {_slot: _stored('K7P2QM')},
      overrides: overrides(FakeInvites()),
    );
    await expectFlowGoldens(
      tester,
      'w4_ri4',
      screen,
      prefsValues: {_slot: _stored('K7P2QM')},
      overrides: overrides(
        FakeInvites()
          ..preview = const InvitePreview(
            state: InvitePreviewState.expired,
            inviterFirstName: 'Yaw',
          ),
      ),
    );
    await expectFlowGoldens(
      tester,
      'w4_r4',
      screen,
      prefsValues: {_slot: _stored('K7P2QM')},
      overrides: overrides(FakeInvites()),
      before: (tester) async {
        await tester.tap(find.text('Join Yaw'));
        await tester.pumpAndSettle();
      },
    );
  });
}
