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
                // Flat palette.end, matching the grid card. The same fill
                // in both places means one game looks like itself
                // wherever it appears -- the translucent gradient this
                // replaced rendered as near-black on the dark sheet, so
                // a rail of three read as three identical grey cards.
                color: palette.end,
                borderRadius: BorderRadius.circular(20),
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
                                decoration: const BoxDecoration(
                                  color: Colors.white,
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
                                  // On a solid card the old
                                  // secondary grey sank into the
                                  // fill. White at reduced opacity
                                  // reads against every palette.end.
                                  Colors.white.withValues(
                                    alpha: isYourTurn ? 0.95 : 0.62,
                                  ),
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
