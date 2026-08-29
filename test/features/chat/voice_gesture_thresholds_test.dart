import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

double _constant(String src, String name) =>
    double.parse(RegExp('$name = ([\\d.]+)').firstMatch(src)!.group(1)!);

void main() {
  late String src;

  setUpAll(() {
    src =
        File(
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
      reason:
          'cancel must complete no later than lock, or the upward '
          'drift of a leftward swipe locks instead of cancelling',
    );
  });

  test('the composer never swaps its row out mid-recording', () {
    // The bar used to replace the entire icon row, so the mic, its halo
    // and its progress ring were not rendered at all mid-recording — the
    // ring could never appear however correctly it was built.
    //
    // The recording UI now lives entirely on the scrim overlay and the
    // composer keeps its ordinary row, whose mic slot still holds the
    // gesture and the position the scrim measures. That the mic stays put
    // and visible is covered behaviourally in voice_record_feedback_test;
    // this guards the structural rule that produced the bug.
    expect(
      src,
      isNot(contains('? VoiceRecordingBar(')),
      reason: 'the bar must never be the composer\'s recording branch',
    );
    expect(
      src,
      isNot(contains('_RecordingComposer')),
      reason: 'the two-branch composer is gone; the scrim owns both stages',
    );
  });
}
