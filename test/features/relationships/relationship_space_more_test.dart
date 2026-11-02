// Spec 1 W3b (§3.8 R3, §3.11): R3 beyond the brief's cases. Leaving while
// a call runs never throws; day 7's "Use Attune on my own for now" keeps the
// path and says when it fails; a paused space shows the lifecycle card and
// no invite; Tab 2 picks Me, the chat or R3 by layout and link.
import 'dart:async';

import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/home/widgets/home_tab_two.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_invites.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

/// FakeInvites whose calls wait for [gate], and whose withdrawal can fail.
class _HeldInvites extends FakeInvites {
  Completer<void>? gate;
  Object? withdrawError;

  @override
  Future<RelationshipInvite> createInvite({bool forceNew = false}) async {
    final wait = gate;
    if (wait != null) await wait.future;
    return super.createInvite(forceNew: forceNew);
  }

  @override
  Future<void> withdrawPendingInvites() async {
    final wait = gate;
    if (wait != null) await wait.future;
    if (withdrawError != null) throw withdrawError!;
    return super.withdrawPendingInvites();
  }
}

Future<FakeHomeStateGateway> _pump(
  WidgetTester tester,
  HomeSnapshot home,
  FakeInvites invites,
) async {
  await tester.pumpWidget(const SizedBox());
  final gateway = FakeHomeStateGateway(state: homeJson(path: 'relationship'));
  await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(home: home),
    size: const Size(390, 2400),
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r3b'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
      invitePartnerServiceProvider.overrideWithValue(invites),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
    ],
  );
  return gateway;
}

final _pending = snapshotOf(homeJson(path: 'relationship', link: 'pending'));
final _none = snapshotOf(homeJson(path: 'relationship'));

