import 'package:flutter/material.dart';

/// A colour identity per game, used by its tile, its icon and its rows.
///
/// DARK ONLY. The games hub does not follow the app theme: it is a dark
/// surface whatever the rest of the app is doing, the way a storefront
/// is. That decision is what lets these colours be saturated — a palette
/// that has to survive a white background ends up muted, and muted is
/// the opposite of what a shelf of games should look like.
///
/// Each game gets a hue that says something about it rather than being
/// picked off a wheel: the Arcade games are cool and electric, the
/// disclosure games are warm, and the slow ones are deep.
@immutable
class GamePalette {
  const GamePalette({
    required this.start,
    required this.end,
    required this.glow,
    required this.onTile,
  });

  /// Top-left of the tile gradient.
  final Color start;

  /// Bottom-right of the tile gradient.
  final Color end;

  /// The colour that bleeds under the tile. Same hue, low alpha — a tile
  /// with no shadow reads as a sticker; one with a neutral drop shadow
  /// reads as a card. A COLOURED shadow reads as lit.
  final Color glow;

  /// Icon and label on top of the gradient.
  final Color onTile;

  LinearGradient get gradient => LinearGradient(
    colors: [start, end],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _fallback = GamePalette(
    start: Color(0xFF3A3A42),
    end: Color(0xFF23232A),
    glow: Color(0xFF3A3A42),
    onTile: Color(0xFFEDEDF2),
  );

  /// The game's identity, or a neutral slate for anything unrecognised.
  static GamePalette of(String? gameType) => _byType[gameType] ?? _fallback;

  static const Map<String, GamePalette> _byType = {
    // ---- Disclosure games: warm, because they ask something of you ----

    // Two doors. Amber into rose: a fork, and a slightly playful one.
    'this_or_that': GamePalette(
      start: Color(0xFFFFB65C),
      end: Color(0xFFE8555F),
      glow: Color(0xFFFF8A4C),
      onTile: Color(0xFF2A0F12),
    ),

    // The spicy one. Deep magenta into red — heat, not danger.
    'truth_or_dare': GamePalette(
      start: Color(0xFFFF6B8B),
      end: Color(0xFFB4245E),
      glow: Color(0xFFFF4D7D),
      onTile: Color(0xFF33040F),
    ),

    // 36 Questions: the long, earnest one. Violet, the colour of the
    // late-night conversation it is trying to produce.
    '36_questions': GamePalette(
      start: Color(0xFF9B7BFF),
      end: Color(0xFF5B3FD1),
      glow: Color(0xFF8B6BFF),
      onTile: Color(0xFF130A33),
    ),

    // Mirror: what you think they think. Cool blue, reflective.
    'mirror': GamePalette(
      start: Color(0xFF7FC5FF),
      end: Color(0xFF3A6BD8),
      glow: Color(0xFF5AA0FF),
      onTile: Color(0xFF061530),
    ),

    // Sliding Scale: a spectrum. Teal into blue, a literal gradient.
    'sliding_scale': GamePalette(
      start: Color(0xFF6FE3C8),
      end: Color(0xFF2C7FB8),
      glow: Color(0xFF4FCFB5),
      onTile: Color(0xFF04241F),
    ),

    // Scenario: hypotheticals. Indigo, a little unreal.
    'scenario': GamePalette(
      start: Color(0xFF8E9BFF),
      end: Color(0xFF4436A8),
      glow: Color(0xFF6E7BFF),
      onTile: Color(0xFF0B0A2E),
    ),

    // Love Map: how well you know them. Warm coral, affectionate rather
    // than romantic-red.
    'love_map': GamePalette(
      start: Color(0xFFFF9E7D),
      end: Color(0xFFD84A6B),
      glow: Color(0xFFFF7E63),
      onTile: Color(0xFF320B14),
    ),

    // ---- Arcade: cool and electric, because nothing is being asked ----

    // Paint Ball. The game's own board is black with teal and red; the
    // tile borrows the teal so the shelf matches the game.
    'paint_ball': GamePalette(
      start: Color(0xFF5EEAD4),
      end: Color(0xFF0E7C86),
      glow: Color(0xFF3FD8C4),
      onTile: Color(0xFF032220),
    ),

    // Snakes and Ladders: up and down. Green into amber — the ladder and
    // the snake in one tile.
    'snakes_and_ladders': GamePalette(
      start: Color(0xFF7BD88F),
      end: Color(0xFFB88A1E),
      glow: Color(0xFF6FCB84),
      onTile: Color(0xFF06220E),
    ),

    // Word Hunt: the grid, the found word. Bright lime — quick and sharp,
    // matching a game that lasts thirty seconds.
    'word_hunt': GamePalette(
      start: Color(0xFFB8F26B),
      end: Color(0xFF3E8E2F),
      glow: Color(0xFF9FE256),
      onTile: Color(0xFF0B2408),
    ),
  };
}
