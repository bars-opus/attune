import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_registry.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_controller.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every game, in the order the hub shows them.
///
/// Titles come from gameTypeDisplayName and icons from gameGlyphFor, and
/// each tagline is the chat sheet's subtitle for that game, so the hub and
/// the chat name a game the same way until phase 5 makes this the source
/// for all of them. The two prototypes are not games Attune offers and are
/// not listed.
final List<GameDefinition> gameCatalogue = [
  thisOrThatGame,
  _launch(
    'truth_or_dare',
    colour: GameColors.truthOrDare,
    collectionLabel: 'Fun and playful',
    tagline: 'Playful prompts for two',
    heroWord: 'DARE',
  ),
  _launch(
    '36_questions',
    colour: GameColors.thirtySixQuestions,
    collectionLabel: 'Go deeper',
    tagline: 'A slow, guided way to feel closer',
    heroWord: '36',
  ),
  _launch(
    'word_hunt',
    colour: GameColors.wordHunt,
    collectionLabel: 'Arcade',
    tagline: 'One hidden word, who spots it first',
    heroWord: 'WORD',
  ),
  _launch(
    'snakes_and_ladders',
    colour: GameColors.snakesAndLadders,
    collectionLabel: 'Arcade',
    tagline: 'No questions, just a die',
    heroWord: 'ROLL',
  ),
  // Coming soon, but with screens: a session started before a game was
  // pulled back still opens.
  _comingSoon('mirror', tagline: 'How well do you read each other right now?'),
  _comingSoon('sliding_scale', tagline: 'Where you each land on what matters'),
  _comingSoon('scenario', tagline: 'What you would each do, and why'),
  _comingSoon(
    'love_map',
    tagline: 'Their inner world, a few prompts at a time',
  ),
  _comingSoon('paint_ball', tagline: 'Turn-based color battle'),
  // No screens at all: nothing to open.
  _comingSoon(
    'never_have_i_ever',
    tagline: 'Light confessions and laughs',
    openable: false,
  ),
];

/// The games, for the hub and the landing pages.
final gameRegistryProvider = Provider<GameRegistry>(
  (ref) => GameRegistry(gameCatalogue),
);

GameDefinition _launch(
  String gameType, {
  required Color colour,
  required String collectionLabel,
  required String tagline,
  required String heroWord,
}) {
  return GameDefinition(
    gameType: gameType,
    title: gameTypeDisplayName(gameType),
    collectionLabel: collectionLabel,
    tagline: tagline,
    theme: GameTheme(primary: colour),
    icon: gameGlyphFor(gameType),
    heroBuilder:
        (context, theme) => GameLetterTiles(word: heroWord, tileSize: 52),
    controller: LegacyGameController(gameType),
  );
}

GameDefinition _comingSoon(
  String gameType, {
  required String tagline,
  bool openable = true,
}) {
  return GameDefinition(
    gameType: gameType,
    title: gameTypeDisplayName(gameType),
    collectionLabel: GameStrings.comingSoon,
    tagline: tagline,
    theme: const GameTheme(primary: GameColors.comingSoon),
    icon: gameGlyphFor(gameType),
    heroBuilder: (context, theme) => const SizedBox.shrink(),
    controller: openable ? LegacyGameController(gameType) : null,
    availability: GameAvailability.comingSoon,
  );
}
