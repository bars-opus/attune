// lib/features/profile/presentation/widgets/know_yourself_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KnowYourselfSection extends ConsumerWidget {
  const KnowYourselfSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizStatusAsync = ref.watch(userQuizzesStatusProvider);
    // Spec 5 (R5-6): communication and conflict wait for clinical sign-off.
    final signedOff =
        ref.watch(quizClinicalSignoffProvider).valueOrNull ?? false;

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
                      title: 'What feels loving',
                      startLabel: 'Add yours',
                      isCompleted:
                          quizStatus['love_language']?.completed ?? false,
                      resultType: quizStatus['love_language']?.displayName,
                      // Spec 5 (R5-5): no quiz intro; it is a short editor
                      // that can be changed any time.
                      onTap: () {
                        final current =
                            quizStatus['love_language']?.loveLanguageResult;
                        if (current != null) {
                          context.pushNamed(
                            'loveLanguageResult',
                            extra: current,
                          );
                        } else {
                          context.pushNamed('loveLanguageQuiz');
                        }
                      },
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
                      comingSoon: !signedOff,
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
                      comingSoon: !signedOff,
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
    bool comingSoon = false,
    String startLabel = 'Start quiz',
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (comingSoon) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.sm.h),
        child: Row(
          children: [
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            Text(
              'Coming soon',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

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
                    startLabel,
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
                    'Your attachment style',
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
                  // Every attachment result carries it (Spec 5, R5-4).
                  Gap(Spacing.md.h),
                  Text(
                    AttachmentResult.caveat,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Gap(Spacing.xl.h),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Retake quiz',
                          onPressed: () {
                            Navigator.pop(context);
                            context.pushNamed('quizEntry', extra: quizType);
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
    } else if (communicationStyleResult != null) {
      context.pushNamed(
        'communicationStyleResult',
        extra: communicationStyleResult,
      );
    } else if (conflictStyleResult != null) {
      context.pushNamed('conflictStyleResult', extra: conflictStyleResult);
    } else {
      // Start new quiz
      context.pushNamed('quizEntry', extra: quizType);
    }
  }
}
