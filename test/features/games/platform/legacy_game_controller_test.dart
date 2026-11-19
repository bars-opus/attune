import 'dart:async';

import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_controller.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_opener.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

Map<String, dynamic> row(String id, String gameType, {String? initiator}) => {
  'id': id,
  'game_type': gameType,
  'initiator_id': initiator ?? 'me',
};

GameCardState card(String status, {String? turn}) => GameCardState(
  gameType: 'truth_or_dare',
  status: status,
  currentTurnUserId: turn,
  winnerUserId: null,
  currentRound: null,
  totalRounds: null,
);

/// Calls watchLanding from build, as the shell does, and offers the
/// controller's button to tap.
class _Probe extends ConsumerWidget {
  const _Probe(this.controller, this.onState);

  final LegacyGameController controller;
  final void Function(
    GameLandingState state,
    BuildContext context,
    WidgetRef ref,
  )
  onState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = controller.watchLanding(ref);
    onState(state, context, ref);
    return GestureDetector(
      key: ValueKey('play-${controller.gameType}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.onPrimary(context, ref, state),
      child: const SizedBox(width: 100, height: 100),
    );
  }
}

void main() {
  late List<Map<String, dynamic>> activeRows;
  late bool listFails;
  late Map<String, GameCardState?> cards;
  late StreamController<void> events;
  late List<(String, String?)> opened;
  late Map<String, GameLandingState> seen;
  late BuildContext probeContext;
  late WidgetRef probeRef;

  setUp(() {
    activeRows = [];
    listFails = false;
    cards = {};
    opened = [];
    seen = {};
  });

  Future<void> pumpProbes(
    WidgetTester tester, {
    List<String> gameTypes = const ['truth_or_dare'],
  }) async {
    useSurface(tester, phone);
    events = StreamController<void>();
    addTearDown(events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeGamesProvider.overrideWith((ref) async {
            if (listFails) throw Exception('offline');
            return activeRows;
          }),
          gameCardProvider.overrideWith((ref, id) => Stream.value(cards[id])),
          gameSessionEventsProvider.overrideWith((ref) => events.stream),
          currentUserIdProvider.overrideWithValue('me'),
          gamePartnerNameProvider.overrideWith((ref) async => 'Ama'),
          legacyGameOpenerProvider.overrideWithValue((
            context,
            gameType, {
            sessionId,
          }) async {
            opened.add((gameType, sessionId));
          }),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final type in gameTypes)
                _Probe(LegacyGameController(type), (state, context, ref) {
                  seen[type] = state;
                  probeContext = context;
                  probeRef = ref;
                }),
            ],
          ),
        ),
      ),
    );
    // The control for every test here: the list still on its way is loading.
    for (final type in gameTypes) {
      expect(seen[type]?.status, GameLandingStatus.loading, reason: type);
    }
    // The list, then the card.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('no game in progress reads as fresh', (tester) async {
    await pumpProbes(tester);

    expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);
    expect(seen['truth_or_dare']!.sessionId, isNull);
  });

  testWidgets('a list that fails to load still lets the player in', (
    tester,
  ) async {
    // Not a dead button: the game's own screens resume an open session.
    listFails = true;
    await pumpProbes(tester);

    expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);
    expect(seen['truth_or_dare']!.sessionId, isNull);
  });

  testWidgets('a game in progress reads from its live card', (tester) async {
    // Newest first, as the list is ordered: the first matching row is the one.
    activeRows = [
      row('w1', 'word_hunt'),
      row('s1', 'truth_or_dare'),
      row('s0', 'truth_or_dare'),
    ];
    cards = {
      'w1': card('active', turn: 'me'),
      's1': card('active', turn: 'me'),
      's0': card('active', turn: 'partner'),
    };
    await pumpProbes(tester);

    expect(seen['truth_or_dare']!.status, GameLandingStatus.yourTurn);
    expect(seen['truth_or_dare']!.sessionId, 's1');
    expect(seen['truth_or_dare']!.partnerName, 'Ama');
  });

  testWidgets('another game\'s session is not mistaken for this one', (
    tester,
  ) async {
    activeRows = [row('w1', 'word_hunt')];
    cards = {'w1': card('active', turn: 'me')};
    await pumpProbes(tester, gameTypes: const ['truth_or_dare', 'word_hunt']);

    expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);
    expect(seen['truth_or_dare']!.sessionId, isNull);
    // Positive control: the row is there, and is word_hunt's.
    expect(seen['word_hunt']!.status, GameLandingStatus.yourTurn);
    expect(seen['word_hunt']!.sessionId, 'w1');
  });

  testWidgets(
    'the button opens the game\'s current screens, with the session when '
    'there is one',
    (tester) async {
      await pumpProbes(tester);
      expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);

      await tester.tap(find.byKey(const ValueKey('play-truth_or_dare')));
      await tester.pump();
      expect(opened, [('truth_or_dare', null)]);

      // A game arrives; the same button now resumes it.
      activeRows = [row('s1', 'truth_or_dare')];
      cards = {'s1': card('active', turn: 'me')};
      events.add(null);
      // The event, the refetched list, then the new session's card.
      await tester.pumpAndSettle();
      expect(seen['truth_or_dare']!.status, GameLandingStatus.yourTurn);

      await tester.tap(find.byKey(const ValueKey('play-truth_or_dare')));
      await tester.pump();
      expect(opened, [('truth_or_dare', null), ('truth_or_dare', 's1')]);

      // Opening one session directly, from a chat card or the hub.
      await const LegacyGameController(
        'truth_or_dare',
      ).openSession(probeContext, probeRef, sessionId: 's9');
      expect(opened.last, ('truth_or_dare', 's9'));
    },
  );

  testWidgets('a game that is over starts a new one, not the old session', (
    tester,
  ) async {
    // A landing state can carry the id of a session that is over. Only a
    // live session is resumed; the status decides, not the id.
    await pumpProbes(tester);
    const controller = LegacyGameController('truth_or_dare');
    const expected = {
      GameLandingStatus.invited: 's1',
      GameLandingStatus.yourTurn: 's1',
      GameLandingStatus.waiting: 's1',
      GameLandingStatus.fresh: null,
      GameLandingStatus.finished: null,
    };
    for (final entry in expected.entries) {
      opened.clear();
      await controller.onPrimary(
        probeContext,
        probeRef,
        GameLandingState(status: entry.key, sessionId: 's1'),
      );
      expect(opened, [('truth_or_dare', entry.value)], reason: '${entry.key}');
    }
  });

  testWidgets('a partner\'s move refreshes it', (tester) async {
    await pumpProbes(tester);
    expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);

    // The partner starts a game: the server's list changes, and an event
    // says so.
    activeRows = [row('s1', 'truth_or_dare', initiator: 'partner')];
    cards = {'s1': card('invited')};
    events.add(null);
    // The event, the refetched list, then the new session's card.
    await tester.pumpAndSettle();

    expect(seen['truth_or_dare']!.status, GameLandingStatus.invited);
    expect(seen['truth_or_dare']!.sessionId, 's1');
  });

  testWidgets('coming back to the page re-reads the list', (tester) async {
    await pumpProbes(tester);
    expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);

    // A game was started from a screen this page opened, and no event
    // reached the list.
    activeRows = [row('s1', 'truth_or_dare')];
    cards = {'s1': card('active', turn: 'me')};
    await tester.pumpAndSettle();
    // The control: without being told, the list is not fetched again.
    expect(seen['truth_or_dare']!.status, GameLandingStatus.fresh);

    const LegacyGameController('truth_or_dare').onResume(probeRef);
    // The refetched list, then the new session's card.
    await tester.pumpAndSettle();

    expect(seen['truth_or_dare']!.status, GameLandingStatus.yourTurn);
    expect(seen['truth_or_dare']!.sessionId, 's1');
  });
}
