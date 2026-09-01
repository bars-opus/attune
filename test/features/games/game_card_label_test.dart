import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/widgets/game_message_bubble.dart';
import 'package:flutter_test/flutter_test.dart';

GameCardState _state({
  String status = 'active',
  String? turn,
  String? winner,
  int? round,
  int? total,
}) {
  return GameCardState(
    gameType: 'mirror',
    status: status,
    currentTurnUserId: turn,
    winnerUserId: winner,
    currentRound: round,
    totalRounds: total,
  );
}

void main() {
  const me = 'user-me';
  const them = 'user-them';

  group('gameCardLabel', () {
    test('an invite reads differently to each side', () {
      // The single most important property: one row, two readings. The
      // sender is waiting; the recipient is being asked to play. Getting
      // this backwards would tell the wrong person to take a turn.
      expect(
        gameCardLabel(
          state: _state(status: 'invited'),
          viewerId: me,
          viewerIsSender: true,
        ),
        'Waiting for them',
      );
      expect(
        gameCardLabel(
          state: _state(status: 'invited'),
          viewerId: them,
          viewerIsSender: false,
        ),
        "Let's play!",
      );
    });

    test('an active turn reads from the viewer, not the sender', () {
      // viewerIsSender is deliberately the SAME in both calls: whose turn
      // it is must come from current_turn_user_id, never from who started
      // the game. A sender who moved first would otherwise permanently
      // read "Your move".
      expect(
        gameCardLabel(
          state: _state(turn: me),
          viewerId: me,
          viewerIsSender: true,
        ),
        'Your move',
      );
      expect(
        gameCardLabel(
          state: _state(turn: them),
          viewerId: me,
          viewerIsSender: true,
        ),
        'Their move',
      );
    });

    test('a win reads as a win only for the winner', () {
      expect(
        gameCardLabel(
          state: _state(status: 'completed', winner: me),
          viewerId: me,
          viewerIsSender: false,
        ),
        'You won!',
      );
      expect(
        gameCardLabel(
          state: _state(status: 'completed', winner: them),
          viewerId: me,
          viewerIsSender: false,
        ),
        'You lost',
      );
    });

    test('a completed game with no winner is finished, not lost', () {
      // 36 Questions and the session games simply end -- nobody wins. A
      // null winner must not read as a loss to both partners.
      expect(
        gameCardLabel(
          state: _state(status: 'completed'),
          viewerId: me,
          viewerIsSender: true,
        ),
        'Finished',
      );
    });

    test('a turnless active game shows progress instead of a turn', () {
      // Games where both partners answer each round carry no
      // current_turn_user_id. "Their move" would be wrong for both.
      expect(
        gameCardLabel(
          state: _state(round: 3, total: 9),
          viewerId: me,
          viewerIsSender: false,
        ),
        'Round 3 of 9',
      );
    });

    test('a turnless game with no round data still says something', () {
      expect(
        gameCardLabel(
          state: _state(),
          viewerId: me,
          viewerIsSender: false,
        ),
        'In progress',
      );
    });

    test('an abandoned game reads as ended', () {
      expect(
        gameCardLabel(
          state: _state(status: 'abandoned'),
          viewerId: me,
          viewerIsSender: true,
        ),
        'Ended',
      );
    });
  });
}
