import 'package:attune/core/utils/exports/export_screens.dart';

class VerificationCodeCountdown extends StatelessWidget {
  const VerificationCodeCountdown({super.key, required this.secondsRemaining});

  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.sm.h,
        ),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.full.r),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
            width: BorderWidthTokens.thin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: IconSizes.sm.r,
              color: colorScheme.primary,
            ),
            Gap(Spacing.xs.w),
            Text(
              'Resend available in ${secondsRemaining}s',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
