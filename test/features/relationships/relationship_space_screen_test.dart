// Spec 1 W3b (§3.8 R3, review R-5): the Relationship path's space when not
// linked, in each link state; never anything about Dating; "Cancel this
// invite" returns to the path the person came from.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_invites.dart';
import '../../helpers/fake_push_asker.dart';
import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

Future<(FlowHarness, FakeHomeStateGateway, FakeInvites)> _pump(
  WidgetTester tester,
  HomeSnapshot home, {
  double textScale = 1.0,
  FakeInvites? fakeInvites,
  RelationshipLifecycle? lifecycle,
}) async {
  await tester.pumpWidget(const SizedBox());
  final gateway = FakeHomeStateGateway(state: homeJson(path: 'relationship'));
  final invites = fakeInvites ?? FakeInvites();
  final h = await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(home: home),
    textScale: textScale,
    // Tall enough that the whole list is built (it is lazy).
    size: const Size(390, 2400),
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r3'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
      invitePartnerServiceProvider.overrideWithValue(invites),
      relationshipLifecycleProvider.overrideWith((ref) async => lifecycle),
      // B6 review M-7: hermetic; notifications off.
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
    ],
  );
  return (h, gateway, invites);
}

final _states = {
  'pending': snapshotOf(homeJson(path: 'relationship', link: 'pending')),
  'none': snapshotOf(homeJson(path: 'relationship')),
  'paused': snapshotOf(homeJson(path: 'relationship', link: 'paused')),
  'ended_window': snapshotOf(
    homeJson(
      path: 'relationship',
      link: 'ended_window',
      windowEndsAt: '2026-11-20T10:00:00Z',
    ),
  ),
  'after_ending': snapshotOf(
    homeJson(path: 'relationship', link: 'after_ending'),
  ),
};

// Review M-5: the paused and ended-window spaces render the lifecycle
// card's own words, so the no-Dating check covers them too.
final _lifecycles = {
  'paused': (
    RelationshipLifecycle.fromRow({
      'relationship_id': 'r-1',
      'status': 'paused',
      'partner_first_name': 'Ama',
      'paused_by_me': true,
      'paused_at': '2026-10-20T10:00:00Z',
      'decide_by': '2026-11-19T10:00:00Z',
    }),
    'Your shared space is paused',
  ),
  'ended_window': (
    RelationshipLifecycle.fromRow({
      'relationship_id': 'r-1',
      'status': 'ended',
      'partner_first_name': 'Ama',
      'ended_by_partner': true,
      'ended_at': '2026-10-21T10:00:00Z',
      'window_ends_at': '2026-11-20T10:00:00Z',
      'chat_readable': true,
    }),
    'Your shared space has ended',
  ),
};

void main() {
  for (final entry in _states.entries) {
    testWidgets('${entry.key}: never anything about Dating', (tester) async {
      final card = _lifecycles[entry.key];
      await _pump(tester, entry.value, lifecycle: card?.$1);
      if (card != null) {
        expect(
          find.textContaining(card.$2, skipOffstage: false),
          findsWidgets,
          reason: "the lifecycle card's own words are on screen",
        );
      }
      expect(
        find.textContaining(
          RegExp('dating', caseSensitive: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(find.text('Journal', skipOffstage: false), findsOneWidget);
    });
  }

  testWidgets('pending: the invite, the guide, a first note, the receipts line', (
    tester,
  ) async {
    final (_, _, invites) = await _pump(tester, _states['pending']!);
    expect(invites.creates, 1, reason: 'the live invite, fetched');
    expect(find.text('K7P2QM'), findsOneWidget);
    expect(
      find.text(
        "We'll suggest a private reflection space if this takes a little while.",
      ),
      findsOneWidget,
    );
    expect(
      find.text('Write a first note', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('A quiz about you, for you', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text(
        'When your partner joins, read receipts start off. You can each turn them on later.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text('More ways to use Attune', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets(
    'pending: "Cancel this invite" asks, then returns to the previous path',
    (tester) async {
      final (_, gateway, _) = await _pump(tester, _states['pending']!);
      await tester.tap(find.byTooltip('Invite options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel this invite'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this invite?'), findsOneWidget);
      expect(
        find.text(
          "Your invite code will stop working. Your partner won't be told.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel invite'));
      await tester.pumpAndSettle();
      expect(
        gateway.calls
            .firstWhere((c) => c.$1 == 'withdraw_my_pending_invites')
            .$2,
        {'p_return_to_previous_path': true},
      );
      expect(
        gateway.count('get_my_home_state'),
        1,
        reason: 'the home caught up',
      );
    },
  );

  testWidgets('none: "Invite your partner" makes the invite', (tester) async {
    final (_, gateway, invites) = await _pump(tester, _states['none']!);
    expect(invites.creates, 0);
    await tester.tap(find.text('Invite your partner'));
    await tester.pumpAndSettle();
    expect(invites.creates, 1);
    expect(gateway.count('get_my_home_state'), 1);
  });

  testWidgets('inside the ending window: no invite, no "More ways"', (
    tester,
  ) async {
    await _pump(tester, _states['ended_window']!);
    expect(find.text('Invite your partner'), findsNothing);
    expect(
      find.text('More ways to use Attune', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('after the window: one "More ways" row', (tester) async {
    await _pump(tester, _states['after_ending']!);
    expect(
      find.text('More ways to use Attune', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Invite your partner'), findsNothing);
  });

  testWidgets('meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    // The space without the card (the code unavailable); with the card,
    // test/features/onboarding/w4/invite_card_screens_a11y_test.dart (P-8).
    for (final state in ['pending', 'none']) {
      await _pump(
        tester,
        _states[state]!,
        fakeInvites: FakeInvites(
          createError: const RelationshipInviteException(
            'Could not create invite.',
          ),
        ),
      );
      await expectFlowGuidelines(tester);
    }
    semantics.dispose();
  });

  for (final state in ['pending', 'none']) {
    testWidgets('R3 $state goldens', (tester) async {
      await expectFlowGoldens(
        tester,
        'r3_$state',
        () => RelationshipSpaceScreen(home: _states[state]!),
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-r3'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(FakeHomeStateGateway()),
          ),
          invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
          relationshipLifecycleProvider.overrideWith((ref) async => null),
          // W3c: notifications off, so R2's ask shows while pending.
          pushAskerProvider.overrideWithValue(FakePushAsker()),
          journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
        ],
      );
    });
  }
}
