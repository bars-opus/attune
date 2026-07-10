import 'package:attune/core/utils/exports/export_screens.dart';

class TruthOrDareRoundResultScreen extends StatelessWidget {
  const TruthOrDareRoundResultScreen({
    super.key,
    required this.questionType,
    required this.questionText,
    required this.partnerName,
    required this.answerText,
    required this.roundNumber,
    required this.totalRounds,
    required this.onNext,
  });

  final String questionType;
  final String questionText;
  final String partnerName;
  final String? answerText;
  final int roundNumber;
  final int totalRounds;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isTruth = questionType == 'truth';

    return Scaffold(
      appBar: AppBar(
        title: Text('Truth or Dare • Round $roundNumber/$totalRounds'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.sm.w,
                vertical: Spacing.xs.h,
              ),
              decoration: BoxDecoration(
                color:
                    isTruth
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isTruth ? '🗣' : '🎯', style: const TextStyle(fontSize: 16)),
                  Gap(Spacing.xs.w),
                  Text(
                    isTruth ? 'Truth completed!' : 'Dare completed!',
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isTruth ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.lg.h),
            Text(
              isTruth
                  ? '$partnerName answered:'
                  : '$partnerName completed this dare:',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(questionText, style: textTheme.bodyLarge),
            Gap(Spacing.lg.h),
            if (isTruth)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Text(
                  answerText ?? '',
                  style: textTheme.bodyLarge,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    Gap(Spacing.sm.w),
                    Text(
                      'Completed',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            AppButton(
              label: roundNumber >= totalRounds ? 'See summary' : 'Next',
              onPressed: onNext,
              width: double.infinity,
              size: ButtonSize.large,
            ),
          ],
        ),
      ),
    );
  }
}
