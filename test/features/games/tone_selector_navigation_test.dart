import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Both tone selectors are GoRouter page-based routes. Completing one
  // with the imperative Navigator API throws:
  //
  //   'A page-based route cannot be completed using imperative api'
  //
  // The session was already created when that fired, so the game existed
  // and only the navigation failed -- and the catch turned it into
  // "Could not start the game right now", which reads as the game being
  // unavailable rather than a routing bug.
  const selectors = <String, String>{
    'Truth or Dare':
        'lib/features/games/truth_or_dare/presentation/screens/'
            'truth_or_dare_tone_selector_screen.dart',
    'This or That':
        'lib/features/games/this_or_that/presentation/screens/'
            'tone_selector_screen.dart',
  };

  selectors.forEach((game, path) {
    test('$game starts its session through the router', () {
      final source = File(path).readAsStringSync();

      expect(
        source.contains('navigator.pushReplacement('),
        isFalse,
        reason:
            'an imperative pushReplacement on a page-based route throws, '
            'and the failure surfaces as "could not start the game"',
      );
      expect(
        source.contains('pushReplacementNamed('),
        isTrue,
        reason: 'the session router must be reached by name',
      );
    });
  });
}
