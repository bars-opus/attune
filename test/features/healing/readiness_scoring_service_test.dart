import 'package:attune/features/healing/domain/services/readiness_scoring_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadinessScoringService', () {
    test('returns 0 when every answer is 1', () {
      final score = ReadinessScoringService.calculateScore({
        'q1': 1,
        'q2': 1,
        'q3': 1,
        'q4': 1,
        'q5': 1,
        'q6': 1,
        'q7': 1,
      });

      expect(score, 0);
    });

    test('returns 100 when every answer is 5', () {
      final score = ReadinessScoringService.calculateScore({
        'q1': 5,
        'q2': 5,
        'q3': 5,
        'q4': 5,
        'q5': 5,
        'q6': 5,
        'q7': 5,
      });

      expect(score, 100);
    });

    test('uses the v1.1 answer minus one formula', () {
      final score = ReadinessScoringService.calculateScore({
        'q1': 3,
        'q2': 3,
        'q3': 3,
        'q4': 3,
        'q5': 3,
        'q6': 3,
        'q7': 3,
      });

      expect(score, 50);
    });

    test('does not allow score 70 to qualify', () {
      final eligible = ReadinessScoringService.isEligibleForDating(
        score: 70,
        breakupAt: DateTime.now().subtract(const Duration(days: 56)),
      );

      expect(eligible, isFalse);
    });

    test('requires eight weeks as a separate gate', () {
      final eligible = ReadinessScoringService.isEligibleForDating(
        score: 71,
        breakupAt: DateTime.now().subtract(const Duration(days: 55)),
      );

      expect(eligible, isFalse);
    });
  });
}
