// lib/core/ui/feedback/audio_session.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attune/features/chat/utils/chat_log.dart';

/// Sets one player's audio context — callers pass `player.setAudioContext`.
/// A closure rather than an [AudioPlayer] so the coordinator (and its tests)
/// never need a real platform player.
typedef PlayerContextSetter = Future<void> Function(AudioContext context);

/// The only two audio sessions this app asks for. Explicit [AudioContext]s,
/// not [AudioContextConfig]: the config helper has no "no focus" option, its
/// iOS half is null off-iOS, and `respectSilence` cannot be combined with
/// `mixWithOthers` — so it can express neither of these correctly.
abstract final class AppAudioContexts {
  /// UI chirps. Android: AUDIOFOCUS_NONE (FocusManager.kt skips the focus
  /// request entirely, so music keeps playing) on the notification stream
  /// (muted by silent/vibrate ring mode) as a sonification. iOS: ambient —
  /// muted by the silent switch, mixes with other apps' audio.
  static final AudioContext chirp = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationCommunicationInstant,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// A voice note the person deliberately tapped: plays through the silent
  /// switch. Android takes TRANSIENT focus (the music app pauses and resumes
  /// when the note ends; AUDIOFOCUS_GAIN is permanent and Spotify never comes
  /// back from it). iOS: playback.
  static final AudioContext voiceNote = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
  );
}

/// The process-wide audio session. Injectable so the coordinator's rules can
/// be tested without a platform channel.
abstract class AudioSessionPort {
  Future<void> setGlobalContext(AudioContext context);
}

class AudioplayersSessionPort implements AudioSessionPort {
  const AudioplayersSessionPort();

  @override
  Future<void> setGlobalContext(AudioContext context) =>
      AudioPlayer.global.setAudioContext(context);
}

class FakeAudioSessionPort implements AudioSessionPort {
  final List<AudioContext> globalContexts = [];

  @override
  Future<void> setGlobalContext(AudioContext context) async =>
      globalContexts.add(context);
}

/// Single owner of "which audio session are we in".
///
/// Chirps and voice notes used to each set their own context and never
/// coordinate: on iOS `audioplayers_darwin` applies a per-player context to
/// the SHARED AVAudioSession (its own log says so), so one voice note left
/// every later chirp on the playback category — audible through the silent
/// switch and pausing other apps' music until restart. On Android the
/// package default (AUDIOFOCUS_GAIN) made every chirp request permanent
/// focus, which stops the person's music for good.
class AudioSessionCoordinator {
  AudioSessionCoordinator({required this.port, TargetPlatform? platform})
    : _platform = platform;

  final AudioSessionPort port;
  final TargetPlatform? _platform;
  TargetPlatform get _target => _platform ?? defaultTargetPlatform;

  int _playbackHolds = 0;

  /// True while at least one voice note holds the session.
  bool get playbackHeld => _playbackHolds > 0;

  /// App start / sound preload: the default for every player created later.
  Future<void> applyChirpGlobalContext() =>
      _setGlobalChirp('apply chirp context');

  /// Port failures (no plugin, platform error) must never surface as
  /// unhandled async errors: audio session is best-effort.
  Future<void> _setGlobalChirp(String what) async {
    try {
      await port.setGlobalContext(AppAudioContexts.chirp);
    } catch (error) {
      ChatLog.diagnostic('audio session: $what failed', error);
    }
  }

  /// Once per preloaded chirp player. On Android this is what actually
  /// decides focus/stream per player; on iOS it (re)applies the global.
  Future<void> configureChirpPlayer(PlayerContextSetter set) =>
      set(AppAudioContexts.chirp);

  /// Immediately before a chirp plays.
  ///
  /// iOS only: AVAudioSession is global and anything (a voice note, a video
  /// message, the streak viewer — video_player upgrades the category to
  /// playback when it creates a player) may have left it on playback, and
  /// nothing else ever puts ambient back. Skipped while a voice note holds
  /// the session: the chirp then plays under the borrowed session rather
  /// than muting the note someone is listening to. Android keeps the
  /// per-player context from [configureChirpPlayer], so nothing to do.
  Future<void> beforeChirp(PlayerContextSetter set) async {
    if (_target != TargetPlatform.iOS || playbackHeld) return;
    await set(AppAudioContexts.chirp);
  }

  /// A voice note is about to play: borrow the session.
  Future<void> beginPlayback(PlayerContextSetter set) async {
    _playbackHolds++;
    try {
      await set(AppAudioContexts.voiceNote);
    } catch (_) {
      // An endPlayback may have already released this hold while the set
      // was in flight; never go negative.
      if (_playbackHolds > 0) _playbackHolds--;
      rethrow;
    }
  }

  /// The voice note paused, completed, failed or was disposed: give the
  /// session back once the LAST hold is released. Counted, not boolean —
  /// cross-bubble auto-pause can overlap the next bubble's play.
  Future<void> endPlayback() async {
    if (_playbackHolds == 0) return;
    _playbackHolds--;
    if (_playbackHolds > 0) return;
    await _setGlobalChirp('release playback');
  }
}

final audioSessionProvider = Provider<AudioSessionCoordinator>(
  (ref) => AudioSessionCoordinator(port: const AudioplayersSessionPort()),
);
