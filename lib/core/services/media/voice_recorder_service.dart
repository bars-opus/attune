import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Result of a completed recording, ready to hand to
/// ChatController.sendVoiceMessage.
class VoiceRecording {
  const VoiceRecording({
    required this.localPath,
    required this.durationMs,
    required this.waveform,
  });

  final String localPath;
  final int durationMs;

  /// Fixed-length (100 points, values 0-255) amplitude array sampled live
  /// during recording. See design spec's "Waveform data is sampled live
  /// on-device" decision.
  final List<int> waveform;
}

/// Raised when a recording cannot proceed or complete. [code] is a coarse,
/// content-free reason (mirrors ChatImageRejected in
/// lib/features/chat/domain/services/chat_image_preparer.dart) — safe to
/// log, never a raw platform exception.
class VoiceRecordingException implements Exception {
  const VoiceRecordingException(this.code);
  final String code;

  @override
  String toString() => 'VoiceRecordingException($code)';
}

/// Records short voice messages: AAC/M4A, ~32kbps mono, capped at
/// [maxDuration], with a live-sampled waveform downsampled incrementally to
/// a fixed [waveformPointCount]-length array. See design spec's "Recording
/// UX" and "Client Architecture" sections.
///
/// One instance per recording session — callers construct a fresh instance
/// per press-and-hold gesture rather than reusing one across recordings,
/// matching ImagePickerService's own per-call-site instantiation pattern
/// (`lib/features/chat/presentation/screens/chat_screen.dart:57`:
/// `final _imagePicker = ImagePickerService();`).
class VoiceRecorderService {
  VoiceRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  static const Duration maxDuration = Duration(minutes: 5);
  static const Duration minDuration = Duration(milliseconds: 500);
  static const int waveformPointCount = 100;
  static const int _bitrate = 32000; // 32kbps

  Timer? _maxDurationTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _currentPath;
  DateTime? _startedAt;

  // Incremental downsampling state: rather than buffering every raw
  // amplitude reading and processing them in one pass at stop() (which
  // would mean unbounded memory growth for a long recording and a single
  // expensive pass at the end — checklist 2.14/2.15), each reading updates
  // the current time-bucket's running peak directly. Bucket width is
  // computed lazily on the first reading once maxDuration is known
  // (constant, so this could be precomputed, but is derived here to keep
  // the bucket-index math in one place).
  final List<double> _bucketPeaks = List.filled(waveformPointCount, 0.0);
  int _readingCount = 0;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> start() async {
    _bucketPeaks.fillRange(0, waveformPointCount, 0.0);
    _readingCount = 0;
    _startedAt = DateTime.now();

    final dir = await getTemporaryDirectory();
    _currentPath = p.join(
      dir.path,
      'voice_${DateTime.now().microsecondsSinceEpoch}.m4a',
    );

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: _bitrate,
          numChannels: 1,
        ),
        path: _currentPath!,
      );
    } catch (error) {
      throw const VoiceRecordingException('recording_start_failed');
    }

    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(_onAmplitude);

    _maxDurationTimer = Timer(maxDuration, () {
      // Auto-stop is fire-and-forget from the timer's perspective — the
      // caller (ChatTextField's gesture handler) is still holding the
      // press when this fires, so it learns the recording ended via
      // whatever UI-facing signal Task 6 wires up (e.g. re-checking
      // isRecording after the timer fires), not via this Future's result.
      unawaited(stop());
    });
  }

  void _onAmplitude(Amplitude amplitude) {
    debugFeedAmplitude(amplitude.current);
  }

  /// Test seam: feeds one raw amplitude reading through the same
  /// incremental-downsampling path start() wires up via the real plugin's
  /// stream, without needing a real microphone. Also called internally by
  /// _onAmplitude — production and test code share this exact path.
  @visibleForTesting
  void debugFeedAmplitude(double raw) {
    // record's amplitude stream reports dBFS (negative, 0 = loudest) on
    // some platforms and linear-ish values on others depending on
    // implementation; normalize defensively to a non-negative 0-255 byte
    // range regardless of the raw scale, rather than assuming one
    // particular unit convention.
    final normalized = raw.abs().clamp(0.0, 255.0);

    final bucketIndex =
        (_readingCount * waveformPointCount ~/ _expectedTotalReadings)
            .clamp(0, waveformPointCount - 1);
    if (normalized > _bucketPeaks[bucketIndex]) {
      _bucketPeaks[bucketIndex] = normalized;
    }
    _readingCount++;
  }

  // Amplitude readings arrive every 100ms (see the onAmplitudeChanged
  // interval above); over the max 5-minute recording that's 3000 possible
  // readings. Using this as the denominator for bucket-index math means a
  // recording stopped early still spreads its readings across buckets
  // proportionally to elapsed time rather than compressing them all into
  // the first few buckets — a 10-second recording's readings land across
  // the first ~7 buckets (10s / 300s * 100), not all crammed into bucket 0.
  //
  // Derived from maxDuration's raw millisecond count as a literal rather
  // than `maxDuration.inMilliseconds ~/ 100` — Duration's getters are not
  // const-evaluable in this Dart SDK, so that expression fails to compile
  // as a static const initializer.
  static const int _expectedTotalReadings = 5 * 60 * 1000 ~/ 100;

  /// Test seam: current downsampled waveform, without stopping the
  /// recorder. Production callers only ever see this via stop()'s returned
  /// VoiceRecording.
  @visibleForTesting
  List<int> debugCurrentWaveform() =>
      _bucketPeaks.map((v) => v.round().clamp(0, 255)).toList();

  Future<VoiceRecording> stop() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _recorder.stop();
    } catch (error) {
      throw const VoiceRecordingException('recording_stop_failed');
    }

    final path = _currentPath;
    final startedAt = _startedAt;
    if (path == null || startedAt == null) {
      throw const VoiceRecordingException('recording_missing');
    }
    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;

    return VoiceRecording(
      localPath: path,
      durationMs: durationMs,
      waveform: debugCurrentWaveform(),
    );
  }

  Future<void> cancel() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {
      // Best-effort — the goal is discarding, so a stop() failure here
      // doesn't need to surface to the caller.
    }

    final path = _currentPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort cleanup — an orphaned temp file is not worth
          // failing the cancel operation over.
        }
      }
    }
    _currentPath = null;
    _startedAt = null;
  }

  void dispose() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    unawaited(_amplitudeSubscription?.cancel());
    _amplitudeSubscription = null;
    unawaited(_recorder.dispose());
  }
}
