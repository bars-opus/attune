import 'dart:io';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the card provider is autoDispose', () {
    // A chat page loads 50 messages. Without autoDispose, every game card
    // ever scrolled past keeps a websocket subscription open for the rest
    // of the session -- all of them still streaming, none of them visible.
    //
    // Asserted on the provider's type rather than by observing a socket:
    // the leak is structural, and the type is what prevents it.
    // The type is the guarantee: a plain StreamProvider.family would be
    // StreamProvider<...>, not AutoDisposeStreamProvider<...>.
    expect(
      gameCardProvider('session-1'),
      isA<AutoDisposeStreamProvider<GameCardState?>>(),
      reason:
          'a non-autoDispose family holds one subscription per session for '
          'the life of the app',
    );
  });

  test('each session gets its own provider instance', () {
    // .family keys by argument: two cards for the same session must share
    // one subscription, and two different sessions must not collide.
    expect(gameCardProvider('a'), equals(gameCardProvider('a')));
    expect(gameCardProvider('a'), isNot(equals(gameCardProvider('b'))));
  });

  test('GameCardState.fromRow tolerates a partial row', () {
    // game_sessions carries columns that only some games populate --
    // current_turn_user_id is null for games where both partners answer
    // each round, winner_user_id for games nobody wins. A missing column
    // must not throw while a card is rendering mid-scroll.
    final state = GameCardState.fromRow(const {'game_type': 'mirror'});

    expect(state.gameType, 'mirror');
    expect(state.status, '');
    expect(state.currentTurnUserId, isNull);
    expect(state.winnerUserId, isNull);
    expect(state.currentRound, isNull);
  });

  test('fromRow reads the fields the card actually renders', () {
    final state = GameCardState.fromRow(const {
      'game_type': 'paint_ball',
      'status': 'active',
      'current_turn_user_id': 'u1',
      'winner_user_id': null,
      'current_round': 2,
      'total_rounds': 7,
    });

    expect(state.status, 'active');
    expect(state.currentTurnUserId, 'u1');
    expect(state.currentRound, 2);
    expect(state.totalRounds, 7);
  });

  test('the card actually fetches per-round state for session games', () {
    // GameCardState had viewerAnswered/partnerAnswered and a
    // withRoundState() helper, and gameCardLabel had fully tested
    // branches for both -- but NOTHING called the RPC. The fields were
    // always null, so every session game fell through to "Round 1 of 8"
    // no matter who had answered.
    //
    // Every unit test passed throughout: the label logic was correct in
    // isolation and the wiring was simply absent. This asserts the seam
    // between them.
    final source =
        File(
          'lib/features/games/presentation/providers/game_card_provider.dart',
        ).readAsStringSync();

    expect(
      source.contains('session_game_round_state'),
      isTrue,
      reason:
          'without this call viewerAnswered is always null and the card '
          'can never say whose move it is',
    );
    expect(
      source.contains('withRoundState('),
      isTrue,
      reason: 'the fetched state must reach the card state',
    );
    expect(
      source.contains('.asyncMap('),
      isTrue,
      reason: 'a plain .map cannot await the round-state fetch',
    );
  });
}
