import 'dart:io';

import 'package:attune/features/chat/presentation/widgets/voice_mic_halo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the lock threshold does not overshoot the pill', () {
    // A threshold beyond the visible target means the finger arrives at
    // the padlock and nothing happens, which reads as the gesture being
    // broken rather than as needing another 38px.
    final src =
        File(
          'lib/features/chat/presentation/widgets/chat_text_field.dart',
        ).readAsStringSync();
    // The pill lives on the recording scrim now, placed relative to the
    // mic's measured rect. The invariant is unchanged.
    final scrim =
        File(
          'lib/features/chat/presentation/widgets/voice_recording_scrim.dart',
        ).readAsStringSync();

    final threshold =
        RegExp(r'_lockDragThreshold = ([\d.]+)').firstMatch(src)?.group(1);
    // The pill hangs off the halo's top edge, so its rise above the mic's
    // CENTRE — the distance the finger actually travels — is half the halo
    // plus that clearance.
    final clearance =
        RegExp(
          r'VoiceMicHalo\.haloExtent / 2 - (\d+)',
        ).firstMatch(scrim)?.group(1);

    expect(threshold, isNotNull, reason: 'threshold not found');
    expect(clearance, isNotNull, reason: 'pill position not found');

    // Read from the widget rather than hardcoded, so resizing the mic
    // moves this expectation with it.
    final pillRise = VoiceMicHalo.haloExtent / 2 + double.parse(clearance!);

    expect(
      double.parse(threshold!),
      lessThanOrEqualTo(pillRise),
      reason:
          'the drag must not have to travel past the pill: threshold '
          '$threshold vs pill $pillRise above the mic centre',
    );
  });
}
