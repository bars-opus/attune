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
    final hasAnswered = answer != null;

    return OnboardingStepFrame(
      title: 'Relationship reflection quiz',
      subtitle:
          'Question ${questionIndex + 1} of ${attachmentQuestions.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (questionIndex + 1) / attachmentQuestions.length,
          ),
          Gap(Spacing.lg.h),
          Text(question.prompt, style: Theme.of(context).textTheme.titleLarge),
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
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Back',
                  onPressed: onBack,
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                  height: OnboardingTokens.actionButtonHeight.h,
                ),
              ),
              Gap(Spacing.smMd.w),
              Expanded(
                child: AppButton(
                  label: isLastQuestion ? 'Finish quiz' : 'Next',
                  // Gated: you cannot advance past a question you never
                  // answered, so the reflection we store is real.
                  onPressed: hasAnswered ? onNext : null,
                  size: ButtonSize.small,
                  height: OnboardingTokens.actionButtonHeight.h,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
