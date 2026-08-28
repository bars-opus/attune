import 'package:attune/features/games/love_map/domain/love_map_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isEligible', () {
    final now = DateTime.utc(2026, 8, 28);

    test('an unseen question is eligible', () {
      expect(isEligible(seenAt: null, now: now), isTrue);
    });

    test('a question seen five months ago is not yet eligible', () {
      expect(isEligible(seenAt: DateTime.utc(2026, 3, 28), now: now), isFalse);
    });

    test('a question seen six months ago is eligible again', () {
      expect(isEligible(seenAt: DateTime.utc(2026, 2, 26), now: now), isTrue);
    });
  });

  group('selectQuestions', () {
    const pool = [
      LoveMapQuestion(id: 'f1', valueDomain: 'fears', text: 'f1'),
      LoveMapQuestion(id: 'd1', valueDomain: 'dreams', text: 'd1'),
      LoveMapQuestion(id: 's1', valueDomain: 'stressors', text: 's1'),
    ];

    test('prefers a domain matching a detected topic', () {
      final picked =
          selectQuestions(pool: pool, detectedTopics: const ['stressors'], count: 1);
      expect(picked.single.valueDomain, 'stressors');
    });

    test('falls back to plain rotation when nothing is detected', () {
      final picked =
          selectQuestions(pool: pool, detectedTopics: const [], count: 3);
      expect(picked, hasLength(3));
    });

    test('never returns more than the pool holds', () {
      final picked =
          selectQuestions(pool: pool, detectedTopics: const [], count: 99);
      expect(picked, hasLength(3));
    });

    test('never returns the same question twice', () {
      final picked =
          selectQuestions(pool: pool, detectedTopics: const [], count: 3);
      expect(picked.map((q) => q.id).toSet(), hasLength(3));
    });

    test('an empty pool yields nothing rather than throwing', () {
      expect(
        selectQuestions(pool: const [], detectedTopics: const ['fears'], count: 3),
        isEmpty,
      );
    });

    test('a detected topic matching nothing still returns questions', () {
      final picked = selectQuestions(
          pool: pool, detectedTopics: const ['nonexistent'], count: 2);
      expect(picked, hasLength(2));
    });
  });
}
