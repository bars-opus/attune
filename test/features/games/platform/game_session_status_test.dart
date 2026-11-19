import 'dart:async';

import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_session_status.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

GameCardState card({
  required String status,
  String? currentTurnUserId,
  int? currentRound,
  int? totalRounds,
  bool? viewerAnswered,
  bool? partnerAnswered,
}) {
  return GameCardState(
    gameType: 'this_or_that',
    status: status,
    currentTurnUserId: currentTurnUserId,
    winnerUserId: null,
    currentRound: currentRound,
    totalRounds: totalRounds,
    viewerAnswered: viewerAnswered,
    partnerAnswered: partnerAnswered,
  );
}

GameLandingState map(GameCardState c, {bool viewerStarted = true}) {
  return landingStateFromCard(
    card: c,
    sessionId: 's1',
    viewerId: 'me',
    viewerStarted: viewerStarted,
    partnerName: 'Ama',
  );
}

void expectState(GameLandingState state, GameLandingStatus status) {
  expect(state.status, status);
  expect(state.sessionId, 's1');
  expect(state.partnerName, 'Ama');
}

void main() {
  group('landingStateFromCard', () {
    test('an invitation you sent is waiting on your partner', () {
      expectState(
        map(card(status: 'invited'), viewerStarted: true),
        GameLandingStatus.waiting,
      );
    });

    test('an invitation your partner sent is yours to join', () {
      expectState(
        map(card(status: 'invited'), viewerStarted: false),
        GameLandingStatus.invited,
      );
    });

    test('a turn that is yours is your turn', () {
      expectState(
        map(card(status: 'active', currentTurnUserId: 'me')),
        GameLandingStatus.yourTurn,
      );
    });

    test("a turn that is your partner's is waiting", () {
      expectState(
        map(card(status: 'active', currentTurnUserId: 'partner')),
        GameLandingStatus.waiting,
      );
    });

    test('with no turn, having answered before your partner is waiting', () {
      expectState(
        map(
          card(status: 'active', viewerAnswered: true, partnerAnswered: false),
        ),
        GameLandingStatus.waiting,
      );
    });

    test('with no turn, a round you have not answered is your turn', () {
      expectState(
        map(
          card(status: 'active', viewerAnswered: false, partnerAnswered: true),
        ),
        GameLandingStatus.yourTurn,
      );
    });

    test('a completed game is finished', () {
      expectState(map(card(status: 'completed')), GameLandingStatus.finished);
    });

    test('any other status is a fresh start', () {
      expectState(map(card(status: 'abandoned')), GameLandingStatus.fresh);
    });

    test('unknown answers still let the player in', () {
      // The round-state read can fail; a wrong "waiting" would lock the game shut.
      final state = landingStateFromCard(
        card: card(status: 'active'),
        sessionId: 's1',
        viewerId: 'me',
        viewerStarted: true,
      );
      expect(state.status, GameLandingStatus.yourTurn);

      // Only the partner's answer unknown: still not certain they owe a move.
      expect(
        map(card(status: 'active', viewerAnswered: true)).status,
        GameLandingStatus.yourTurn,
      );
    });

    test('round zero is not shown as a round', () {
      expect(
        map(card(status: 'active', currentRound: 0, totalRounds: 10)).caption,
        isNull,
      );
      expect(
        map(card(status: 'active', currentRound: 3, totalRounds: 10)).caption,
        'Round 3 of 10',
      );
    });
  });

  testWidgets('watchSessionLanding is loading until the card arrives', (
    tester,
  ) async {
    useSurface(tester, phone);
    final cards = StreamController<GameCardState?>();
    addTearDown(cards.close);
    late GameLandingState seen;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me'),
          gamePartnerNameProvider.overrideWith((ref) async => 'Ama'),
          gameCardProvider.overrideWith((ref, id) => cards.stream),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            seen = watchSessionLanding(ref, sessionId: 's1', initiatorId: 'me');
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen.status, GameLandingStatus.loading);
    expect(seen.sessionId, 's1');

    cards.add(card(status: 'invited'));
    await tester.pump();

    // The viewer is the initiator, so their own invitation waits on Ama.
    expect(seen.status, GameLandingStatus.waiting);
    expect(seen.sessionId, 's1');
    expect(seen.partnerName, 'Ama');
  });
}
