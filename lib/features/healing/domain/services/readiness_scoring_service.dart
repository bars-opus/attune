// lib/features/healing/domain/services/readiness_scoring_service.dart

/// Healing's readiness check-in: Healing's own private reflection. Spec 2
/// W2 (§2.1): it never decides anything about Dating.
class ReadinessScoringService {
  static const String scoringVersion = 'healing_readiness_v1_1';

  /// From this score the result says the check-in is complete; below it,
  /// that there may be more to explore (the same words as the server's
  /// submit_healing_readiness).
  static const int minimumScore = 71;

  static int calculateScore(Map<String, dynamic> answers) {
    final scores = <int>[];
    for (int i = 1; i <= 7; i++) {
      final key = 'q$i';
      if (answers.containsKey(key)) {
        final value = answers[key];
        if (value is int && value >= 1 && value <= 5) {
          scores.add(value);
        }
      }
    }

    if (scores.length != 7) {
      throw Exception('Incomplete readiness answers: ${scores.length}/7');
    }

    final sum = scores.fold(0, (a, b) => a + (b - 1));
    final score = (100 * sum / 28).round();

    return score.clamp(0, 100);
  }

  /// Get the next retake date (7 days after last attempt)
  static DateTime getNextRetakeDate(DateTime lastAttemptAt) {
    return lastAttemptAt.add(const Duration(days: 7));
  }

  /// The words after a check-in: never a Dating date (Spec 2 W2).
  static String getResultMessage(int score) {
    if (score < minimumScore) {
      return 'Your answers suggest there may be more you want to explore. Go at your own pace.';
    }

    return 'Your check-in is complete. Healing stays here whenever you want it.';
  }
}
