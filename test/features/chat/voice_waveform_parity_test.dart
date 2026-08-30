import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the live and playback waveforms use the same minimum bar', () {
    // The scrim draws the recording live from currentLevel; the player
    // draws the stored array. Both are the same numbers (see
    // voice_recorder_service_test), so a different floor in either painter
    // makes the same audio look quieter on playback than it did live.
    //
    // A source check rather than a render comparison: the two painters
    // take different inputs and sizes, so rendering them side by side
    // would compare two different pictures rather than the one constant
    // that has to agree.
    final player =
        File(
          'lib/features/chat/presentation/widgets/voice_message_player.dart',
        ).readAsStringSync();

    expect(
      player,
      isNot(contains('clamp(0.12, 1.0)')),
      reason:
          'the 0.12 fraction floor lifts quiet audio well above where the '
          'live waveform draws it; both should floor in pixels',
    );
    expect(
      player,
      contains('_minBarHeight'),
      reason: 'the floor should be a named pixel constant, as live is',
    );
  });
}
