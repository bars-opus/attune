import 'package:attune/features/quiz/data/conflict_style_questions.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';

class ConflictStyleScoringService {
  static const List<String> _dimensions = [
    'collaborating',
    'competing',
    'avoiding',
    'accommodating',
    'compromising',
  ];

  static const Map<String, int> _canonicalOrder = {
    'collaborating': 0,
    'competing': 1,
    'avoiding': 2,
    'accommodating': 3,
    'compromising': 4,
  };

  /// Pure function: calculates scores from raw answers
  /// Returns ConflictStyleResult with deterministic ordering
  static ConflictStyleResult calculateScore(Map<int, int?> answers) {
    // Validate input
    _validateAnswers(answers);

    final allQuestions = ConflictStyleQuestions.getAllQuestions();

    // Group answers by dimension
    final dimensionScores = <String, List<int>>{};
    for (final dim in _dimensions) {
      dimensionScores[dim] = [];
    }

    for (int i = 0; i < allQuestions.length; i++) {
      final answer = answers[i];
      if (answer == null) {
        throw ArgumentError('Missing answer for question ${i + 1}');
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
    final sorted =
        rawScores.entries.toList()..sort((a, b) {
          // Sort by score descending, then by canonical order
          if (a.value != b.value) {
            return b.value.compareTo(a.value);
          }
          return _canonicalOrder[a.key]!.compareTo(_canonicalOrder[b.key]!);
        });

    final primary = sorted[0].key;
    final secondary = sorted.length > 1 ? sorted[1].key : primary;
    final separation =
        sorted[0].value - (sorted.length > 1 ? sorted[1].value : 0);

    return ConflictStyleResult(
      collaborating: rawScores['collaborating']!,
      competing: rawScores['competing']!,
      avoiding: rawScores['avoiding']!,
      accommodating: rawScores['accommodating']!,
      compromising: rawScores['compromising']!,
      primary: primary,
      secondary: secondary,
      separation: separation,
      instrumentVersion: ConflictStyleQuestions.instrumentVersion,
      resultVersion: 1,
      completedAt: null,
    );
  }

  static int _normalizeTo100(double mean) {
    final normalized = ((mean - 1) / 6) * 100;
    return normalized.round().clamp(0, 100);
  }

  static void _validateAnswers(Map<int, int?> answers) {
    const totalQuestions = 18;

    // Check all questions answered
    for (int i = 0; i < totalQuestions; i++) {
      final answer = answers[i];
      if (answer == null) {
        throw ArgumentError('Missing answer for question ${i + 1}');
      }
      if (answer < 1 || answer > 7) {
        throw RangeError.range(answer, 1, 7, 'question ${i + 1}');
      }
    }

    // Check no extra keys
    for (final key in answers.keys) {
      if (key < 0 || key >= totalQuestions) {
        throw ArgumentError('Invalid question index: $key');
      }
    }
  }
}
