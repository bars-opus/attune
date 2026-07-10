// lib/features/quiz/domain/services/communication_style_scoring_service.dart

import '../models/communication_style_result.dart';
import '../../data/communication_style_questions.dart';

class CommunicationStyleScoringService {
  static const List<String> _dimensions = [
    'assertive',
    'passive',
    'aggressive',
    'passive_aggressive',
  ];

  static const Map<String, int> _canonicalOrder = {
    'assertive': 0,
    'passive': 1,
    'aggressive': 2,
    'passive_aggressive': 3,
  };

  /// Pure function: calculates scores from raw answers
  /// Returns CommunicationStyleResult with deterministic ordering
  static CommunicationStyleResult calculateScore(Map<int, int?> answers) {
    // Validate input
    _validateAnswers(answers);

    final allQuestions = CommunicationStyleQuestions.getAllQuestions();

    // Group answers by dimension
    final dimensionScores = <String, List<int>>{};
    for (final dim in _dimensions) {
      dimensionScores[dim] = [];
    }

    for (int i = 0; i < allQuestions.length; i++) {
      final answer = answers[i];
      if (answer == null) {
        throw Exception('Missing answer for question $i');
      }
      final dimension = allQuestions[i].dimension;
      dimensionScores[dimension]!.add(answer);
    }

    // Calculate independent dimension scores (0-100)
    final rawScores = <String, int>{};
    for (final entry in dimensionScores.entries) {
      final scores = entry.value;
      final mean = scores.reduce((a, b) => a + b) / scores.length;
      final score = _normalizeTo100(mean);
      rawScores[entry.key] = score;
    }

    // Determine primary and secondary with deterministic tie-breaking
    final sorted = rawScores.entries.toList()..sort((a, b) {
      // Sort by score descending, then by canonical order
      if (a.value != b.value) {
        return b.value.compareTo(a.value);
      }
      return _canonicalOrder[a.key]!.compareTo(_canonicalOrder[b.key]!);
    });

    final primary = sorted[0].key;
    final secondary = sorted.length > 1 ? sorted[1].key : primary;
    final separation = sorted[0].value - (sorted.length > 1 ? sorted[1].value : 0);

    return CommunicationStyleResult(
      assertive: rawScores['assertive']!,
      passive: rawScores['passive']!,
      aggressive: rawScores['aggressive']!,
      passiveAggressive: rawScores['passive_aggressive']!,
      primary: primary,
      secondary: secondary,
      separation: separation,
      instrumentVersion: CommunicationStyleQuestions.instrumentVersion,
      resultVersion: 1,
      completedAt: null,
    );
  }

  static int _normalizeTo100(double mean) {
    // mean is between 1.0 and 7.0
    // Convert to 0-100: ((mean - 1) / 6) * 100
    final normalized = ((mean - 1) / 6) * 100;
    return normalized.round().clamp(0, 100);
  }

  static void _validateAnswers(Map<int, int?> answers) {
    const totalQuestions = 20;

    // Check all questions answered
    for (int i = 0; i < totalQuestions; i++) {
      final answer = answers[i];
      if (answer == null) {
        throw Exception('Missing answer for question $i');
      }
      if (answer < 1 || answer > 7) {
        throw Exception('Invalid answer value for question $i: $answer');
      }
    }

    // Check no extra keys
    for (final key in answers.keys) {
      if (key < 0 || key >= totalQuestions) {
        throw Exception('Invalid question index: $key');
      }
    }
  }

  /// Check if a result exists in a profile
  static bool hasResult(Map<String, dynamic>? profile) {
    return profile != null &&
        profile['communication_style'] != null &&
        (profile['communication_style'] as Map<String, dynamic>?)?.isNotEmpty == true;
  }
}
