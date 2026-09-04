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

    test('rejects an incomplete answer set rather than scoring it', () {
      // A partial submission must not be scored: six answers out of seven
      // would produce a number that looks like a readiness score and is
      // not one. The gate depends on the instrument being complete.
      expect(
        () => ReadinessScoringService.calculateScore({
          'q1': 5,
          'q2': 5,
          'q3': 5,
          'q4': 5,
          'q5': 5,
          'q6': 5,
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects out-of-range answers', () {
      // Answers are 1-5. A 9 would inflate the score past the threshold,
      // so it is dropped, which leaves the set incomplete and throws.
      expect(
        () => ReadinessScoringService.calculateScore({
          'q1': 9,
          'q2': 5,
          'q3': 5,
          'q4': 5,
          'q5': 5,
          'q6': 5,
          'q7': 5,
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('a high score still fails inside the eight-week window', () {
      // Both gates are independent and both must hold. This is the one an
      // impatient user hits: they feel ready, and the clock disagrees.
      expect(
        ReadinessScoringService.isEligibleForDating(
          score: 100,
          breakupAt: DateTime.now().subtract(const Duration(days: 55)),
        ),
        isFalse,
      );
    });

    test('the eight-week boundary is inclusive on the far side', () {
      expect(
        ReadinessScoringService.isEligibleForDating(
          score: 71,
          breakupAt: DateTime.now().subtract(const Duration(days: 57)),
        ),
        isTrue,
      );
    });

    test('the retake date is a week after the attempt', () {
      final attempt = DateTime(2026, 3, 1);
      expect(
        ReadinessScoringService.getNextRetakeDate(attempt),
        DateTime(2026, 3, 8),
      );
    });

    test('a sub-threshold result never names a date', () {
      // Copy check: someone who did not pass must not be handed a countdown
      // to when they will. The message points at the work, not the clock.
      final message = ReadinessScoringService.getResultMessage(
        40,
        DateTime.now().subtract(const Duration(days: 400)),
      );
      expect(message, isNot(contains('until')));
    });
  });
}
