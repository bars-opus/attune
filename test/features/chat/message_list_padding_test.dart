import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list reserve tightens when the composer is focused', () {
    // The bottom reserve covers the composer PLUS the home-indicator inset
    // while the keyboard is closed. When the composer is focused, the
    // keyboard may already have been consumed by Scaffold resize, so focus is
    // the reliable signal that the composer is just the floating row.
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
      source.contains('_messageListKeyboardBottomReserve'),
      isTrue,
      reason: 'focused composer clearance must use the tighter reserve',
    );

    expect(
      source.contains('_messageListKeyboardBottomReserve = 64.0'),
      isTrue,
      reason: 'the focused reserve should be close to the composer height',
    );

    expect(
      source.contains(
        'composerFocused || MediaQuery.of(context).viewInsets.bottom > 0',
      ),
      isTrue,
      reason: 'the focused text field must tighten spacing even after resize',
    );
  });
}
