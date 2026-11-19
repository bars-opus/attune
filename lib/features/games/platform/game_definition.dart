import 'dart:async';

import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a game can be started.
enum GameAvailability {
  /// Playable.
  launch,

  /// Listed, not startable. A session already in progress stays reachable.
  comingSoon,
}

/// One row in the list under a game's Play button: a tone, a chapter, the
/// player's own questions, past games.
@immutable
class GameEntry {
  const GameEntry({required this.title, this.subtitle, this.onTap});

  final String title;
  final String? subtitle;

  /// May return a future, such as one that starts a game: the landing page
  /// takes no other tap until it completes, so two quick taps start one
  /// game, not two.
  final FutureOr<void> Function(BuildContext context)? onTap;
}

typedef GameHeroBuilder =
    Widget Function(BuildContext context, GameTheme theme);
typedef GameSettingsBuilder = Widget Function(BuildContext context);

/// What the shell needs from a game to show its landing page and get a
/// player into it.
abstract class GameController {
  const GameController();

  /// Where the couple's game stands. Called from build.
  GameLandingState watchLanding(WidgetRef ref);

  /// Play, Join, Your turn or Play again, according to [state].
  Future<void> onPrimary(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  );

  /// Only called when [state.canRemind].
  Future<void> onRemind(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) async {}

  /// The rows under the button.
  List<GameEntry> entries(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) => const [];

  /// Opens one session directly: from a chat card or the hub.
  Future<void> openSession(
    BuildContext context,
    WidgetRef ref, {
    required String sessionId,
  });
}

/// Everything the shell needs to know about one game.
///
/// The list of games used to be repeated in five places -- display names,
/// colours, icons, routes and the catalogue -- and a game added to one and
/// missed in another rendered as a raw database value or routed nowhere.
/// This is the one place.
@immutable
class GameDefinition {
  const GameDefinition({
    required this.gameType,
    required this.title,
    required this.collectionLabel,
    required this.tagline,
    required this.theme,
    required this.icon,
    required this.heroBuilder,
    this.howToPlay = const [],
    this.settingsBuilder,
    this.controller,
    this.availability = GameAvailability.launch,
  });

  /// The `game_sessions.game_type` value.
  final String gameType;

  final String title;

  /// The small label over the title, such as "CONVERSATION GAME".
  final String collectionLabel;

  final String tagline;
  final GameTheme theme;

  /// The game's small mark, where a list names it without its tile art.
  final IconData icon;

  /// Draws the tile art at the top of the landing page.
  final GameHeroBuilder heroBuilder;

  /// The rules, a sentence each, for the "?" button.
  final List<String> howToPlay;

  /// The game's own settings tab. Null hides the tab.
  final GameSettingsBuilder? settingsBuilder;

  /// Reads the couple's state and gets a player into the game. Null for a
  /// coming-soon game with no screens: there is nothing to open.
  final GameController? controller;

  final GameAvailability availability;
}