void main() {
  testWidgets('leaving while "Cancel invite" runs never throws', (
    tester,
  ) async {
    final gateway = await _pump(tester, _pending, FakeInvites());
    await tester.tap(find.byTooltip('Invite options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel this invite'));
    await tester.pumpAndSettle();
    final hold = gateway.hold = Completer<void>();
    await tester.tap(find.text('Cancel invite'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    hold.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving while "Invite your partner" runs never throws', (
    tester,
  ) async {
    final invites = _HeldInvites();
    await _pump(tester, _none, invites);
    final hold = invites.gate = Completer<void>();
    await tester.tap(find.text('Invite your partner'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    hold.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('day 7 "on my own": the invites go, the path stays', (
    tester,
  ) async {
    final invites = _HeldInvites()..age = const Duration(days: 8);
    final gateway = await _pump(tester, _pending, invites);
    await tester.tap(find.text('Use Attune on my own for now'));
    await tester.pumpAndSettle();
    expect(invites.withdrawals, 1);
    expect(gateway.count('withdraw_my_pending_invites'), 0);
    expect(gateway.count('set_my_path'), 0);
    expect(gateway.count('get_my_home_state'), 1, reason: 'home caught up');
  });

  testWidgets('day 7 "on my own" that fails is said, with its icon', (
    tester,
  ) async {
    final invites =
        _HeldInvites()
          ..age = const Duration(days: 8)
          ..withdrawError = const RelationshipInviteException('nope');
    await _pump(tester, _pending, invites);
    await tester.tap(find.text('Use Attune on my own for now'));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't save that. Try again."), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('an invite that is already accepted: home catches up, no error', (
    tester,
  ) async {
    final gateway = await _pump(
      tester,
      _pending,
      FakeInvites(
        createError: const RelationshipInviteException(
          'already',
          alreadyActiveRelationship: true,
        ),
      ),
    );
    expect(gateway.count('get_my_home_state'), 1);
    expect(find.text('already'), findsNothing);
  });

  testWidgets('paused: the lifecycle card, no invite, no "More ways"', (
    tester,
  ) async {
    final invites = FakeInvites();
    await _pump(
      tester,
      snapshotOf(homeJson(path: 'relationship', link: 'paused')),
      invites,
    );
    expect(find.byType(RelationshipLifecycleCard), findsOneWidget);
    expect(find.text('Invite your partner'), findsNothing);
    expect(find.text('More ways to use Attune'), findsNothing);
    expect(invites.creates, 0);
  });

  // Review I-1: a pending invite that fails to load never dead-ends.
  testWidgets('pending: an invite that fails to load can be tried again', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final invites = FakeInvites(
      createError: const RelationshipInviteException('x'),
    );
    await _pump(tester, _pending, invites);
    expect(find.text('Try again'), findsOneWidget);
    await expectFlowGuidelines(tester);
    invites.createError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('K7P2QM'), findsOneWidget);
    expect(invites.creates, 2);
    expect(find.text('Try again'), findsNothing);
    semantics.dispose();
  });

  testWidgets('pending: "Cancel this invite" is reachable without the code', (
    tester,
  ) async {
    final gateway = await _pump(
      tester,
      _pending,
      FakeInvites(createError: const RelationshipInviteException('x')),
    );
    await tester.tap(find.byTooltip('Invite options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel this invite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel invite'));
    await tester.pumpAndSettle();
    expect(gateway.count('withdraw_my_pending_invites'), 1);
  });

  // Review M-3: the home turning pending after "Invite your partner" keeps
  // the invite just made; create-relationship-invite runs once.
  testWidgets('none -> pending: the invite is made exactly once', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    const uid = 'u-r3c';
    final gateway = FakeHomeStateGateway(state: homeJson(path: 'relationship'));
    final invites = FakeInvites();
    await pumpFlowScreen(
      tester,
      () => Consumer(
        builder:
            (_, ref, __) => RelationshipSpaceScreen(
              home: ref.watch(homeStateProvider(uid)),
            ),
      ),
      size: const Size(390, 2400),
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(uid))),
        homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
        invitePartnerServiceProvider.overrideWithValue(invites),
        relationshipLifecycleProvider.overrideWith((ref) async => null),
      ],
    );
    gateway.state = homeJson(path: 'relationship', link: 'pending');
    await tester.tap(find.text('Invite your partner'));
    await tester.pumpAndSettle();
    expect(find.text('K7P2QM'), findsOneWidget, reason: 'now pending');
    expect(invites.creates, 1);
  });

  // Ruling (couple-name rule): the receipts line names the partner, never
  // "you can both".
  testWidgets('the receipts line names the invited partner', (tester) async {
    await _pump(
      tester,
      snapshotOf(
        homeJson(
          path: 'relationship',
          link: 'pending',
          partnerFirstName: 'Ama',
        ),
      ),
      FakeInvites(),
    );
    expect(
      find.text(
        'When your partner joins, read receipts start off. You and Ama can '
        'each turn them on later.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the receipts line without a name', (tester) async {
    await _pump(tester, _pending, FakeInvites());
    expect(
      find.text(
        'When your partner joins, read receipts start off. You can each turn '
        'them on later.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('both'), findsNothing);
  });

  group('Tab 2 (HomeTabTwo)', () {
    Future<Widget> chosen(
      WidgetTester tester,
      AppTab tab,
      String link, {
      String path = 'relationship',
    }) async {
      late Widget built;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            built = HomeTabTwo(
              tab: tab,
              home: snapshotOf(homeJson(path: path, link: link)),
              onInviteSent: () {},
            ).build(context);
            return const SizedBox();
          },
        ),
      );
      return built;
    }

    testWidgets('Me layout: the Me home', (tester) async {
      expect(
        await chosen(tester, AppTab.me, 'none', path: 'just_me'),
        isA<MeHomeScreen>(),
      );
    });

    testWidgets('linked: the couple chat', (tester) async {
      final w = await chosen(tester, AppTab.chat, 'linked');
      expect(w, isA<AuthenticatedChatWorkspace>());
      expect((w as AuthenticatedChatWorkspace).isCouples, isTrue);
    });

    for (final link in [
      'none',
      'pending',
      'paused',
      'ended_window',
      'after_ending',
    ]) {
      testWidgets('$link: R3, never the locked Chat screen', (tester) async {
        expect(
          await chosen(tester, AppTab.chat, link),
          isA<RelationshipSpaceScreen>(),
        );
      });
    }
  });

  // W4a (W3 carry M-1, preflight F-4): R3's failed invite is the app's
  // words, never the service's English or RI-3's "couldn't find".
  testWidgets('a failed invite is the app\'s words, never the server\'s', (
    tester,
  ) async {
    final cases = <RelationshipInviteException, String>{
      inviteCreateFailure(
        const FunctionException(
          status: 409,
          details: {
            'error': 'You already have the maximum number of pending invites',
          },
        ),
      ): 'You already have 3 invites waiting. Cancel one before you send '
          'another.',
      const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      ): "We couldn't make your invite. Try again.",
      const RelationshipInviteException(
        'Unexpected invite response.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      ): "We couldn't make your invite. Try again.",
    };
    for (final MapEntry(key: error, value: words) in cases.entries) {
      await _pump(tester, _pending, FakeInvites(createError: error));
      expect(find.text(words), findsOneWidget, reason: error.message);
      expect(find.text(error.message), findsNothing, reason: error.message);
      expect(
        find.textContaining("We couldn't find that invite"),
        findsNothing,
        reason: error.message,
      );
    }
  });
}
