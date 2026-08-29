import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the lock threshold matches where the pill is drawn', () {
    // A threshold beyond the visible target means the finger arrives at
    // the padlock and nothing happens, which reads as the gesture being
    // broken rather than as needing another 38px.
    final src =
        File(
          'lib/features/chat/presentation/widgets/chat_text_field.dart',
        ).readAsStringSync();
    // The pill moved onto the recording scrim, where it is placed relative
    // to the mic's measured rect. The invariant is unchanged: the drag must
    // complete where the pill is drawn.
    final scrim =
        File(
          'lib/features/chat/presentation/widgets/voice_recording_scrim.dart',
        ).readAsStringSync();

    final threshold = RegExp(
      r'_lockDragThreshold = ([\d.]+)',
    ).firstMatch(src)?.group(1);
    final pillBottom = RegExp(
      r'top: micRect\.top - (\d+),',
    ).firstMatch(scrim)?.group(1);

    expect(threshold, isNotNull, reason: 'threshold not found');
    expect(pillBottom, isNotNull, reason: 'pill position not found');
    expect(
      double.parse(threshold!),
      double.parse(pillBottom!),
      reason: 'the gesture must complete where the target is drawn',
    );
  });
}
