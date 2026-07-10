// lib/features/profile/presentation/widgets/know_yourself_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/screens/communication_style_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/conflict_style_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_entry_screen.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_result_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KnowYourselfSection extends ConsumerWidget {
  const KnowYourselfSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizStatusAsync = ref.watch(userQuizzesStatusProvider);

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Know yourself',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          Gap(Spacing.md.h),

          quizStatusAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error')),
            data:
                (quizStatus) => Column(
                  children: [
                    _buildQuizTile(
                      context,
                      title: 'Attachment style',
                      isCompleted: quizStatus['attachment']?.completed ?? false,
                      resultType: quizStatus['attachment']?.displayName,
                      onTap:
                          () => _navigateToQuiz(
                            context,
                            ref,
                            'attachment',
                            attachmentResult: quizStatus['attachment']?.result,
                          ),
                    ),
                    Divider(
                      height: 32,
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    _buildQuizTile(
                      context,
                      title: 'Love languages',
                      isCompleted:
                          quizStatus['love_language']?.completed ?? false,
                      resultType: quizStatus['love_language']?.displayName,
                      onTap:
                          () => _navigateToQuiz(
                            context,
                            ref,
                            'love_language',
                            loveLanguageResult:
                                quizStatus['love_language']?.loveLanguageResult,
                          ),
                    ),
                    Divider(
                      height: 32,
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    _buildQuizTile(
                      context,
                      title: 'Communication style',
                      isCompleted:
                          quizStatus['communication']?.completed ?? false,
                      resultType: quizStatus['communication']?.displayName,
                      onTap:
                          () => _navigateToQuiz(
                            context,
                            ref,
                            'communication',
                            communicationStyleResult:
                                quizStatus['communication']
                                    ?.communicationStyleResult,
                          ),
                    ),
                    Divider(
                      height: 32,
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    _buildQuizTile(
                      context,
                      title: 'Conflict style',
                      isCompleted: quizStatus['conflict']?.completed ?? false,
                      resultType: quizStatus['conflict']?.displayName,
                      onTap:
                          () => _navigateToQuiz(
                            context,
                            ref,
                            'conflict',
                            conflictStyleResult:
                                quizStatus['conflict']?.conflictStyleResult,
                          ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizTile(
    BuildContext context, {
    required String title,
    required bool isCompleted,
    String? resultType,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.sm.h),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.titleMedium),
                  if (isCompleted && resultType != null)
                    Text(
                      resultType,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            if (isCompleted)
              Row(
                children: [
                  Text(
                    'View result',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  Gap(Spacing.xs.w),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Text(
                    'Start quiz',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Gap(Spacing.xs.w),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToQuiz(
    BuildContext context,
    WidgetRef ref,
    String quizType, {
    AttachmentResult? attachmentResult,
    LoveLanguageResult? loveLanguageResult,
    CommunicationStyleResult? communicationStyleResult,
    ConflictStyleResult? conflictStyleResult,
  }) {
    if (attachmentResult != null) {
      // Show existing result with option to retake
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (context) => Container(
              padding: EdgeInsets.all(Spacing.lg.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your $quizType result',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Gap(Spacing.md.h),
                  Text(
                    attachmentResult.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Gap(Spacing.md.h),
                  Text(
                    attachmentResult.poeticDescription,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Gap(Spacing.xl.h),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Retake quiz',
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => QuizEntryScreen(quizType: quizType),
                              ),
                            );
                          },
                          size: ButtonSize.medium,
                          customColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          textColor: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Gap(Spacing.md.w),
                      Expanded(
                        child: AppButton(
                          label: 'Close',
                          onPressed: () => Navigator.pop(context),
                          size: ButtonSize.medium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      );
    } else if (loveLanguageResult != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (context) => Container(
              padding: EdgeInsets.all(Spacing.lg.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your love language result',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Gap(Spacing.md.h),
                  Text(
                    loveLanguageResult.getPrimaryDisplay(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Gap(Spacing.md.h),
                  Text(
                    loveLanguageResult.getDescription(
                      loveLanguageResult.primary,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Gap(Spacing.xl.h),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'View result',
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => LoveLanguageResultScreen(
                                      result: loveLanguageResult,
                                    ),
                              ),
                            );
                          },
                          size: ButtonSize.medium,
                        ),
                      ),
                      Gap(Spacing.md.w),
                      Expanded(
                        child: AppButton(
                          label: 'Retake quiz',
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => QuizEntryScreen(quizType: quizType),
                              ),
                            );
                          },
                          size: ButtonSize.medium,
                          customColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          textColor: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Gap(Spacing.sm.h),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
      );
    } else if (communicationStyleResult != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => CommunicationStyleResultScreen(
                result: communicationStyleResult,
              ),
        ),
      );
    } else if (conflictStyleResult != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ConflictStyleResultScreen(result: conflictStyleResult),
        ),
      );
    } else {
      // Start new quiz
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QuizEntryScreen(quizType: quizType)),
      );
    }
  }
}
