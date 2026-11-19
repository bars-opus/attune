import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// A made-up game, for exercising the shell without a real one.
GameDefinition demoGame({
  bool withSettings = false,
  bool withEntries = true,
  GameAvailability availability = GameAvailability.launch,
  String gameType = 'demo',
  Color color = GameColors.wordHunt,
}) {
  return GameDefinition(
    gameType: gameType,
    title: 'Tile Tutorial',
    collectionLabel: 'Starter pack',
    tagline: 'Learn how the shell fits together.',
    theme: GameTheme(primary: color),
    heroBuilder:
        (context, theme) =>
            const GameLetterTiles(word: 'PLAY', tileSize: 52, animate: false),
    entriesBuilder:
        withEntries
            ? (context) => const [
              GameEntry(title: 'Learn the basics'),
              GameEntry(title: 'Themes', subtitle: 'Pick a mood'),
              GameEntry(title: 'Past games'),
            ]
            : null,
    howToPlay: const [
      'Tap a tile to pick it.',
      'Your partner answers the same question.',
      'See both answers together.',
    ],
    settingsBuilder:
        withSettings ? (context) => const Text('Demo game settings') : null,
    availability: availability,
  );
}
