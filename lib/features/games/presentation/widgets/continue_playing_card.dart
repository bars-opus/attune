import 'package:attune/features/games/presentation/widgets/game_hub_theme.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';

/// A game in progress, as a wide card in a horizontal rail.
///
/// Wide rather than a list row because there are rarely more than two or
/// three of these, and a full-width row per game pushed the actual
/// catalogue below the fold. A rail shows two at a time and hints at a
/// third by cutting it off at the edge — which is also how a person knows
/// to swipe.
class ContinuePlayingCard extends StatelessWidget {
  const ContinuePlayingCard({
    super.key,
    required this.gameType,
    required this.title,
    required this.status,
    required this.onTap,
    this.isYourTurn = false,
  });

  final String gameType;
  final String title;
  final String status;
  final VoidCallback? onTap;

  /// Drives the accent dot. Whose move it is, is the only thing anyone
  /// opens this rail to find out.
  final bool isYourTurn;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of(gameType);

    return Semantics(
      button: onTap != null,
      label: '$title. $status',
      child: SizedBox(
        width: 232,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                // The card takes a faint version of the game's own
                // gradient, so a rail of three in-progress games reads as
                // three different games at a glance rather than three
                // identical grey cards.
                gradient: LinearGradient(
                  colors: [
                    palette.start.withValues(alpha: 0.16),
                    palette.end.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.glow.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  GameIcon(gameType: gameType, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: GameHubTheme.primaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (isYourTurn) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: palette.start,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      isYourTurn
                                          ? palette.start
                                          : GameHubTheme.secondaryText,
                                  fontSize: 11.5,
                                  fontWeight:
                                      isYourTurn
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
