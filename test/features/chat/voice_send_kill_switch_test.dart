import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the temporary voice-send kill switch is still recorded as OFF', () {
    // Deliberately fails once the flag is flipped back to true. That
    // failure is the reminder to delete this test and the flag together --
    // a disabled send that nobody remembers disabling is a silent feature
    // regression, which is exactly what a kill switch invites.
    final src = File(
      'lib/features/chat/presentation/screens/chat_screen.dart',
    ).readAsStringSync();

    final match = RegExp(
      r'_voiceSendEnabled = (true|false)',
    ).firstMatch(src);

    expect(match, isNotNull, reason: 'flag not found — was it removed?');
    expect(
      match!.group(1),
      'false',
      reason:
          'Voice send is re-enabled. Delete _voiceSendEnabled, its guard in '
          '_onVoiceMessageRecorded, and this test.',
    );
  });
}
