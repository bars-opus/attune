import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionGameQuestion.fromRow', () {
    test('parses a sliding_scale row with its anchors', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q1',
        'game_type': 'sliding_scale',
        'question_text': 'How much of our money should be shared?',
        'value_domain': 'money',
        'scale_low': 'Kept separate',
        'scale_high': 'Fully shared',
      });
      expect(q.gameType, 'sliding_scale');
      expect(q.valueDomain, 'money');
      expect(q.scaleLow, 'Kept separate');
      expect(q.scaleHigh, 'Fully shared');
      expect(q.options, isEmpty);
    });

    test('parses a scenario row with its options', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q2',
        'game_type': 'scenario',
        'question_text': 'You are both tired and a disagreement starts.',
        'options': [
          {'key': 'a', 'text': 'Push through'},
          {'key': 'b', 'text': 'Pause'},
          {'key': 'c', 'text': 'Step away'},
        ],
      });
      expect(q.options.length, 3);
      expect(q.options.first.key, 'a');
      expect(q.options.first.text, 'Push through');
    });

    test('parses a mirror row, which has neither anchors nor options', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q3',
        'game_type': 'mirror',
        'question_text': 'What is weighing on them most this week?',
      });
      expect(q.gameType, 'mirror');
      expect(q.options, isEmpty);
      expect(q.scaleLow, isNull);
    });

    test('malformed options degrade to empty rather than throwing', () {
      // The column is jsonb; a row written by hand or by a future
      // migration could hold a shape this parser does not expect. A
      // throw here would take down the whole question list.
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q4',
        'game_type': 'scenario',
        'question_text': 'Broken',
        'options': 'not-an-array',
      });
      expect(q.options, isEmpty);
    });

    test('an option missing its text is dropped, not rendered blank', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q5',
        'game_type': 'scenario',
        'question_text': 'Partial',
        'options': [
          {'key': 'a', 'text': 'Fine'},
          {'key': 'b'},
        ],
      });
      expect(q.options.length, 1);
      expect(q.options.first.key, 'a');
    });
  });
}
