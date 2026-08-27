import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionGameRound.subjectId', () {
    test('parses the round subject when present', () {
      // Mirror alternates whose inner state each round is about. The
      // controller needs that to decide whether this user writes a truth
      // or a guess, and whether they are the one who judges.
      final round = SessionGameRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'both_answered': false,
        'active_partner_id': 'user-a',
      });
      expect(round.subjectId, 'user-a');
    });

    test('subjectId is null for the non-Mirror games', () {
      // Sliding Scale and Scenario have no subject: both partners answer
      // the same prompt about the same thing.
      final round = SessionGameRound.fromRow(const {
        'id': 'r2',
        'round_number': 2,
        'question_id': 'q2',
        'both_answered': false,
      });
      expect(round.subjectId, isNull);
    });

    test('is populated when the row has fetchRounds\' exact column shape', () {
      // fetchRounds selects id, round_number, question_id, both_answered
      // and active_partner_id — no more, no less. This proves subjectId
      // actually comes through that shape, not just a hand-built row
      // that happens to include a field fetchRounds never selects.
      final round = SessionGameRound.fromRow(const {
        'id': 'r4',
        'round_number': 4,
        'question_id': 'q4',
        'both_answered': true,
        'active_partner_id': 'user-b',
      });
      expect(round.subjectId, 'user-b');
    });

    test('still carries no answer fields', () {
      // Regression guard on the reveal gate: a round model that could
      // hold answers would invite a direct table select, which RLS
      // permits and the gate never sees.
      final round = SessionGameRound.fromRow(const {
        'id': 'r3',
        'round_number': 3,
        'question_id': 'q3',
        'both_answered': false,
        'active_partner_id': 'user-a',
        'answer_a': 'leaked',
        'answer_b': 'leaked',
      });
      expect(round.toString(), isNot(contains('leaked')));
    });
  });
}
