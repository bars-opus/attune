// lib/features/quiz/presentation/widgets/question_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/question_data.dart';

class QuestionScreen extends StatelessWidget {
  final String title;
  final int screenIndex;
  final int totalScreens;
  final int? totalQuestionCount;
  final List<QuestionData> questions;
  final Map<int, int?> answers;
  final Function(int questionIndex, int value) onAnswerChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFirstScreen;
  final bool isLastScreen;

  const QuestionScreen({
    super.key,
    this.title = 'Attachment style',
    required this.screenIndex,
    required this.totalScreens,
    this.totalQuestionCount,
    required this.questions,
    required this.answers,
    required this.onAnswerChanged,
    required this.onNext,
    required this.onPrevious,
    required this.isFirstScreen,
    required this.isLastScreen,
  });

  bool get _allQuestionsAnswered {
    for (final question in questions) {
      if (answers[question.globalIndex] == null) {
        return false;
      }
    }
    return true;
  }

  double get _progress {
    final totalQuestions = totalQuestionCount ?? totalScreens * 5;
    final answeredCount = answers.values.where((v) => v != null).length;
    return answeredCount / totalQuestions;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: textTheme.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onPrevious,
        ),
      ),
      body: Column(
        children: [
          // Progress bar
          Container(
            height: 4,
            margin: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            ),
          ),
          // Screen indicator
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.md.w,
              vertical: Spacing.sm.h,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Screen ${screenIndex + 1} of $totalScreens',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          // Questions
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Column(
                children:
                    questions.asMap().entries.map((entry) {
                      final localIndex = entry.key;
                      final question = entry.value;
                      final currentAnswer = answers[question.globalIndex];

                      return _buildQuestionCard(
                        context,
                        questionNumber: localIndex + 1 + (screenIndex * 5),
                        questionText: question.text,
                        currentValue: currentAnswer,
                        onChanged:
                            (value) =>
                                onAnswerChanged(question.globalIndex, value),
                      );
                    }).toList(),
              ),
            ),
          ),
          // Navigation buttons
          Container(
            padding: EdgeInsets.all(Spacing.md.w),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                if (!isFirstScreen)
                  Expanded(
                    child: AppButton(
                      label: '← Previous',
                      onPressed: onPrevious,
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                if (!isFirstScreen) Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: isLastScreen ? 'Submit' : 'Next →',
                    onPressed: _allQuestionsAnswered ? onNext : null,
                    size: ButtonSize.medium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(
    BuildContext context, {
    required int questionNumber,
    required String questionText,
    required int? currentValue,
    required Function(int) onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.lg.h),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q$questionNumber',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.sm.h),
          Text(questionText, style: textTheme.bodyLarge),
          Gap(Spacing.lg.h),
          // Likert scale 1-7
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final value = index + 1;
              final isSelected = currentValue == value;

              return GestureDetector(
                onTap: () => onChanged(value),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            isSelected
                                ? colorScheme.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                        border: Border.all(
                          color:
                              isSelected
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$value',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                            color:
                                isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                          ),
                        ),
                      ),
                    ),
                    Gap(Spacing.xs.h),
                    if (value == 1)
                      Text(
                        'Strongly\ndisagree',
                        style: textTheme.labelSmall,
                        textAlign: TextAlign.center,
                      ),
                    if (value == 7)
                      Text(
                        'Strongly\nagree',
                        style: textTheme.labelSmall,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
