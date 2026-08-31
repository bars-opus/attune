import 'package:attune/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart';

/// The sentinel written into the NON-active partner's answer slot.
///
/// Truth or Dare alternates turns (TRUTH_OR_DARE.md §2.2), so only one
/// partner answers a round. The other slot is filled with this so
/// both_answered fires for a legitimately one-sided round — it is not a
/// real answer and must never be shown or measured as one.
const String kTruthOrDareRevealed = '__revealed__';

/// Picks the round to feature on the end screen.
///
/// Deterministic and AI-free, per TRUTH_OR_DARE.md §"Most interesting
/// pick": the longest Truth answer, else the first Dare, else the round a
/// skip happened in, else the first round. Longer answers stand in for
/// engagement, which is why length decides rather than recency.
///
/// Extracted from TruthOrDareSessionRouterScreen so it can be tested
/// without a widget tree.
class TruthOrDareScoringService {
  const TruthOrDareScoringService();

  /// The real answer for a round, or null if neither partner wrote one.
  ///
  /// Skips the reveal sentinel: treating it as an answer would let it win
  /// "longest answer" on a session where nobody said much.
  String? roundAnswer(TruthOrDareRound round) {
    final answers =
        [round.answerA, round.answerB]
            .whereType<String>()
            .where((value) => value.isNotEmpty && value != kTruthOrDareRevealed)
            .toList();
    return answers.isEmpty ? null : answers.first;
  }

  Map<String, dynamic> mostInterestingPick(List<TruthOrDareRound> rounds) {
    final truthRounds =
        rounds.where((round) {
          if (round.questionType != 'truth') return false;
          final answer = roundAnswer(round);
          return answer != null && answer.isNotEmpty;
        }).toList();

    if (truthRounds.isNotEmpty) {
      truthRounds.sort((a, b) {
        final aAnswer = roundAnswer(a) ?? '';
        final bAnswer = roundAnswer(b) ?? '';
        return aAnswer.length.compareTo(bAnswer.length);
      });
      final round = truthRounds.last;
      return {'text': round.questionText, 'answer': roundAnswer(round) ?? ''};
    }

    for (final round in rounds) {
      if (round.questionType == 'dare') {
        return {'text': round.questionText};
      }
    }

    for (final round in rounds) {
      if (round.isSkip) {
        return {'text': round.questionText};
      }
    }

    return rounds.isEmpty
        ? <String, dynamic>{}
        : {'text': rounds.first.questionText};
  }
}
