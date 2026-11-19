import 'package:attune/features/games/platform/game_strings.dart';
import 'package:flutter/material.dart';

/// Where the two players stand in a game.
enum GameLandingStatus {
  /// The game's state has not arrived yet.
  loading,

  /// No game in progress.
  fresh,

  /// The partner started one and is waiting for this player.
  invited,

  /// A game is in progress and this player can act.
  yourTurn,

  /// A game is in progress and the partner has to act.
  waiting,

  /// The last game is over.
  finished,

  /// The game is listed but cannot be started yet.
  comingSoon,
}

@immutable
class GameLandingState {
  const GameLandingState({
    required this.status,
    this.sessionId,
    this.partnerName,
    this.caption,
    this.canRemind = false,
  });

  final GameLandingStatus status;

  /// The session this state describes, when there is one.
  final String? sessionId;

  /// Named on the button while waiting. Null falls back to "your partner".
  final String? partnerName;

  /// Where the game stands, such as "Round 3 of 10". Shown under the button.
  final String? caption;

  /// Whether a reminder can be sent right now. Only read while waiting.
  final bool canRemind;
}

/// What the landing page's one button says and whether it can be pressed.
@immutable
class GameLandingAction {
  const GameLandingAction({
    required this.label,
    required this.enabled,
    this.icon,
  });

  final String label;
  final bool enabled;
  final IconData? icon;
}

/// The button for a state.
///
/// Pure, so each state is checked without building a screen. The button is
/// what makes this page about two people rather than one: the same game
/// says Play, Your turn or Waiting for Ama depending on who has to move.
GameLandingAction landingAction(GameLandingState state) {
  switch (state.status) {
    case GameLandingStatus.loading:
      // Says what it will most likely say, so the page does not jump when
      // the state arrives, but cannot start a second game meanwhile.
      return const GameLandingAction(
        label: GameStrings.play,
        enabled: false,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.fresh:
      return const GameLandingAction(
        label: GameStrings.play,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.invited:
      return const GameLandingAction(
        label: GameStrings.join,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.yourTurn:
      return const GameLandingAction(
        label: GameStrings.yourTurn,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.waiting:
      final name = state.partnerName?.trim();
      return GameLandingAction(
        label:
            name == null || name.isEmpty
                ? GameStrings.waitingForPartner
                : GameStrings.waitingFor(name),
        // Waiting is information, not an action: there is nothing this
        // player can do in the game until the partner moves.
        enabled: false,
      );
    case GameLandingStatus.finished:
      return const GameLandingAction(
        label: GameStrings.playAgain,
        enabled: true,
        icon: Icons.replay_rounded,
      );
    case GameLandingStatus.comingSoon:
      return const GameLandingAction(
        label: GameStrings.comingSoon,
        enabled: false,
      );
  }
}
