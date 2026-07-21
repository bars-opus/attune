import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';
import 'package:attune/features/quiz/presentation/widgets/quiz_question_card.dart';

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
    final hasAnswered = answer != null;

    return OnboardingStepFrame(
      title: 'Relationship reflection quiz',
      icon: Icons.psychology_outlined,
      totalSegments: attachmentQuestions.length,
      progressValue: (questionIndex + 1) / attachmentQuestions.length,
      subtitle:
          'Question ${questionIndex + 1} of ${attachmentQuestions.length}',
      child: QuizQuestionCard(
        questionNumber: questionIndex + 1,
        prompt: question.prompt,
        description: question.description,
        value: answer,
        onChanged: onChanged,
        // One tag per question, so advancing does not try to fly the previous
        // question's card into the next one's.
        heroTag: 'attachment-$questionIndex',
        footer: Column(
          children: [
            // A fixed gap rather than a Spacer: Spacer demands a bounded
            // height, which conflicts with the card's scroll fallback on short
            // screens (it expands to infinity when the height is unbounded).
            Gap(Spacing.xl.h),
            AppButton(
              textColor: colorScheme.surface,
              label: isLastQuestion ? 'Finish quiz' : 'Next',
              // Gated: you cannot advance past a question you never
              // answered, so the reflection we store is real.
              onPressed: hasAnswered ? onNext : null,
              size: ButtonSize.small,
              elevation: 0,
              height: OnboardingTokens.actionButtonHeight.h,
            ),
            // No Back on the first question — there is nothing to go back to.
            if (onBack != null) ...[
              Gap(Spacing.sm.h),
              AppTextButton(
                alignment: Alignment.center,
                text: 'Back',
                fontSize: 12,
                onPressed: onBack,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
