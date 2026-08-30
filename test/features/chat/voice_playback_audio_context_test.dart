import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the voice player sets a playback audio context of its own', () {
    // SoundService calls AudioPlayer.global.setAudioContext with
    // respectSilence:true, which on iOS is AVAudioSessionCategory.ambient
    // — muted by the Ring/Silent switch. That call is PROCESS-WIDE, so it
    // applies to voice messages too, and a voice note played silently.
    //
    // UI chirps genuinely should respect the silent switch; a voice
    // message a user deliberately tapped should not. The player therefore
    // needs its own per-player context rather than inheriting the global.
    final player =
        File(
          'lib/features/chat/presentation/widgets/voice_message_player.dart',
        ).readAsStringSync();

    expect(
      player,
      contains('setAudioContext'),
      reason:
          'without its own context the player inherits SoundService\'s '
          'ambient category and plays silently',
    );
    expect(
      player,
      contains('respectSilence: false'),
      reason: 'a deliberately-tapped voice note must play through silent mode',
    );
  });

  test('SoundService still keeps UI chirps on the silent switch', () {
    // The fix must not swing the other way: notification blips should stay
    // muted when the phone is silenced.
    final sound =
        File('lib/core/ui/feedback/sound_service.dart').readAsStringSync();
    expect(sound, contains('respectSilence: true'));
  });

  test('playback failures surface instead of reading as silence', () {
    // With no error handling a thrown play() — missing file, unsupported
    // codec, failed download — is indistinguishable from a silent one.
    // That ambiguity is what made the ambient-category bug hard to place.
    final player =
        File(
          'lib/features/chat/presentation/widgets/voice_message_player.dart',
        ).readAsStringSync();

    expect(
      player,
      contains('catch'),
      reason: 'a failed play() must not look the same as a silent one',
    );
    expect(
      player,
      isNot(contains('catch (_)')),
      reason: 'the cause has to reach the log, not be discarded',
    );
  });
}
