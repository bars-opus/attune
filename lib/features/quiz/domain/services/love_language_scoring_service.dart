// lib/features/quiz/domain/services/love_language_scoring_service.dart

import '../models/love_language_result.dart';
import '../../data/love_language_questions.dart';

class LoveLanguageScoringService {
  static LoveLanguageResult calculateScore(Map<int, int?> answers) {
    // Step 1: Extract raw answers (ensure all 15 questions answered)
    final allQuestions = LoveLanguageQuestions.getAllQuestions();
    final Map<String, List<int>> dimensionScores = {
      'words': [],
      'quality_time': [],
      'gifts': [],
      'acts': [],
      'touch': [],
    };

    for (int i = 0; i < allQuestions.length; i++) {
      final answer = answers[i];
      if (answer == null) {
        throw Exception('Missing answer for question $i');
      }
      final dimension = allQuestions[i].dimension;
      dimensionScores[dimension]!.add(answer);
    }

    // Step 2: Calculate raw dimension averages (1.0 - 7.0)
    final rawScores = <String, double>{};
    for (final entry in dimensionScores.entries) {
      final scores = entry.value;
      rawScores[entry.key] = scores.reduce((a, b) => a + b) / scores.length;
    }

    // Step 3: Normalise to percentages
    final total = rawScores.values.reduce((a, b) => a + b);

    final percentages = <String, int>{};
    for (final entry in rawScores.entries) {
      percentages[entry.key] = ((entry.value / total) * 100).round();
    }

    // Step 4: Normalise to ensure sum is exactly 100
    var sum = percentages.values.reduce((a, b) => a + b);
    if (sum != 100) {
      final remainder = 100 - sum;
      final largestKey = percentages.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      percentages[largestKey] = percentages[largestKey]! + remainder;
    }

    // Step 5: Determine primary and secondary
    final sorted = percentages.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final primary = sorted[0].key;
    final secondary = sorted.length > 1 ? sorted[1].key : primary;

    return LoveLanguageResult(
      words: percentages['words'] ?? 0,
      qualityTime: percentages['quality_time'] ?? 0,
      gifts: percentages['gifts'] ?? 0,
      acts: percentages['acts'] ?? 0,
      touch: percentages['touch'] ?? 0,
      primary: primary,
      secondary: secondary,
      completedAt: DateTime.now(),
    );
  }
}
