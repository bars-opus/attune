import 'package:attune/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart';
import 'package:attune/features/games/truth_or_dare/domain/services/truth_or_dare_scoring_service.dart';
import 'package:flutter_test/flutter_test.dart';

TruthOrDareRound _round({
  required int number,
  required String type,
  String text = 'q',
  String? answerA,
  String? answerB,
  bool isSkip = false,
}) => TruthOrDareRound(
  id: 'r$number',
  sessionId: 's1',
  roundNumber: number,
  questionId: 'q$number',
  questionType: type,
  questionText: text,
  answerA: answerA,
  answerB: answerB,
  isSkip: isSkip,
);

void main() {
  const scoring = TruthOrDareScoringService();

  group('the round answer', () {
    test('ignores the reveal sentinel', () {
      // Turns alternate, so the non-active partner's slot holds a sentinel
      // rather than an answer. Counting it would let '__revealed__' win
      // "longest answer" in a session where nobody wrote much.
      final round = _round(
        number: 1,
        type: 'truth',
        answerA: kTruthOrDareRevealed,
        answerB: 'the real answer',
      );
      expect(scoring.roundAnswer(round), 'the real answer');
    });

    test('is null when neither partner answered', () {
      expect(scoring.roundAnswer(_round(number: 1, type: 'truth')), isNull);
    });
  });

  group('the most interesting pick (TRUTH_OR_DARE.md §"deterministic")', () {
    test('is the LONGEST truth answer, not the first or the latest', () {
      final rounds = [
        _round(number: 1, type: 'truth', text: 'short', answerA: 'no'),
        _round(
          number: 2,
          type: 'truth',
          text: 'longest',
          answerB: 'a considerably longer and more vulnerable answer',
        ),
        _round(number: 3, type: 'truth', text: 'middling', answerA: 'a bit'),
      ];
      expect(scoring.mostInterestingPick(rounds)['text'], 'longest');
    });

    test('the pick carries the answer text, not just the question', () {
      final rounds = [
        _round(number: 1, type: 'truth', text: 'q', answerA: 'my answer'),
      ];
      expect(scoring.mostInterestingPick(rounds)['answer'], 'my answer');
    });

    test('an unanswered truth cannot win', () {
      // A truth round with no answer has nothing to feature.
      final rounds = [
        _round(number: 1, type: 'truth', text: 'unanswered'),
        _round(number: 2, type: 'dare', text: 'the dare'),
      ];
      expect(scoring.mostInterestingPick(rounds)['text'], 'the dare');
    });

    test('falls back to the FIRST dare when no truth was answered', () {
      final rounds = [
        _round(number: 1, type: 'dare', text: 'first dare'),
        _round(number: 2, type: 'dare', text: 'second dare'),
      ];
      expect(scoring.mostInterestingPick(rounds)['text'], 'first dare');
    });

    test('falls back to a skip round when there are no dares either', () {
      final rounds = [
        _round(number: 1, type: 'truth', text: 'unanswered'),
        _round(number: 2, type: 'truth', text: 'the skip', isSkip: true),
      ];
      expect(scoring.mostInterestingPick(rounds)['text'], 'the skip');
    });

    test('falls back to the first round when nothing else applies', () {
      final rounds = [
        _round(number: 1, type: 'truth', text: 'first'),
        _round(number: 2, type: 'truth', text: 'second'),
      ];
      expect(scoring.mostInterestingPick(rounds)['text'], 'first');
    });

    test('an empty session returns nothing rather than throwing', () {
      expect(scoring.mostInterestingPick(const []), isEmpty);
    });
  });
}
