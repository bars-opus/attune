// lib/features/games/paint_ball/presentation/widgets/paint_ball_lives_display.dart

import 'package:attune/core/utils/exports/export_screens.dart';
class PaintBallLivesDisplay extends StatelessWidget {
  final int myLives;
  final int opponentLives;
  final bool isMyTurn;

  const PaintBallLivesDisplay({
    super.key,
    required this.myLives,
    required this.opponentLives,
    required this.isMyTurn,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
      child: Row(
        children: [
          // Opponent lives
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Opponent',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Gap(Spacing.xs.h),
                _buildLivesRow(context, opponentLives, isOpponent: true),
              ],
            ),
          ),

          // VS separator
          Container(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              'VS',
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isMyTurn ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),

          // My lives
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'You',
                  style: textTheme.labelMedium?.copyWith(
                    color:
                        isMyTurn
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Gap(Spacing.xs.h),
                _buildLivesRow(context, myLives, isOpponent: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivesRow(
    BuildContext context,
    int lives, {
    required bool isOpponent,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment:
          isOpponent ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: List.generate(3, (index) {
        final hasLife = index < lives;
        return Container(
          margin: EdgeInsets.only(
            right: isOpponent ? 4.w : 0,
            left: isOpponent ? 0 : 4.w,
          ),
          width: 24.w,
          height: 24.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                hasLife
                    ? (isOpponent ? colorScheme.secondary : colorScheme.primary)
                    : colorScheme.surface,
            border: Border.all(
              color:
                  hasLife
                      ? (isOpponent
                          ? colorScheme.secondary
                          : colorScheme.primary)
                      : colorScheme.outline.withValues(alpha: 0.2),
              width: 2.r,
            ),
          ),
          child: Center(
            child:
                hasLife
                    ? Icon(
                      Icons.favorite,
                      size: 14.sp,
                      color:
                          isOpponent
                              ? colorScheme.onSecondary
                              : colorScheme.onPrimary,
                    )
                    : Icon(
                      Icons.favorite_border,
                      size: 14.sp,
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                    ),
          ),
        );
      }),
    );
  }
}
