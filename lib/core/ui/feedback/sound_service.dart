import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Universal one-shot UI sounds. Content-blind — these are event sounds, not
/// tied to any message/answer content. Any feature can add a value here.
enum AppSound {
  // Chat
  chatSend,
  chatReceive,
  // Games — shared beats across This or That / Truth or Dare / 36 Questions.
  gameMatch, // both partners aligned — the celebratory beat
  gameCardFlip, // Truth or Dare card flip
  gameReveal, // a round result / answer reveal
  gameTap, // option / choice selection
  gameComplete, // session finished (end screen)
}

/// Back-compat alias for the original chat-only names. Existing chat call sites
/// use `ChatSound.send` / `ChatSound.receive`; keep them working unchanged.
abstract final class ChatSound {
  static const AppSound send = AppSound.chatSend;
  static const AppSound receive = AppSound.chatReceive;
}

/// Injectable one-shot sound player. Universal (any feature can use it).
/// Playback failures are silent no-ops and never block the caller.
abstract class SoundService {
  /// Preloads the clips so the first play has no cold-start latency.
  Future<void> preload();

  /// Plays [sound] if audio is available. Never throws.
  void play(AppSound sound);
}

/// Test double: records calls, plays nothing.
class FakeSoundService implements SoundService {
  final List<AppSound> played = [];
  int preloadCount = 0;

  @override
  Future<void> preload() async => preloadCount++;

  @override
  void play(AppSound sound) => played.add(sound);
}

/// Real player. One preloaded AudioPlayer per sound. iOS uses the ambient audio
/// context so the hardware silent switch / DND mute chat sounds automatically.
class AudioPlayerSoundService implements SoundService {
  AudioPlayerSoundService();

  // AssetSource paths are relative to the `assets/` prefix already declared in
  // pubspec, so they start at `sounds/…`.
  //
  // TODO(assets): the game_*.wav clips below are code seams — drop the designed
  // audio files into assets/sounds/ and declare them in pubspec. Until they
  // exist, per-asset load failures are caught individually (see preload), so a
  // missing game clip is a silent no-op and never breaks chat sounds.
  static const _assets = {
    AppSound.chatSend: 'sounds/chat_send.wav',
    AppSound.chatReceive: 'sounds/chat_receive.wav',
    AppSound.gameMatch: 'sounds/game_match.wav',
    AppSound.gameCardFlip: 'sounds/game_card_flip.wav',
    AppSound.gameReveal: 'sounds/game_reveal.wav',
    AppSound.gameTap: 'sounds/game_tap.wav',
    AppSound.gameComplete: 'sounds/game_complete.wav',
  };

  final Map<AppSound, AudioPlayer> _players = {};
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
        // Per-asset guard: a missing clip (e.g. game_*.wav not yet added) loads
        // nothing for that key and is skipped, without aborting the others.
        try {
          final player =
              AudioPlayer()
                ..setReleaseMode(ReleaseMode.stop)
                ..setPlayerMode(PlayerMode.lowLatency);
          await player.setSource(AssetSource(entry.value));
          _players[entry.key] = player;
        } catch (_) {
          if (kDebugMode) {
            debugPrint('[sound] ${entry.value} unavailable: silent no-op');
          }
        }
      }
      // Ready if at least one clip loaded; play() no-ops any missing key.
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
  void play(AppSound sound) {
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
