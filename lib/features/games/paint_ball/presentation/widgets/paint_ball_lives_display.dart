// lib/features/games/paint_ball/presentation/widgets/paint_ball_lives_display.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';

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
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
      child: Semantics(
        container: true,
        label:
            'Your partner has $opponentLives lives. You have $myLives lives. '
            '${isMyTurn ? 'It is your turn.' : 'It is your partner\'s turn.'}',
        child: ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THEM  $opponentLives',
                      style: textTheme.labelMedium?.copyWith(
                        color: PaintBallPalette.theirs,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Gap(Spacing.xs.h),
                    _buildLivesRow(context, opponentLives, isOpponent: true),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                child: Text(
                  isMyTurn ? 'YOUR MOVE' : 'THEIR MOVE',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.62),
                    letterSpacing: 0,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'YOU  $myLives',
                      style: textTheme.labelMedium?.copyWith(
                        color: PaintBallPalette.mine,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Gap(Spacing.xs.h),
                    _buildLivesRow(context, myLives, isOpponent: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLivesRow(
    BuildContext context,
    int lives, {
    required bool isOpponent,
  }) {
    final color = isOpponent ? PaintBallPalette.theirs : PaintBallPalette.mine;

    return Row(
      mainAxisAlignment:
          isOpponent ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: List.generate(3, (index) {
        final hasLife = index < lives;
        return AnimatedContainer(
          duration:
              reduceMotionOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
          margin: EdgeInsets.only(
            right: isOpponent ? 5.w : 0,
            left: isOpponent ? 0 : 5.w,
          ),
          width: 18.w,
          height: 18.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasLife ? color : Colors.transparent,
            border: Border.all(
              color: color.withValues(alpha: hasLife ? 1 : 0.30),
              width: 1.5.r,
            ),
          ),
        );
      }),
    );
  }
}
