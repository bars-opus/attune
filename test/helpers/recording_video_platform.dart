import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records play/pause. A playing clip reports 0.5 s of progress; [initGate]
/// holds the "initialized" event back until the test completes it.
class RecordingVideoPlatform extends VideoPlayerPlatform {
  RecordingVideoPlatform({this.initGate});
  final Completer<void>? initGate;
  final List<String> calls = [];
  final Set<int> _playing = {};
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    _playing.remove(playerId);
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    _streams[id] = StreamController<VideoEvent>.broadcast(
      onListen: () async {
        if (initGate != null) await initGate!.future;
        _streams[id]?.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 4),
            size: const Size(720, 1280),
          ),
        );
      },
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
    _playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
    _playing.remove(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async =>
      _playing.contains(playerId)
          ? const Duration(milliseconds: 500)
          : Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} unused');
}
