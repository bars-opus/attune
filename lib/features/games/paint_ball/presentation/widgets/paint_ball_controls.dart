// lib/features/games/paint_ball/presentation/widgets/paint_ball_controls.dart

import 'package:attune/core/utils/exports/export_screens.dart';

class PaintBallControls extends StatelessWidget {
  final bool isMyTurn;
  final bool isSubmitting;

  const PaintBallControls({
    super.key,
    required this.isMyTurn,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.md.w,
        Spacing.md.h,
        Spacing.md.w,
        Spacing.sm.h,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.md.h,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isMyTurn
                ? colorScheme.primary.withValues(alpha: 0.18)
                : colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSubmitting ? Icons.hourglass_top : Icons.touch_app,
              size: 18.sp,
              color: isMyTurn
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.55),
            ),
            Gap(Spacing.sm.w),
            Expanded(
              child: Text(
                isSubmitting
                    ? 'Resolving shot...'
                    : isMyTurn
                        ? 'Tap the arena when the marker feels right.'
                        : 'Waiting for your partner to take the next shot.',
                style: textTheme.bodySmall?.copyWith(
                  color: isMyTurn
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
