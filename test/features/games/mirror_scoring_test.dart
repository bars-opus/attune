import 'package:attune/features/games/mirror/domain/services/mirror_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mirrorScore', () {
    test('counts correct judgements', () {
      expect(mirrorScore([true, true, false, true]), 3);
    });

    test('a perfect round scores every question', () {
      expect(mirrorScore(List<bool>.filled(8, true)), 8);
    });

    test('no correct guesses scores zero, not null', () {
      expect(mirrorScore(List<bool>.filled(8, false)), 0);
    });

    test('an empty list scores zero', () {
      // A session abandoned before any round was judged must produce a
      // real 0, not a crash or a null that later reads as "unscored".
      expect(mirrorScore(const []), 0);
    });
  });

  group('isAttentivenessFlagged', () {
    test('flags below the 6.5 threshold (§8.4)', () {
      expect(isAttentivenessFlagged(6), isTrue);
      expect(isAttentivenessFlagged(0), isTrue);
    });

    test('does not flag at or above the threshold', () {
      // 6.5 of 8 means 7 is the first passing whole score.
      expect(isAttentivenessFlagged(7), isFalse);
      expect(isAttentivenessFlagged(8), isFalse);
    });

    test('the boundary is exclusive on the low side', () {
      // Guards the off-by-one: 6 < 6.5 flags, 7 > 6.5 does not. A >=
      // comparison against 6 or a rounding of 6.5 to 7 would break one
      // of these two assertions.
      expect(isAttentivenessFlagged(6), isTrue);
      expect(isAttentivenessFlagged(7), isFalse);
    });
  });
}
