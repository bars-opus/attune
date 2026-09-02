import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The illustrated tile for a game, where one exists.
///
/// Returns null for a game whose art has not been drawn yet, so callers
/// fall back to the catalogue's Material icon rather than showing a gap.
/// The set is filled in one game at a time; a missing asset must never be
/// a broken image.
String? gameIconAsset(String gameType) {
  const drawn = {'this_or_that', 'truth_or_dare'};
  if (!drawn.contains(gameType)) return null;
  return 'assets/images/game_icons/$gameType.svg';
}

/// A game's icon: its illustration, or the catalogue glyph as a fallback.
///
/// The illustrations carry their own light tile, which is what lets them
/// be full colour: a coloured mark drawn straight onto the chat wallpaper
/// would have to solve light and dark itself, and one of eight would
/// eventually fail on the dark background.
///
/// The fallback is tinted, because a Material glyph has no tile of its
/// own and does need to follow the theme.
class GameIcon extends StatelessWidget {
  const GameIcon({
    super.key,
    required this.gameType,
    required this.size,
    this.fallbackColor,
  });

  final String gameType;
  final double size;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final asset = gameIconAsset(gameType);

    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        // The tile is part of the artwork, so it is drawn as-is rather
        // than tinted to the theme.
        fit: BoxFit.contain,
      );
    }

    return Icon(
      chatGameIconForType(gameType) ?? Icons.sports_esports_outlined,
      size: size,
      color: fallbackColor ?? Theme.of(context).colorScheme.primary,
    );
  }
}
