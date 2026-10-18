import 'dart:io';

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

  test('the score is a count, never a flag (Spec 1b: no attentiveness '
      'judgement is computed or stored)', () {
    final src = File(
      'lib/features/games/mirror/domain/services/mirror_scoring.dart',
    ).readAsStringSync();
    expect(src.contains('isAttentivenessFlagged'), isFalse);
    expect(src.contains('kAttentivenessFlagThreshold'), isFalse);
  });
}
