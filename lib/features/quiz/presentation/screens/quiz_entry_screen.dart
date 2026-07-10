// lib/features/quiz/presentation/screens/quiz_entry_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/screens/attachment_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/communication_style_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/conflict_style_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_quiz_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuizEntryScreen extends ConsumerWidget {
  final String
  quizType; // 'attachment', 'love_language', 'communication', 'conflict'

  const QuizEntryScreen({super.key, required this.quizType});

  String get _title {
    switch (quizType) {
      case 'attachment':
        return 'Attachment style';
      case 'love_language':
        return 'Love languages';
      case 'communication':
        return 'Communication style';
      case 'conflict':
        return 'Conflict style';
      default:
        return 'Quiz';
    }
  }

  String get _questionCount {
    switch (quizType) {
      case 'attachment':
        return '25 questions · about 5 minutes';
      case 'love_language':
        return '15 questions · about 3 minutes';
      case 'communication':
        return '20 questions · about 4 minutes';
      case 'conflict':
        return '18 questions · about 4 minutes';
      default:
        return '';
    }
  }

  String get _description {
    switch (quizType) {
      case 'attachment':
        return 'This quiz helps you understand how you tend to show up in relationships — and why.';
      case 'love_language':
        return 'Discover how you most naturally give and receive affection.';
      case 'communication':
        return 'Understand your natural communication patterns under different conditions.';
      case 'conflict':
        return 'This reflection can help you notice approaches you may use during disagreement. Your response can change with the situation, relationship, culture, and sense of safety.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              _questionCount,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Gap(Spacing.xl.h),
            Text(_description, style: textTheme.bodyLarge),
            Gap(Spacing.lg.h),
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  Gap(Spacing.sm.w),
                  Expanded(
                    child: Text(
                      'Your result is private. You choose whether to share it.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.lg.h),
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'There are no right or wrong answers.',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Gap(Spacing.xs.h),
                  Text(
                    'Answer how you actually feel, not how you think you should feel.',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Spacer(),
            AppButton(
              label: 'Start quiz →',
              onPressed: () {
                final Widget quizScreen;
                switch (quizType) {
                  case 'love_language':
                    quizScreen = const LoveLanguageQuizScreen();
                    break;
                  case 'communication':
                    quizScreen = const CommunicationStyleQuizScreen();
                    break;
                  case 'conflict':
                    quizScreen = const ConflictStyleQuizScreen();
                    break;
                  case 'attachment':
                  default:
                    quizScreen = AttachmentQuizScreen(quizType: quizType);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => quizScreen),
                );
              },
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
