import 'dart:async';

import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:audioplayers/audioplayers.dart';

/// Scriptable engine: records calls, lets tests push position/completion/
/// playing events as the OS would.
///
/// Models audioplayers' default ReleaseMode.release: a completion frees the
/// source, so [resume] (and [seek]) after it do nothing until the next
/// [play] sets a source again.
class FakeVoiceEngine implements VoicePlaybackEngine {
  FakeVoiceEngine() {
    // Subscribed first, so the source is released before any other
    // listener (the controller) reacts to the completion.
    completionsController.stream.listen((_) => released = true);
  }

  final positionsController = StreamController<Duration>.broadcast();
  final completionsController = StreamController<void>.broadcast();
  final playingController = StreamController<bool>.broadcast();

  /// True once a completion released the source (no source loaded).
  bool released = false;

  /// Calls to [resume] that found no source (after a completion).
  int resumesWithoutSource = 0;

  /// When set, [stop] waits on it — a slow platform stop.
  Completer<void>? stopGate;

  final List<String> calls = [];
  final List<AudioContext> contexts = [];
  String? lastSource;
  bool? lastIsLocalFile;
  double lastRate = 1.0;
  Duration? lastSeek;

  /// When set, the next [play] throws it.
  Object? nextPlayError;

  @override
  Stream<Duration> get positions => positionsController.stream;
  @override
  Stream<void> get completions => completionsController.stream;
  @override
  Stream<bool> get playing => playingController.stream;

  @override
  Future<void> setAudioContext(AudioContext context) async {
    calls.add('context');
    contexts.add(context);
  }

  @override
  Future<void> play(
    String source, {
    required bool isLocalFile,
    required double rate,
  }) async {
    calls.add('play');
    final error = nextPlayError;
    if (error != null) {
      nextPlayError = null;
      throw error;
    }
    released = false;
    lastSource = source;
    lastIsLocalFile = isLocalFile;
    lastRate = rate;
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async {
    calls.add('resume');
    if (released) resumesWithoutSource++;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final gate = stopGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    if (released) return;
    lastSeek = position;
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('rate:$rate');
    lastRate = rate;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await positionsController.close();
    await completionsController.close();
    await playingController.close();
  }
}
