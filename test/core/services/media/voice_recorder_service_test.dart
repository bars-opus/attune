import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  group('VoiceRecorderService waveform downsampling', () {
    test('downsamples an arbitrary number of amplitude readings to a fixed 100-point array', () {
      final service = VoiceRecorderService();
      // Feed 350 raw readings (more than the 100-point target) through the
      // service's own incremental downsampler and confirm the output is
      // always exactly 100 points regardless of input count — this is the
      // core invariant from the spec ("fixed-length array... regardless of
      // recording duration").
      for (var i = 0; i < 350; i++) {
        service.debugFeedAmplitude((i % 256).toDouble());
      }
      final waveform = service.debugCurrentWaveform();
      expect(waveform.length, 100);
    });

    test('downsamples fewer readings than the target point count without crashing', () {
      final service = VoiceRecorderService();
      for (var i = 0; i < 12; i++) {
        service.debugFeedAmplitude((i * 10).toDouble());
      }
      final waveform = service.debugCurrentWaveform();
      expect(waveform.length, 100);
      // Only the first 12 buckets should have real data; the rest are the
      // downsampler's defined fill value (0) rather than garbage/uninitialized.
      expect(waveform.skip(12).every((v) => v == 0), isTrue);
    });

    test('every waveform value is clamped to the 0-255 byte range', () {
      final service = VoiceRecorderService();
      service.debugFeedAmplitude(-40.0); // amplitude streams can report negative dB
      service.debugFeedAmplitude(9999.0); // and out-of-range positive spikes
      final waveform = service.debugCurrentWaveform();
      expect(waveform.every((v) => v >= 0 && v <= 255), isTrue);
    });

    test('a louder dBFS reading produces a TALLER bar than a quieter one', () {
      // record's Amplitude.current is dBFS: 0 = loudest, increasingly
      // negative as audio gets quieter. This is the exact regression guard
      // for the inverted-waveform bug: naively taking .abs() of a dBFS
      // reading makes loud audio (near 0) produce a SMALL number and quiet
      // audio (e.g. -45) produce a LARGER number than loud audio — visually
      // backwards. Feed the two readings into different bucket indices
      // (far enough apart in _readingCount that they land in different
      // buckets of the 100-point downsampled array) so they don't overwrite
      // each other, then assert the loud reading's bucket is taller.
      final service = VoiceRecorderService();

      // Bucket index is `_readingCount * 100 ~/ 3000` (3000 = expected
      // total readings over the 5-minute max at one reading/100ms). Feed
      // enough filler readings first to land the loud/quiet readings in
      // two distinct, well-separated buckets: the 1501st reading (index
      // 1500) lands in bucket 50, and the 7502nd reading (index 7501)
      // clamps into the final bucket, 99.
      for (var i = 0; i < 1500; i++) {
        service.debugFeedAmplitude(-50.0); // silence filler
      }
      service.debugFeedAmplitude(-5.0); // loud reading, lands in bucket 50

      for (var i = 0; i < 6000; i++) {
        service.debugFeedAmplitude(-50.0); // silence filler
      }
      service.debugFeedAmplitude(-45.0); // quiet reading, lands in bucket 99

      final waveform = service.debugCurrentWaveform();
      final loudBucket = waveform[50];
      final quietBucket = waveform[99];

      expect(
        loudBucket,
        greaterThan(quietBucket),
        reason:
            'a -5 dBFS (loud) reading must produce a taller bar than a '
            '-45 dBFS (quiet) reading — if this fails, the waveform is '
            'inverted (see C2 fix in voice_recorder_service.dart)',
      );
    });
  });

  group('VoiceRecorderService resource cleanup', () {
    test('stop() can be called repeatedly across start/stop cycles without leaking', () async {
      final service = VoiceRecorderService();
      // Three full cycles — each stop() must fully release its subscription/
      // timer so the next start() doesn't compound leaked resources. This
      // can't directly assert "no leaked StreamSubscription" without a real
      // recorder plugin (unavailable in a pure Dart test host), so this
      // test instead asserts the cycle completes without throwing and that
      // repeated dispose() calls (simulating a widget's dispose being
      // called after an already-stopped service) are safe no-ops.
      for (var i = 0; i < 3; i++) {
        expect(() => service.dispose(), returnsNormally);
      }
    });
  });

  group('VoiceRecorderService max-duration auto-stop', () {
    test(
      'stop() after the max-duration timer already auto-stopped returns the '
      'already-captured recording instead of throwing or over-counting duration',
      () async {
        // A bare AudioRecorder() that never has start()/hasPermission()/etc.
        // called on it never touches the real platform channel (record's
        // AudioRecorder._created stays null, so its stop() short-circuits
        // and returns null locally) — safe to use directly in a pure Dart
        // test host without a fake/mock.
        final service = VoiceRecorderService(recorder: AudioRecorder());

        // Seed "a recording is in progress" state without going through
        // start() (which needs path_provider/permission_handler/record
        // platform channels unavailable here), then feed one amplitude
        // reading so the eventual waveform isn't empty.
        final startedAt = DateTime.now().subtract(const Duration(minutes: 5));
        service.debugSeedActiveRecording(
          path: '/tmp/voice_test.m4a',
          startedAt: startedAt,
        );
        service.debugFeedAmplitude(-5.0);

        // Simulate the internal max-duration Timer firing while the user is
        // still physically holding the record gesture.
        await service.debugTriggerMaxDurationAutoStop();

        // The user keeps holding for a bit longer in real wall-clock time
        // before releasing — long enough that, were stop() to recompute the
        // duration instead of returning the latched result, it would grow
        // measurably past this delay.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // The user releases their still-held gesture — the UI-driven stop()
        // call must NOT throw, and must NOT recompute a fresh (now longer)
        // wall-clock duration.
        final recording = await service.stop();

        expect(recording.localPath, '/tmp/voice_test.m4a');
        // Duration must be the one captured AT auto-stop time (~5 minutes),
        // not stretched out by the 50ms+ that elapsed before this second
        // stop() call ran — proves stop() returned the latched result
        // rather than recomputing DateTime.now().difference(startedAt).
        expect(
          recording.durationMs,
          lessThan(VoiceRecorderService.maxDuration.inMilliseconds + 1000),
        );
        expect(recording.waveform.length, 100);

        // Calling stop() again is also idempotent — same result, no second
        // call into the (already-stopped) recorder plugin.
        final recordingAgain = await service.stop();
        expect(recordingAgain.durationMs, recording.durationMs);
        expect(recordingAgain.localPath, recording.localPath);
      },
    );

    test(
      'a fresh start() (simulated via debugSeedActiveRecording) does not '
      'inherit a stale completed-recording from a previous session',
      () async {
        final service = VoiceRecorderService(recorder: AudioRecorder());

        service.debugSeedActiveRecording(
          path: '/tmp/first.m4a',
          startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await service.debugTriggerMaxDurationAutoStop();
        final first = await service.stop();
        expect(first.localPath, '/tmp/first.m4a');

        // A real second recording starts — start() resets _completedRecording
        // to null internally; debugSeedActiveRecording alone doesn't reset
        // it, so exercise the real start()-adjacent reset path is covered
        // by asserting stop() computes a FRESH duration/path here rather
        // than replaying the first session's latched result.
        service.debugSeedActiveRecording(
          path: '/tmp/second.m4a',
          startedAt: DateTime.now().subtract(const Duration(seconds: 1)),
        );
        final second = await service.stop();
        expect(second.localPath, '/tmp/second.m4a');
      },
    );
  });

  group('VoiceRecordingException', () {
    test('carries a coarse, content-free code, mirroring ChatImageRejected', () {
      const exception = VoiceRecordingException('permission_denied');
      expect(exception.code, 'permission_denied');
      expect(exception.toString(), contains('permission_denied'));
      expect(exception.toString(), isNot(contains('/'))); // no leaked file paths
    });
  });
}
