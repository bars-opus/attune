// test/core/ui/audio_session_coordinator_test.dart
import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what a caller's `player.setAudioContext` would have received.
class _Recorder {
  final List<AudioContext> contexts = [];
  Future<void> set(AudioContext context) async => contexts.add(context);
}

class _ThrowingPort implements AudioSessionPort {
  @override
  Future<void> setGlobalContext(AudioContext context) async =>
      throw Exception('no plugin');
}

void main() {
  group('AppAudioContexts', () {
    test('chirps request no Android audio focus and sit on the '
        'notification stream', () {
      // AUDIOFOCUS_GAIN (the package default) is permanent: Spotify gets
      // AUDIOFOCUS_LOSS and never resumes. FocusManager.kt skips the
      // request entirely for AUDIOFOCUS_NONE.
      final android = AppAudioContexts.chirp.android;
      expect(android.audioFocus, AndroidAudioFocus.none);
      expect(
        android.usageType,
        AndroidUsageType.notificationCommunicationInstant,
      );
      expect(android.contentType, AndroidContentType.sonification);
    });

    test(
      'chirps are ambient on iOS (silent switch mutes, mixes with others)',
      () {
        expect(
          AppAudioContexts.chirp.iOS.category,
          AVAudioSessionCategory.ambient,
        );
        expect(AppAudioContexts.chirp.iOS.options, isEmpty);
      },
    );

    test(
      'a voice note takes TRANSIENT focus on Android and playback on iOS',
      () {
        // Transient, not gain: the music app resumes when the note ends.
        expect(
          AppAudioContexts.voiceNote.android.audioFocus,
          AndroidAudioFocus.gainTransient,
        );
        expect(
          AppAudioContexts.voiceNote.android.usageType,
          AndroidUsageType.media,
        );
        expect(
          AppAudioContexts.voiceNote.iOS.category,
          AVAudioSessionCategory.playback,
        );
      },
    );
  });

  group('AudioSessionCoordinator', () {
    test('preload sets the chirp context globally and per player', () async {
      final port = FakeAudioSessionPort();
      final session = AudioSessionCoordinator(port: port);
      final player = _Recorder();

      await session.applyChirpGlobalContext();
      await session.configureChirpPlayer(player.set);

      expect(port.globalContexts, [AppAudioContexts.chirp]);
      expect(player.contexts, [AppAudioContexts.chirp]);
    });

    test('on iOS every chirp re-asserts ambient first', () async {
      // AVAudioSession is process-global; audioplayers_darwin applies even a
      // per-player context to the shared session, and video_player upgrades
      // it to playback whenever a video is created. Nothing else ever puts
      // ambient back, so the chirp has to.
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      );
      final player = _Recorder();
      await session.beforeChirp(player.set);
      await session.beforeChirp(player.set);
      expect(player.contexts, [AppAudioContexts.chirp, AppAudioContexts.chirp]);
    });

    test(
      'on Android the per-player context persists, so a chirp sets nothing',
      () async {
        final session = AudioSessionCoordinator(
          port: FakeAudioSessionPort(),
          platform: TargetPlatform.android,
        );
        final player = _Recorder();
        await session.beforeChirp(player.set);
        expect(player.contexts, isEmpty);
      },
    );

    test('a voice note borrows the session and gives it back', () async {
      final port = FakeAudioSessionPort();
      final session = AudioSessionCoordinator(
        port: port,
        platform: TargetPlatform.iOS,
      );
      final voice = _Recorder();

      await session.beginPlayback(voice.set);
      expect(voice.contexts, [AppAudioContexts.voiceNote]);
      expect(session.playbackHeld, isTrue);

      await session.endPlayback();
      expect(session.playbackHeld, isFalse);
      expect(
        port.globalContexts,
        [AppAudioContexts.chirp],
        reason: 'ambient must be restored the moment playback ends',
      );
    });

    test('a chirp during a held playback leaves the session alone', () async {
      // Review Focus 1: a receive chirp mid-voice-note must not flip the
      // session to ambient under the note (which would mute it on silent).
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      );
      await session.beginPlayback((_) async {});
      final chirp = _Recorder();
      await session.beforeChirp(chirp.set);
      expect(chirp.contexts, isEmpty);
    });

    test('holds are counted, not boolean', () async {
      // Review Focus 2: two overlapping notes (cross-bubble auto-pause races
      // the next play) release ambient once, after the LAST end; a stray
      // extra end never drives the count negative.
      final port = FakeAudioSessionPort();
      final session = AudioSessionCoordinator(
        port: port,
        platform: TargetPlatform.iOS,
      );
      await session.beginPlayback((_) async {});
      await session.beginPlayback((_) async {});
      await session.endPlayback();
      expect(port.globalContexts, isEmpty);
      expect(session.playbackHeld, isTrue);
      await session.endPlayback();
      expect(port.globalContexts, [AppAudioContexts.chirp]);
      await session.endPlayback(); // stray
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp]);
    });

    test('a failed beginPlayback does not leave a phantom hold', () async {
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      );
      await expectLater(
        session.beginPlayback((_) async => throw Exception('no plugin')),
        throwsException,
      );
      expect(session.playbackHeld, isFalse);
    });

    test('endPlayback during a failing begin cannot drive the count '
        'negative', () async {
      final session = AudioSessionCoordinator(port: FakeAudioSessionPort());
      final failing = session.beginPlayback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        throw Exception('no plugin');
      });
      final settled = expectLater(failing, throwsException);
      await session.endPlayback(); // releases the in-flight hold
      await settled;
      expect(session.playbackHeld, isFalse);
      await session.beginPlayback((_) async {});
      expect(session.playbackHeld, isTrue);
    });

    test('port failures on end/apply are logged, not thrown', () async {
      final session = AudioSessionCoordinator(
        port: _ThrowingPort(),
        platform: TargetPlatform.iOS,
      );
      await session.applyChirpGlobalContext();
      await session.beginPlayback((_) async {});
      await session.endPlayback();
      expect(session.playbackHeld, isFalse);
    });
  });
}
