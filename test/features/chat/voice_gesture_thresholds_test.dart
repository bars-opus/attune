import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

double _constant(String src, String name) => double.parse(
      RegExp('$name = ([\\d.]+)').firstMatch(src)!.group(1)!,
    );

void main() {
  late String src;

  setUpAll(() {
    src = File(
      'lib/features/chat/presentation/widgets/chat_text_field.dart',
    ).readAsStringSync();
  });

  test('cancel is reachable before lock steals the gesture', () {
    // A leftward swipe carries upward drift. With cancel at 80px and lock
    // at 62px, the lock fires first and the recording sends instead of
    // being discarded — swipe-to-delete simply never works.
    final cancel = _constant(src, '_cancelDragThreshold');
    final lock = _constant(src, '_lockDragThreshold');

    expect(
      cancel,
      lessThanOrEqualTo(lock),
      reason: 'cancel must complete no later than lock, or the upward '
          'drift of a leftward swipe locks instead of cancelling',
    );
  });

  test('the mic stays on screen while recording', () {
    // The bar replaced the entire icon row, so the mic, its halo and its
    // progress ring were not rendered at all mid-recording — the ring
    // could never appear however correctly it was built.
    // Asserts it is RENDERED, not merely defined: the class surviving
    // unused would pass a bare contains() while the bar goes back to
    // replacing the row.
    expect(
      src,
      contains('? _RecordingComposer('),
      reason: 'the bar and the mic must sit side by side, not swap',
    );
    expect(
      src,
      isNot(contains('? VoiceRecordingBar(')),
      reason: 'the bar alone must not be the recording branch',
    );
  });
}
