import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something that just happened in a game.
///
/// Games name the event and nothing else. Which clip plays and how the phone
/// taps back is decided here, once, so every game answers a tap the same way
/// and a new sound pack is a change to this file rather than to ten games.
enum GameEvent {
  /// A finger chose something.
  tap,

  /// A piece or an answer went down.
  place,

  /// Two things agreed: a match, a found word.
  match,

  /// Something hidden was shown.
  reveal,

  /// The move passed to the other player.
  turn,

  /// The game finished.
  complete,
}

class GameFeedback {
  GameFeedback(this._ref);

  final Ref _ref;

  /// The clip for each event. Every event has one.
  static const Map<GameEvent, AppSound> sounds = {
    GameEvent.tap: AppSound.gameTap,
    GameEvent.place: AppSound.gameAnswer,
    GameEvent.match: AppSound.gameMatch,
    GameEvent.reveal: AppSound.gameReveal,
    GameEvent.turn: AppSound.gameAnswer,
    GameEvent.complete: AppSound.gameComplete,
  };

  void fire(GameEvent event) {
    final prefs = _ref.read(gamePrefsProvider);

    if (prefs.sound) {
      _ref.read(soundServiceProvider).play(sounds[event]!);
    }
    if (!prefs.haptics) return;

    final haptics = _ref.read(hapticsProvider);
    switch (event) {
      case GameEvent.tap:
        haptics.selection();
      case GameEvent.place:
      case GameEvent.reveal:
      case GameEvent.turn:
        haptics.light();
      case GameEvent.match:
      case GameEvent.complete:
        haptics.medium();
    }
  }
}

final gameFeedbackProvider = Provider<GameFeedback>(GameFeedback.new);
