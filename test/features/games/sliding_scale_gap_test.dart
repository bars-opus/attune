import 'package:attune/features/games/sliding_scale/domain/services/sliding_scale_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ratingGap', () {
    test('identical ratings have no gap', () {
      expect(ratingGap(5, 5), 0);
    });

    test('opposite extremes give the maximum gap of 9', () {
      // The scale is 1-10, so the widest possible disagreement is 9,
      // not 10. Getting this wrong would make alignmentFromGap return a
      // negative score at the extreme.
      expect(ratingGap(1, 10), 9);
      expect(ratingGap(10, 1), 9);
    });

    test('gap is order-independent', () {
      expect(ratingGap(3, 8), ratingGap(8, 3));
    });
  });

  group('averageGap', () {
    test('averages across statements', () {
      expect(averageGap([0, 4, 2]), closeTo(2.0, 0.001));
    });

    test('an empty list averages to zero, not NaN', () {
      // Guards a divide-by-zero that would propagate NaN into the Pulse
      // score and poison every downstream comparison.
      expect(averageGap(const []), 0.0);
    });
  });

  group('alignmentFromGap', () {
    test('a zero gap is full alignment', () {
      expect(alignmentFromGap(0), closeTo(100.0, 0.001));
    });

    test('the maximum gap is zero alignment', () {
      expect(alignmentFromGap(9), closeTo(0.0, 0.001));
    });

    test('a mid gap is mid alignment', () {
      expect(alignmentFromGap(4.5), closeTo(50.0, 0.001));
    });

    test('out-of-range input is clamped, never negative', () {
      expect(alignmentFromGap(20), 0.0);
      expect(alignmentFromGap(-3), 100.0);
    });
  });
}
