import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat UI sounds. Content-blind — these are event sounds, not tied to
/// message content.
enum ChatSound { send, receive }

/// Injectable one-shot sound player. Universal (any feature can use it); chat
/// is the first consumer. Playback failures are silent no-ops and never block
/// the caller.
abstract class SoundService {
  /// Preloads the clips so the first play has no cold-start latency.
  Future<void> preload();

  /// Plays [sound] if audio is available. Never throws.
  void play(ChatSound sound);
}

/// Test double: records calls, plays nothing.
class FakeSoundService implements SoundService {
  final List<ChatSound> played = [];
  int preloadCount = 0;

  @override
  Future<void> preload() async => preloadCount++;

  @override
  void play(ChatSound sound) => played.add(sound);
}

/// Real player. One preloaded AudioPlayer per sound. iOS uses the ambient audio
/// context so the hardware silent switch / DND mute chat sounds automatically.
class AudioPlayerSoundService implements SoundService {
  AudioPlayerSoundService();

  // AssetSource paths are relative to the `assets/` prefix already declared in
  // pubspec, so they start at `sounds/…`.
  static const _assets = {
    ChatSound.send: 'sounds/chat_send.wav',
    ChatSound.receive: 'sounds/chat_receive.wav',
  };

  final Map<ChatSound, AudioPlayer> _players = {};
  bool _ready = false;
  bool _preloading = false;

  @override
  Future<void> preload() async {
    if (_ready || _preloading) return;
    _preloading = true;
    try {
      // respectSilence:true maps (on iOS) to AVAudioSessionCategory.ambient:
      // silenced by the Ring/Silent switch and by screen locking, and does NOT
      // interrupt other apps' (nonmixable) audio. That combination is exactly
      // "silent switch mutes, don't interrupt other audio" — the ambient
      // category already implies non-interruption, so no extra `focus` option
      // is needed (and `mixWithOthers`/`duckOthers` are actually disallowed
      // together with `respectSilence` by the package's own validation).
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(respectSilence: true).build(),
      );
      for (final entry in _assets.entries) {
        final player = AudioPlayer()
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource(entry.value));
        _players[entry.key] = player;
      }
      _ready = true;
    } catch (e) {
      // Audio unavailable (e.g. test host, missing assets) — stay a no-op.
      _ready = false;
      if (kDebugMode) debugPrint('[sound] preload failed: silent no-op');
    } finally {
      _preloading = false;
    }
  }

  @override
  void play(ChatSound sound) {
    // Lazily preload if startup didn't (so the feature works even without an
    // explicit preload); the first play may be silent while it warms up, but
    // subsequent plays are ready. Never awaits, never throws into the caller.
    if (!_ready) {
      unawaited(preload());
      return;
    }
    final player = _players[sound];
    if (player == null) return;
    player.seek(Duration.zero).then((_) => player.resume()).catchError((_) {});
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}

/// Overridden in app startup / by the real impl. Now returns the real
/// audioplayers-backed implementation.
final soundServiceProvider = Provider<SoundService>((ref) {
  final service = AudioPlayerSoundService();
  ref.onDispose(service.dispose);
  return service;
});
