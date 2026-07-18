import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

class AttachmentQuizStep extends StatelessWidget {
  const AttachmentQuizStep({
    super.key,
    required this.questionIndex,
    required this.answers,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final int questionIndex;
  final List<int?> answers;
  final ValueChanged<int> onChanged;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final question = attachmentQuestions[questionIndex];
    final isLastQuestion = questionIndex == attachmentQuestions.length - 1;
    final answer = answers[questionIndex];
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasAnswered = answer != null;

    return OnboardingStepFrame(
      title: 'Relationship reflection quiz',
      subtitle:
          'Question ${questionIndex + 1} of ${attachmentQuestions.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LinearProgressIndicator(
            value: (questionIndex + 1) / attachmentQuestions.length,
          ),
          Gap(Spacing.lg.h),

          Container(
            padding: EdgeInsets.all(Spacing.sm.w),
            decoration: BoxDecoration(
              color: colorScheme.onBackground,
              shape: BoxShape.circle,
            ),
            child: Text(
              '4',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.background,
              ),
            ),
          ),
          Gap(Spacing.lg.h),
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onBackground,
            ),
          ),
          Gap(Spacing.sm.h),
          Text(
            question.prompt,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.onBackground),
          ),
          Gap(Spacing.lg.h),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 5, label: Text('5')),
            ],
            // Empty until the user actually picks: an untouched question must
            // not look answered.
            emptySelectionAllowed: true,
            selected: hasAnswered ? {answer} : const <int>{},
            onSelectionChanged: (values) {
              if (values.isEmpty) return;
              onChanged(values.first);
            },
          ),
          Gap(Spacing.sm.h),
          Text(
            '1 = strongly disagree, 5 = strongly agree',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          // A fixed gap rather than a Spacer: Spacer demands a bounded height,
          // which conflicts with the card's scroll fallback on short screens
          // (it expands to infinity when the height is unbounded). A fixed gap
          // gives the column a natural intrinsic height, so it lays out the
          // same when there is room and scrolls when there isn't.
          Gap(Spacing.xl.h),
          AppButton(
            label: isLastQuestion ? 'Finish quiz' : 'Next',
            // Gated: you cannot advance past a question you never
            // answered, so the reflection we store is real.
            onPressed: hasAnswered ? onNext : null,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
          Gap(Spacing.sm.h),
          AppButton(
            label: 'Back',
            onPressed: onBack,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
          // Row(
          //   children: [
          //     Expanded(
          //   child: AppButton(
          //     label: 'Back',
          //     onPressed: onBack,
          //     variant: ButtonVariant.outline,
          //     size: ButtonSize.small,
          //     height: OnboardingTokens.actionButtonHeight.h,
          //   ),
          // ),
          //     Gap(Spacing.smMd.w),
          //     Expanded(
          //       child: AppButton(
          //         label: isLastQuestion ? 'Finish quiz' : 'Next',
          //         // Gated: you cannot advance past a question you never
          //         // answered, so the reflection we store is real.
          //         onPressed: hasAnswered ? onNext : null,
          //         size: ButtonSize.small,
          //         height: OnboardingTokens.actionButtonHeight.h,
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }
}
