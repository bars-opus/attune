// Spec 1 W4b carried items on RI-3 and R4 (batch 5): each failure has its
// own words (the attempt limit, the server's own failure, no connection,
// the uniform invalid); the acceptor's hold goes to the gate's H1 path; a
// preview the server refuses for good drops the code; nothing is accepted
// before the account has a name (D9); a system back drops the code like
// "Not now" (preflight F-9); R4 names the couple (F-1) and taps once.
import 'dart:async';

import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/screens/join_invite_screen.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-join-carried';
const _slot = 'attune.onboarding.user.$_uid.pending_invite';

String _stored(String code) =>
    '{"code":"$code","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}';

const _tryLater = "You've checked a lot of codes. Try again in a little while.";
const _server = 'Something went wrong on our side. Try again.';
const _offline = "We couldn't check that code. Try again when you're online.";
const _invalid =
    "We couldn't find that invite. Check the code with the person who sent it.";
const _notPossible =
    "We couldn't link these accounts. If you think this is wrong, contact support.";

List<Override> _overrides(
  FakeInvites invites, {
  Map<String, dynamic>? server,
  String? coupleName,
}) => [
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
  homeStateServiceProvider.overrideWithValue(
    HomeStateService(
      FakeHomeStateGateway(
        state: server ?? homeJson(path: null, needs: ['path']),
      ),
    ),
  ),
  invitePartnerServiceProvider.overrideWithValue(invites),
  inviteShareActionsProvider.overrideWithValue(
    FakeShareActions(whatsApp: true),
  ),
  pushAskerProvider.overrideWithValue(FakePushAsker()),
  coupleNameProvider.overrideWith((ref, id) async => coupleName),
];

Future<(FlowHarness, List<String>)> _pump(
  WidgetTester tester, {
  required FakeInvites invites,
  Map<String, dynamic>? server,
  Map<String, Object> prefs = const {},
  String? coupleName,
  bool stored = true,
}) async {
  await tester.pumpWidget(const SizedBox());
  final events = <String>[];
  final h = await pumpFlowScreen(
    tester,
    () => JoinInviteScreen(
      onDone: () => events.add('done'),
      onJoined: () => events.add('joined'),
      onChooseAnotherWay: (first) => events.add('other:$first'),
      onNeedsAccount: () => events.add('needs'),
      onHeld: () => events.add('held'),
    ),
    prefsValues: {if (stored) _slot: _stored('K7P2QM'), ...prefs},
    overrides: _overrides(invites, server: server, coupleName: coupleName),
  );
  return (h, events);
}

String? _code(FlowHarness h) =>
    OnboardingStore(h.prefs, scope: 'user.$_uid').pendingInviteCode;

/// An accept that answers when the test says.
class _SlowAccept extends FakeInvites {
  final answer = Completer<void>();

  @override
  Future<InviteAcceptance> acceptInvite(String inviteCode) async {
    await answer.future;
    return super.acceptInvite(inviteCode);
  }
}

