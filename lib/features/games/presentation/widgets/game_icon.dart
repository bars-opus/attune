import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';

/// A game's tile: its glyph on its own gradient, lit from underneath.
///
/// THE SVG ILLUSTRATIONS ARE GONE. Two games had drawn logos and six did
/// not, so the shelf was two illustrations sitting beside six Material
/// glyphs and reading as unfinished. A consistent set of glyphs on
/// per-game gradients looks deliberate at eight games and stays that way
/// at twelve, which a hand-drawn set only manages if every new game waits
/// for an illustrator.
///
/// The tile carries the game's colour (see [GamePalette]) so the same
/// identity shows up in the grid, in the row and beside a chat card.
class GameIcon extends StatelessWidget {
  const GameIcon({
    super.key,
    required this.gameType,
    required this.size,
    this.fallbackColor,
    this.radius,
  });

  final String gameType;
  final double size;

  /// Ignored by the tile, kept so existing callers compile. The glyph
  /// takes its colour from the palette now.
  final Color? fallbackColor;

  final double? radius;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(gameType);
    final corner = radius ?? size * 0.28;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: palette.gradient,
        borderRadius: BorderRadius.circular(corner),
        boxShadow: [
          // A COLOURED shadow, not a neutral one. A grey drop shadow
          // reads as a card lying on a surface; the tile's own hue
          // bleeding underneath reads as something lit, which is what
          // makes a dark shelf feel alive rather than flat.
          BoxShadow(
            color: palette.glow.withValues(alpha: 0.35),
            blurRadius: size * 0.32,
            offset: Offset(0, size * 0.10),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          gameGlyphFor(gameType),
          size: size * 0.52,
          color: palette.onTile,
        ),
      ),
    );
  }
}

/// The glyph for a game.
///
/// Distinct from the catalogue's icon on purpose: the catalogue picks
/// icons that read at 20px in a list, and a tile needs a shape that holds
/// up filled and large. Falls back to the catalogue's choice for anything
/// this map has not been taught.
IconData gameGlyphFor(String gameType) =>
    _glyphs[gameType] ??
    chatGameIconForType(gameType) ??
    Icons.sports_esports_rounded;

const Map<String, IconData> _glyphs = {
  // A fork in the road: two options, pick one.
  'this_or_that': Icons.alt_route_rounded,
  // A flame. The spicy one, without being literal about it.
  'truth_or_dare': Icons.local_fire_department_rounded,
  // A question, asked thirty-six times.
  '36_questions': Icons.forum_rounded,
  // Two halves facing each other.
  'mirror': Icons.flip_rounded,
  // A spectrum with a position on it.
  'sliding_scale': Icons.tune_rounded,
  // A branch: what would you do if.
  'scenario': Icons.account_tree_rounded,
  // How well you know the terrain of another person.
  'love_map': Icons.explore_rounded,
  // The shot.
  'paint_ball': Icons.gps_fixed_rounded,
  // The die. The whole game is the die.
  'snakes_and_ladders': Icons.casino_rounded,
  // The grid you search.
  'word_hunt': Icons.grid_view_rounded,
};
