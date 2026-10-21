import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list reserve is the measured overlay height, not a constant', () {
    // The reserve used to be 120 (keyboard closed) / 64 (focused) — a guess
    // that any extra strip above the composer (typing, reply, staged game)
    // immediately broke. It is now measured with MeasureSize (#33); the
    // geometry itself is pinned by chat_screen_overlay_clearance_test.dart.
    final source =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    expect(source.contains('_messageListKeyboardBottomReserve'), isFalse);
    expect(source.contains('composerFocused'), isFalse);
    expect(source.contains('MeasureSize('), isTrue);
    expect(
      source.contains('bottomOverlayHeight + _messageListOverlayGap'),
      isTrue,
    );
  });
}
