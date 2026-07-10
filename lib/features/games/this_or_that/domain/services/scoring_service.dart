// lib/features/games/this_or_that/domain/services/scoring_service.dart

class ScoringService {
  /// Calculate the most interesting pick from a list of rounds
  /// Priority: first differing round > is_interesting flag > round 5
  Map<String, dynamic> getMostInterestingPick(List<Map<String, dynamic>> rounds) {
    // Find first differing round
    for (final round in rounds) {
      if (round['answer_a'] != round['answer_b'] && 
          round['answer_a'] != null && 
          round['answer_b'] != null) {
        return round;
      }
    }

    // Find round with is_interesting flag
    for (final round in rounds) {
      if (round['is_interesting'] == true) {
        return round;
      }
    }

    // Fallback to round 5 (index 4)
    return rounds.length > 4 ? rounds[4] : rounds[0];
  }

  /// Calculate match percentage
  double getMatchPercentage(int matchCount, int totalRounds) {
    if (totalRounds == 0) return 0.0;
    return (matchCount / totalRounds) * 100;
  }

  /// Get appropriate message for low match percentage (< 60%)
  String getLowMatchMessage() {
    return "You see things differently — that's what makes it interesting.";
  }
}
