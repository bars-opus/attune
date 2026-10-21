import 'dart:io';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the voice controller borrows the session instead of setting a '
      'context', () {
    // One owner for the audio session. A per-player playback context on iOS
    // is applied to the SHARED AVAudioSession and nothing restored ambient,
    // so one voice note broke every later chirp's silent-switch behaviour.
    final controllerSrc =
        File(
          'lib/features/chat/presentation/state/voice_playback_controller.dart',
        ).readAsStringSync();
    expect(controllerSrc, isNot(contains('AudioContextConfig(')));
    expect(controllerSrc, isNot(contains('respectSilence')));
    expect(controllerSrc, contains('beginPlayback(_engine.setAudioContext)'));
    expect(controllerSrc, contains('endPlayback'));
  });

  test('UI chirps stay on the silent switch and off other apps\' audio', () {
    // The fix must not swing the other way: notification blips stay muted
    // when the phone is silenced (iOS ambient), and never take Android
    // audio focus.
    expect(AppAudioContexts.chirp.iOS.category, AVAudioSessionCategory.ambient);
    expect(AppAudioContexts.chirp.android.audioFocus, AndroidAudioFocus.none);
  });

  test('playback failures surface instead of reading as silence', () {
    // With no error handling a thrown play() — missing file, unsupported
    // codec, failed download — is indistinguishable from a silent one.
    final controllerSrc =
        File(
          'lib/features/chat/presentation/state/voice_playback_controller.dart',
        ).readAsStringSync();
    expect(
      controllerSrc,
      contains('catch'),
      reason: 'a failed play() must not look the same as a silent one',
    );
    expect(
      controllerSrc,
      isNot(contains('catch (_)')),
      reason: 'the cause has to reach the log, not be discarded',
    );
  });
}
