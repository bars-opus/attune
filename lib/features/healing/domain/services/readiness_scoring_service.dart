// lib/features/healing/domain/services/readiness_scoring_service.dart

class ReadinessScoringService {
  static const String scoringVersion = 'healing_readiness_v1_1';
  static const int minimumScore = 71;
  static const int minimumWeeks = 8;

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

  /// Check if the user is eligible for Dating Mode
  static bool isEligibleForDating({
    required int score,
    required DateTime breakupAt,
  }) {
    if (score < minimumScore) return false;

    final now = DateTime.now();
    final weeksSinceBreakup = now.difference(breakupAt).inDays / 7;
    if (weeksSinceBreakup < minimumWeeks) return false;

    return true;
  }

  /// Get the date when 8 weeks have passed
  static DateTime getEligibilityDate(DateTime breakupAt) {
    return breakupAt.add(Duration(days: minimumWeeks * 7));
  }

  /// Get the next retake date (7 days after last attempt)
  static DateTime getNextRetakeDate(DateTime lastAttemptAt) {
    return lastAttemptAt.add(const Duration(days: 7));
  }

  /// Get result message based on score
  static String getResultMessage(int score, DateTime breakupAt) {
    if (score < minimumScore) {
      return 'Your answers suggest there may be more you want to explore. Go at your own pace.';
    }

    if (!isEligibleForDating(score: score, breakupAt: breakupAt)) {
      final eligibilityDate = getEligibilityDate(breakupAt);
      return 'Your check-in is complete. Dating Mode remains unavailable until ${_formatDate(eligibilityDate)}.';
    }

    return 'You can choose whether to explore Dating Mode when it becomes available.';
  }

  static String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  static String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
