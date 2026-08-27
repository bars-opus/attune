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

  /// Set once the max-duration timer's auto-stop finishes. The user is
  /// typically still physically holding the record gesture when this
  /// fires, so a later, user-driven call to [stop] must not try to stop
  /// the (already-stopped) recorder plugin a second time — that either
  /// throws, or recomputes a wall-clock duration that now exceeds
  /// [maxDuration] and gets rejected downstream as "too long to send".
  /// Reset to null at the start of every new recording in [start].
  VoiceRecording? _completedRecording;

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

  /// Live 0.0-1.0 level of the most recent amplitude reading, republished
  /// every ~100ms while recording.
  ///
  /// The downsampled [_bucketPeaks] array is a *whole-recording* summary
  /// only readable at [stop] — it can't drive a live waveform, which is
  /// why the recording UI used to paint a hardcoded constant. This
  /// notifier is the live counterpart: same readings, same dBFS
  /// normalization, published as they arrive.
  ///
  /// A ValueNotifier rather than a Stream so the recording bar can rebuild
  /// only the waveform via ValueListenableBuilder, instead of setState-ing
  /// the whole composer ten times a second.
  final ValueNotifier<double> currentLevel = ValueNotifier<double>(0.0);

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> start() async {
    _bucketPeaks.fillRange(0, waveformPointCount, 0.0);
    _readingCount = 0;
    currentLevel.value = 0.0;
    _startedAt = DateTime.now();
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _completedRecording = null;

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
      // Goes through _performStop() (not stop()) and latches the result
      // into _completedRecording, so the eventual user-driven stop() call
      // (once they release the still-held gesture) returns this same
      // already-captured recording instead of stopping an already-stopped
      // recorder a second time and recomputing a now-too-long duration.
      unawaited(_autoStop());
    });
  }

  Future<void> _autoStop() async {
    try {
      _completedRecording = await _performStop();
    } on VoiceRecordingException {
      // Best-effort — if the auto-stop itself fails, leave
      // _completedRecording unset so the eventual stop() call surfaces
      // the failure normally via its own _performStop() attempt.
    }
  }

  /// Test seam: simulates the max-duration timer firing and running its
  /// auto-stop path, without waiting the real 5 minutes. Exercises the
  /// exact same _autoStop()/_performStop() path the real Timer callback
  /// in [start] uses.
  @visibleForTesting
  Future<void> debugTriggerMaxDurationAutoStop() => _autoStop();

  /// Test seam: seeds the "a fresh recording just started" state that
  /// [start] itself sets up ([_currentPath], [_startedAt], the waveform
  /// buckets, and — critically — resetting [_completedRecording] to null
  /// so a stale latched result from a previous session isn't inherited),
  /// without going through [start] itself — [start] touches the real
  /// platform recorder plugin (path_provider, permission_handler, record),
  /// which isn't available in a pure Dart test host. Lets tests exercise
  /// [stop] / [debugTriggerMaxDurationAutoStop] against a
  /// constructor-injected fake [AudioRecorder] as if a real recording were
  /// underway.
  @visibleForTesting
  void debugSeedActiveRecording({required String path, required DateTime startedAt}) {
    _bucketPeaks.fillRange(0, waveformPointCount, 0.0);
    _readingCount = 0;
    _completedRecording = null;
    _pausedTotal = Duration.zero;
    _pausedAt = null;
    _currentPath = path;
    _startedAt = startedAt;
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
    // record's Amplitude.current is dBFS: 0 = loudest possible, and
    // increasingly NEGATIVE as audio gets quieter (roughly -50 to -60 dBFS
    // near silence, down to a theoretical -160 floor). A linear mapping
    // from [-50, 0] dBFS to [0, 255] preserves perceptual ordering — loud
    // (near 0 dBFS) maps to a tall bar, quiet/silent (<= -50 dBFS) maps to
    // 0. Using .abs() here would invert that (loud -> small number, quiet
    // -> large number), which is exactly the bug this replaced.
    const minDb = -50.0;
    final db = raw.clamp(minDb, 0.0);
    final normalized = ((db - minDb) / -minDb * 255).clamp(0.0, 255.0);

    // Published from inside the shared normalization path (rather than
    // from _onAmplitude) so the live waveform and the final recorded
    // waveform are guaranteed to be the same numbers — and so the
    // debugFeedAmplitude test seam drives both identically.
    // Guarded against a late in-flight amplitude reading arriving after
    // dispose() — writing a disposed ValueNotifier throws.
    if (!_levelDisposed) currentLevel.value = normalized / 255;

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
    final alreadyCompleted = _completedRecording;
    if (alreadyCompleted != null) {
      // The max-duration timer already auto-stopped this recording (the
      // user was still holding the gesture when it fired). Return the
      // already-captured result idempotently instead of calling into the
      // recorder plugin a second time — that would either throw (recorder
      // already stopped) or recompute a wall-clock duration that now
      // exceeds maxDuration.
      return alreadyCompleted;
    }

    final recording = await _performStop();
    _completedRecording = recording;
    return recording;
  }

  /// Does the actual work of stopping the recorder plugin and building the
  /// [VoiceRecording] result. Shared by the public [stop] and the internal
  /// max-duration auto-stop path — callers are responsible for latching
  /// the result into [_completedRecording] as appropriate.
  Future<VoiceRecording> _performStop() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _recorder.stop();
    } catch (error) {
      throw const VoiceRecordingException('recording_stop_failed');
    }

    // Close any still-open pause span BEFORE reading `elapsed`. Stopping
    // while paused is an ordinary action (pause, then tap send), and
    // leaving the span open would let it keep accruing against the
    // recording — understating durationMs by the length of the pause.
    _closeOpenPause();

    final path = _currentPath;
    final startedAt = _startedAt;
    if (path == null || startedAt == null) {
      throw const VoiceRecordingException('recording_missing');
    }
    // Excludes paused spans — see `elapsed`'s doc. Uses the same getter
    // the UI ticker reads, so the sent duration always matches the timer
    // the user watched.
    final durationMs = elapsed.inMilliseconds;

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
    // Reset alongside the rest of the per-recording state, so a reused
    // instance can never inherit a previous session's pause accounting.
    _pausedTotal = Duration.zero;
    _pausedAt = null;
  }

  void dispose() {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    unawaited(_amplitudeSubscription?.cancel());
    _amplitudeSubscription = null;
    unawaited(_recorder.dispose());
    // Guarded: dispose() is contractually idempotent here (a widget's
    // dispose may run after the service already stopped and disposed —
    // see the repeated-dispose test), but ValueNotifier.dispose() throws
    // on a second call. Everything else above is already a safe no-op
    // when repeated.
    if (!_levelDisposed) {
      _levelDisposed = true;
      currentLevel.dispose();
    }
  }

  bool _levelDisposed = false;

  // Pause bookkeeping. Duration is computed from wall-clock
  // (DateTime.now() - _startedAt), so any time spent paused would
  // otherwise be counted as recorded audio — producing a durationMs longer
  // than the actual file, which desyncs the player's progress bar and can
  // push a recording past maxDuration's downstream check. _pausedTotal
  // accumulates completed pause spans; _pausedAt marks an open one.
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;

  bool get isPaused => _pausedAt != null;

  /// Suspends capture without finalizing the recording. No-op if already
  /// paused or not recording.
  Future<void> pause() async {
    if (_pausedAt != null || _startedAt == null) return;
    try {
      await _recorder.pause();
    } catch (error) {
      throw const VoiceRecordingException('recording_pause_failed');
    }
    _pausedAt = DateTime.now();
    if (!_levelDisposed) currentLevel.value = 0.0;
  }

  /// Resumes a paused recording. No-op if not paused.
  Future<void> resume() async {
    if (_pausedAt == null) return;
    try {
      await _recorder.resume();
    } catch (error) {
      throw const VoiceRecordingException('recording_resume_failed');
    }
    _closeOpenPause();
  }

  /// Folds an in-progress pause span into [_pausedTotal] and clears it.
  /// Idempotent — a no-op when not paused.
  void _closeOpenPause() {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    _pausedTotal += DateTime.now().difference(pausedAt);
    _pausedAt = null;
  }

  /// Elapsed *recorded* time — wall-clock since start, minus any time
  /// spent paused (including an in-progress pause). The single source of
  /// truth for both the UI's ticker and [_performStop]'s durationMs, so
  /// the displayed timer and the persisted duration can never disagree.
  Duration get elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;
    final openPause =
        _pausedAt == null
            ? Duration.zero
            : DateTime.now().difference(_pausedAt!);
    final value =
        DateTime.now().difference(startedAt) - _pausedTotal - openPause;
    // Floored at zero: a device clock adjustment mid-recording can make
    // the wall-clock difference smaller than the accumulated pause total,
    // which would otherwise yield a NEGATIVE durationMs — silently
    // corrupting the sent message's metadata and any player that divides
    // by it.
    return value < Duration.zero ? Duration.zero : value;
  }
}