Future<void> _tapJoin(WidgetTester tester) async {
  await tester.tap(find.text('Join Yaw'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accept past the attempt limit: try later, code kept', (
    tester,
  ) async {
    final invites = FakeInvites(
      acceptError: inviteAcceptFailure(
        const FunctionException(
          status: 429,
          details: {'error': 'invite:try_later', 'code': 'invite:try_later'},
        ),
      ),
    );
    final (h, _) = await _pump(tester, invites: invites);
    await _tapJoin(tester);
    expect(find.text(_tryLater), findsOneWidget);
    expect(find.textContaining('online'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(_code(h), 'K7P2QM');
  });

  testWidgets('accept the server could not finish: its own words, kept', (
    tester,
  ) async {
    final invites = FakeInvites(
      acceptError: inviteAcceptFailure(
        const FunctionException(
          status: 503,
          details: {'error': 'invite:try_again', 'code': 'invite:try_again'},
        ),
      ),
    );
    final (h, _) = await _pump(tester, invites: invites);
    await _tapJoin(tester);
    expect(find.text(_server), findsOneWidget);
    expect(find.textContaining('online'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(_code(h), 'K7P2QM');
  });

  testWidgets('accept with no connection: "online", kept', (tester) async {
    final invites = FakeInvites(
      acceptError: inviteAcceptFailure(Exception('socket closed')),
    );
    final (h, _) = await _pump(tester, invites: invites);
    await _tapJoin(tester);
    expect(find.text(_offline), findsOneWidget);
    expect(_code(h), 'K7P2QM');
  });

  testWidgets('a preview the server failed: its own words, kept', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            retryable: true,
            kind: InviteRefusalKind.unavailable,
            serverError: true,
          );
    final (h, _) = await _pump(tester, invites: invites);
    expect(find.text(_server), findsOneWidget);
    expect(find.textContaining('online'), findsNothing);
    expect(_code(h), 'K7P2QM');
  });

  testWidgets('the acceptor\'s hold: the gate\'s H1 path, never "not '
      'possible"', (tester) async {
    final invites = FakeInvites(
      acceptError: inviteAcceptFailure(
        const FunctionException(
          status: 403,
          details: {'error': 'account:hold', 'code': 'account:hold'},
        ),
      ),
    );
    final (h, events) = await _pump(tester, invites: invites);
    await _tapJoin(tester);
    expect(events, ['held']);
    expect(find.text(_notPossible), findsNothing);
    expect(_code(h), isNull);
  });

  testWidgets('invalid and already accepted read the same (uniform)', (
    tester,
  ) async {
    for (final code in ['invite:invalid', 'invite:already_accepted']) {
      final invites = FakeInvites(
        acceptError: inviteAcceptFailure(
          FunctionException(
            status: code == 'invite:invalid' ? 404 : 409,
            details: {'error': 'Invite code is invalid', 'code': code},
          ),
        ),
      );
      final (h, _) = await _pump(tester, invites: invites);
      await _tapJoin(tester);
      expect(find.text(_invalid), findsOneWidget, reason: code);
      expect(find.textContaining('Invite code is invalid'), findsNothing);
      expect(_code(h), isNull, reason: code);
    }
  });

  testWidgets('a preview refused for good (phone_required): code dropped', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            kind: InviteRefusalKind.phoneRequired,
          );
    final (h, _) = await _pump(tester, invites: invites);
    expect(find.text(_notPossible), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(_code(h), isNull);
  });

  testWidgets('no name yet: nothing accepted, the gate asks for it (D9)', (
    tester,
  ) async {
    final invites = FakeInvites();
    final (h, events) = await _pump(
      tester,
      invites: invites,
      server: homeJson(path: null, needs: ['name', 'path']),
    );
    await _tapJoin(tester);
    expect(invites.accepted, isEmpty);
    expect(events, ['needs']);
    expect(_code(h), 'K7P2QM');
  });

  testWidgets('a queued sign-up: nothing accepted before the account', (
    tester,
  ) async {
    final invites = FakeInvites();
    final (h, events) = await _pump(
      tester,
      invites: invites,
      prefs: {
        'attune.onboarding.user.$_uid.pending_sign_up':
            '{"display_name":"Ama","birth_date":"1990-01-01"}',
      },
    );
    await _tapJoin(tester);
    expect(invites.accepted, isEmpty);
    expect(events, ['needs']);
    expect(_code(h), 'K7P2QM');
  });

  group('a system back (F-9)', () {
    Future<FlowHarness> open(WidgetTester tester, FakeInvites invites) async {
      final h = await pumpFlowScreen(
        tester,
        () => Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => JoinInviteScreen(
                                onDone: () {},
                                onJoined: () {},
                                onChooseAnotherWay: (_) {},
                                onNeedsAccount: () {},
                              ),
                        ),
                      ),
                  child: const Text('OPEN'),
                ),
              ),
        ),
        prefsValues: {_slot: _stored('K7P2QM')},
        overrides: _overrides(invites),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('from RI-3 drops the code, like "Not now"', (tester) async {
      final invites = FakeInvites();
      final h = await open(tester, invites);
      expect(find.text('Join Yaw?'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget);
      expect(_code(h), isNull);
      expect(invites.accepted, isEmpty);
    });

    testWidgets('from a retryable failure keeps it', (tester) async {
      final invites =
          FakeInvites()
            ..previewError = const RelationshipInviteException(
              'Could not check invite.',
              retryable: true,
              kind: InviteRefusalKind.unavailable,
            );
      final h = await open(tester, invites);
      expect(find.text(_offline), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('OPEN'), findsOneWidget);
      expect(_code(h), 'K7P2QM');
    });

    // Batch-5 review M-1: R4 is marked seen as the accept lands, so the
    // screen can't be left mid-accept (R4 and its ask would be lost).
    testWidgets('during the accept keeps RI-3; R4 follows', (tester) async {
      final invites = _SlowAccept();
      await open(tester, invites);
      await tester.tap(find.text('Join Yaw'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('OPEN'), findsNothing);
      expect(find.text('Join Yaw?'), findsOneWidget);
      invites.answer.complete();
      await tester.pumpAndSettle();
      expect(invites.accepted, ['K7P2QM']);
      expect(find.text('Welcome, Couples'), findsOneWidget);
    });
  });

  testWidgets('R4 names the couple once they chose a name (F-1)', (
    tester,
  ) async {
    await _pump(tester, invites: FakeInvites(), coupleName: 'The Harolds');
    await _tapJoin(tester);
    expect(find.text('Welcome, The Harolds'), findsOneWidget);
    expect(find.textContaining('both'), findsNothing);
  });

  testWidgets('R4: one light haptic; none under reduce motion', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Widget moment() => LinkedMoment(
      relationshipId: 'r-1',
      partnerFirstName: 'Yaw',
      onContinue: () {},
    );
    await pumpFlowScreen(tester, moment, overrides: _overrides(FakeInvites()));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(find.text('Welcome, Couples'), findsOneWidget);
    haptics.clear();
    await tester.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      tester,
      moment,
      reduceMotion: true,
      overrides: _overrides(FakeInvites()),
    );
    expect(haptics, isEmpty);
    expect(find.text('Your private space with Yaw is open.'), findsOneWidget);
  });

  // Ruling M-3: a hold the home state already shows goes to the gate's H1
  // path before any accept, and drops the code like the refusal path.
  testWidgets('a hold already known: H1 path, nothing accepted, code dropped', (
    tester,
  ) async {
    final invites = FakeInvites();
    final (h, events) = await _pump(
      tester,
      invites: invites,
      server: homeJson(path: null, needs: ['path'], hold: true),
    );
    await _tapJoin(tester);
    expect(events, ['held']);
    expect(invites.accepted, isEmpty);
    expect(_code(h), isNull);
  });

  // Batch-5 review M-2: every new state meets the guidelines.
  testWidgets('RI-2, RI-4 and each refusal state meet the guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, invites: FakeInvites(), stored: false);
    expect(find.text('Enter your invite code'), findsOneWidget);
    await expectFlowGuidelines(tester);
    await tester.enterText(find.byType(TextField), 'K7');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Codes have 6 letters and numbers. Check it with the person who sent it.',
      ),
      findsOneWidget,
    );
    await expectFlowGuidelines(tester);
    for (final (what, invites) in [
      (
        'expired',
        FakeInvites()
          ..preview = const InvitePreview(
            state: InvitePreviewState.expired,
            inviterFirstName: 'Yaw',
          ),
      ),
      (
        'invalid',
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.invalid),
      ),
      (
        'own',
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.own),
      ),
      (
        'offline',
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            retryable: true,
            kind: InviteRefusalKind.unavailable,
          ),
      ),
      (
        'refused',
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            kind: InviteRefusalKind.phoneRequired,
          ),
      ),
    ]) {
      await _pump(tester, invites: invites);
      expect(find.text('Join Yaw?'), findsNothing, reason: what);
      await expectFlowGuidelines(tester);
    }
    semantics.dispose();
  });
}
