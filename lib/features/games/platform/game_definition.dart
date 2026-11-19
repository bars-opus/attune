import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/widgets.dart';

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
  final void Function(BuildContext context)? onTap;
}

typedef GameHeroBuilder =
    Widget Function(BuildContext context, GameTheme theme);
typedef GameEntriesBuilder = List<GameEntry> Function(BuildContext context);
typedef GameSettingsBuilder = Widget Function(BuildContext context);

/// Enters play: a new game when [sessionId] is null, that session otherwise.
typedef GameOpen =
    Future<void> Function(BuildContext context, {String? sessionId});

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
    required this.heroBuilder,
    this.entriesBuilder,
    this.howToPlay = const [],
    this.settingsBuilder,
    this.open,
    this.availability = GameAvailability.launch,
  });

  /// The `game_sessions.game_type` value.
  final String gameType;

  final String title;

  /// The small label over the title, such as "CONVERSATION GAME".
  final String collectionLabel;

  final String tagline;
  final GameTheme theme;

  /// Draws the tile art at the top of the landing page.
  final GameHeroBuilder heroBuilder;

  /// The rows under the Play button. Null means none.
  final GameEntriesBuilder? entriesBuilder;

  /// The rules, a sentence each, for the "?" button.
  final List<String> howToPlay;

  /// The game's own settings tab. Null hides the tab.
  final GameSettingsBuilder? settingsBuilder;

  /// How play is entered. Wraps the game's existing routes.
  final GameOpen? open;

  final GameAvailability availability;
}
