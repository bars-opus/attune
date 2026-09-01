import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list reserve drops the safe-area inset when the keyboard is up', () {
    // The bottom reserve covers the composer PLUS the home-indicator
    // inset, because the composer wraps itself in a SafeArea. When the
    // keyboard opens, that inset collapses to zero -- the keyboard is
    // covering the indicator -- but a flat 120 kept reserving for it,
    // leaving a visible gap under the last bubble.
    final source =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    expect(
      source.contains('const EdgeInsets.fromLTRB(0, 10, 0, 120)'),
      isFalse,
      reason:
          'a constant reserve cannot account for the inset disappearing '
          'behind the keyboard',
    );

    expect(
      source.contains('120 - MediaQuery.of(context).padding.bottom'),
      isTrue,
      reason: 'the reserve must shed the inset the keyboard now covers',
    );
  });
}
