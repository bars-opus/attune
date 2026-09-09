import 'package:attune/features/games/presentation/widgets/game_hub_theme.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';

/// One game in the hub's grid: a coloured card with its icon and its
/// words on it.
///
/// THE CARD IS THE COLOUR, not just the icon. An icon-over-caption layout
/// puts the game's identity in a 56px square and leaves the rest of the
/// tile as background, so a grid of ten reads as a grid of grey with
/// coloured dots. Filling the card means the shelf is legible by hue from
/// arm's length, which is the whole point of giving each game one.
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
        // and a greyed card still says the game is planned.
        opacity: comingSoon ? 0.5 : 1,
        child: AspectRatio(
          // Slightly taller than wide, as the reference is: a square card
          // leaves the two text lines cramped against the icon.
          aspectRatio: 0.86,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                color: palette.end,
                // gradient: LinearGradient(
                //   // The card's own gradient, deeper than the icon tile's
                //   // so the icon still reads as a distinct object sitting
                //   // ON it rather than dissolving into it.
                //   colors: [
                //     Color.lerp(palette.start, Colors.black, 0.42)!,
                //     Color.lerp(palette.end, Colors.black, 0.55)!,
                //   ],
                //   begin: Alignment.topLeft,
                //   end: Alignment.bottomRight,
                // ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                onTap: comingSoon ? null : onTap,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: GameIcon(gameType: gameType, size: 100)),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: GameHubTheme.primaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        comingSoon ? 'Coming soon' : subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // Tinted toward the card's own hue rather than
                          // flat grey, so the subtitle belongs to the
                          // card instead of sitting on top of it.
                          color: Color.lerp(
                            palette.start,
                            GameHubTheme.primaryText,
                            0.55,
                          )!.withValues(alpha: 0.85),
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
