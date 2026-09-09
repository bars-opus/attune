import 'package:attune/features/games/presentation/widgets/game_hub_theme.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';

/// One game in the hub's grid.
///
/// The tile, the name, and one line of what it is. The colour comes from
/// the game rather than the theme, so a player learns the shelf by hue
/// before they learn it by name — which is the whole reason for
/// GamePalette existing.
class GameGridTile extends StatelessWidget {
  const GameGridTile({
    super.key,
    required this.gameType,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.comingSoon = false,
  });

  final String gameType;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(gameType);

    return Semantics(
      button: !comingSoon,
      label: comingSoon ? '$title, coming soon' : '$title. $subtitle',
      child: Opacity(
        // Dimmed rather than hidden: the catalogue doubles as a roadmap,
        // and a greyed row still tells you the game is planned.
        opacity: comingSoon ? 0.45 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: comingSoon ? null : onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A subtle wash of the game's colour behind the tile,
                  // so the identity extends past the icon's edges without
                  // needing a second gradient.
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: palette.glow.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: GameIcon(gameType: gameType, size: 56),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GameHubTheme.primaryText,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comingSoon ? 'Coming soon' : subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: GameHubTheme.mutedText,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
