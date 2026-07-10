// test/features/quiz/domain/services/conflict_style_scoring_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/services/conflict_style_scoring_service.dart';

void main() {
  group('ConflictStyleScoringService', () {
    test('All 1s produce five zero scores', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 1};

      final result = ConflictStyleScoringService.calculateScore(answers);

      expect(result.collaborating, 0);
      expect(result.competing, 0);
      expect(result.avoiding, 0);
      expect(result.accommodating, 0);
      expect(result.compromising, 0);
    });

    test('All 4s produce five 50 scores', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 4};

      final result = ConflictStyleScoringService.calculateScore(answers);

      expect(result.collaborating, 50);
      expect(result.competing, 50);
      expect(result.avoiding, 50);
      expect(result.accommodating, 50);
      expect(result.compromising, 50);
    });

    test('All 7s produce five 100 scores', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 7};

      final result = ConflictStyleScoringService.calculateScore(answers);

      expect(result.collaborating, 100);
      expect(result.competing, 100);
      expect(result.avoiding, 100);
      expect(result.accommodating, 100);
      expect(result.compromising, 100);
    });

    test('Scores are independent and not forced to sum to 100', () {
      final answers = {
        0: 6,
        1: 2,
        2: 2,
        3: 3,
        4: 5,
        5: 7,
        6: 2,
        7: 3,
        8: 4,
        9: 6,
        10: 7,
        11: 3,
        12: 2,
        13: 3,
        14: 6,
        15: 7,
        16: 3,
        17: 3,
      };

      final result = ConflictStyleScoringService.calculateScore(answers);

      final sum =
          result.collaborating +
          result.competing +
          result.avoiding +
          result.accommodating +
          result.compromising;
      expect(sum, isNot(100));
      expect(result.collaborating, 96);
      expect(result.competing, 25);
      expect(result.avoiding, 25);
      expect(result.accommodating, 39);
      expect(result.compromising, 78);
    });

    test('Tie-breaking is deterministic with canonical order', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 4};

      final result = ConflictStyleScoringService.calculateScore(answers);

      expect(result.primary, 'collaborating');
      expect(result.secondary, 'competing');
    });

    test('Separation == 0 produces tied copy', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 4};

      final result = ConflictStyleScoringService.calculateScore(answers);

      expect(result.isTied, true);
      expect(result.isMixed, false);
      expect(result.getSummary(), contains('tied'));
    });

    test('Separation between 0 and 10 produces mixed copy', () {
      final result = ConflictStyleResult(
        collaborating: 52,
        competing: 48,
        avoiding: 0,
        accommodating: 0,
        compromising: 0,
        primary: 'collaborating',
        secondary: 'competing',
        separation: 4,
      );

      expect(result.isMixed, true);
      expect(result.isTied, false);
      expect(result.getSummary(), contains('mixed pattern'));
    });

    test('Separation >= 10 produces clear copy', () {
      final result = ConflictStyleResult(
        collaborating: 96,
        competing: 25,
        avoiding: 25,
        accommodating: 39,
        compromising: 78,
        primary: 'collaborating',
        secondary: 'compromising',
        separation: 18,
      );

      expect(result.isMixed, false);
      expect(result.isTied, false);
      expect(result.getSummary(), contains('lean most toward'));
    });

    test('Missing answers are rejected', () {
      final answers = <int, int?>{for (var i = 0; i < 17; i++) i: 4};

      expect(
        () => ConflictStyleScoringService.calculateScore(answers),
        throwsArgumentError,
      );
    });

    test('Out-of-range answers are rejected', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 4};
      answers[7] = 8;

      expect(
        () => ConflictStyleScoringService.calculateScore(answers),
        throwsRangeError,
      );
    });

    test('Unknown question indexes are rejected', () {
      final answers = <int, int?>{for (var i = 0; i < 18; i++) i: 4};
      answers[18] = 4;

      expect(
        () => ConflictStyleScoringService.calculateScore(answers),
        throwsArgumentError,
      );
    });
  });
}
