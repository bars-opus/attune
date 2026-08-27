import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionGameRound.fromRow', () {
    test('parses a round that is not yet revealed', () {
      final round = SessionGameRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'both_answered': false,
      });
      expect(round.id, 'r1');
      expect(round.roundNumber, 1);
      expect(round.questionId, 'q1');
      expect(round.bothAnswered, isFalse);
    });

    test('parses a revealed round', () {
      final round = SessionGameRound.fromRow(const {
        'id': 'r2',
        'round_number': 2,
        'question_id': 'q2',
        'both_answered': true,
      });
      expect(round.bothAnswered, isTrue);
    });

    test('carries no answer fields at all', () {
      // The model deliberately has no answerA/answerB. Answers reach the
      // UI only via fetchRevealedRound's gated RPC — a round model that
      // could hold them would invite a caller to select them directly
      // from the table, which RLS would permit and the reveal gate would
      // not catch.
      final round = SessionGameRound.fromRow(const {
        'id': 'r3',
        'round_number': 3,
        'question_id': 'q3',
        'both_answered': false,
        'answer_a': 'leaked',
        'answer_b': 'leaked',
      });
      expect(round.toString(), isNot(contains('leaked')));
    });

    test('a missing both_answered defaults to false, never true', () {
      // Failing closed matters more than failing loud: a null read as
      // true would reveal both answers early.
      final round = SessionGameRound.fromRow(const {
        'id': 'r4',
        'round_number': 4,
        'question_id': 'q4',
      });
      expect(round.bothAnswered, isFalse);
    });
  });
}
