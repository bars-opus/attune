import 'dart:io';

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

    test('is populated when the row has fetchRounds\' exact column shape',
        () {
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

    test('fetchRounds selects active_partner_id and no answer columns', () {
      // Asserts against the repository's real select string rather than
      // a hand-copied key list, so a select-list regression is actually
      // caught here. This is what would have caught the missing
      // active_partner_id column fixed in commit 75c978d5: that bug was
      // invisible to a test that only exercised fromRow in isolation.
      final source = File(
        'lib/features/games/session_games/data/repositories/session_game_repository.dart',
      ).readAsStringSync();

      final fetchRoundsIndex = source.indexOf('Future<List<SessionGameRound>> fetchRounds(');
      expect(fetchRoundsIndex, isNot(-1),
          reason: 'fetchRounds method not found in session_game_repository.dart');

      // Scope to this method's body only, so we can't accidentally match
      // fetchQuestions' unrelated .select() call further up the file.
      final nextMethodIndex = source.indexOf('\n  Future<', fetchRoundsIndex + 1);
      final methodBody = nextMethodIndex == -1
          ? source.substring(fetchRoundsIndex)
          : source.substring(fetchRoundsIndex, nextMethodIndex);

      // Whitespace-tolerant: dart format wraps .select( onto its own
      // line once the column list grows, and a single-line pattern then
      // stops matching code that is perfectly correct.
      final selectMatch = RegExp(
        r"\.select\(\s*'([^']*)'\s*,?\s*\)",
        dotAll: true,
      ).firstMatch(methodBody);
      expect(selectMatch, isNotNull,
          reason: 'fetchRounds does not call .select(\'...\') with an explicit column list');

      final selectList = selectMatch!.group(1)!;
      expect(selectList, contains('active_partner_id'));
      expect(selectList, isNot(contains('answer_a')));
      expect(selectList, isNot(contains('answer_b')));
    });

    test('still carries no answer fields', () {
      // Regression guard on the reveal gate: a round model that could
      // hold answers would invite a direct table select, which RLS
      // permits and the gate never sees. Asserts on the parsed object's
      // actual fields — not on toString(), which SessionGameRound does
      // not override and which would stay trivially true even if an
      // answer-carrying field were added.
      const answerA = 'leaked-a';
      const answerB = 'leaked-b';
      final round = SessionGameRound.fromRow(const {
        'id': 'r3',
        'round_number': 3,
        'question_id': 'q3',
        'both_answered': false,
        'active_partner_id': 'user-a',
        'answer_a': answerA,
        'answer_b': answerB,
      });

      // Each of the model's five real fields holds exactly what was
      // passed for its own key...
      expect(round.id, 'r3');
      expect(round.roundNumber, 3);
      expect(round.questionId, 'q3');
      expect(round.bothAnswered, false);
      expect(round.subjectId, 'user-a');

      // ...and none of them holds a planted answer value.
      final fieldValues = <Object?>[
        round.id,
        round.roundNumber,
        round.questionId,
        round.bothAnswered,
        round.subjectId,
      ];
      expect(fieldValues, isNot(contains(answerA)));
      expect(fieldValues, isNot(contains(answerB)));

      // The above only inspects the five fields this test already knows
      // about — it cannot see a brand-new field by construction, since
      // Dart has no reflection available here to enumerate an object's
      // fields at runtime. So also assert directly on the model's
      // source: it must declare no field or fromRow assignment that
      // carries an answer. This is what actually fails if someone adds
      // an `answerA` field populated from row['answer_a'].
      final modelSource = File(
        'lib/features/games/session_games/data/models/session_game_round.dart',
      ).readAsStringSync();

      final classIndex = modelSource.indexOf('class SessionGameRound');
      expect(classIndex, isNot(-1),
          reason: 'SessionGameRound class not found in session_game_round.dart');
      // Exclude the file's leading doc comment, which legitimately
      // discusses "answer_a"/"answer_b" in prose when explaining why
      // they're absent.
      final classBody = modelSource.substring(classIndex);

      final forbidden = RegExp(
        r'answer[_]?[aAbB]\b',
        caseSensitive: false,
      );
      expect(
        forbidden.hasMatch(classBody),
        isFalse,
        reason:
            'SessionGameRound must not declare or assign any answer-carrying '
            'field (found a match for $forbidden in the class body)',
      );
    });
  });
}
