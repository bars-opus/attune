// lib/features/games/truth_or_dare/presentation/widgets/custom_truth_or_dare_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class CustomTruthOrDareCard extends ConsumerWidget {
  final CustomTruthOrDareQuestion question;
  final bool isOwnQuestion;
  final VoidCallback? onDeleted;
  final VoidCallback? onPrivacyChanged;
  final VoidCallback? onSharedChanged;
  final VoidCallback? onReported;

  const CustomTruthOrDareCard({
    super.key,
    required this.question,
    required this.isOwnQuestion,
    this.onDeleted,
    this.onPrivacyChanged,
    this.onSharedChanged,
    this.onReported,
  });

  String get _toneDisplay {
    switch (question.tone) {
      case 'connecting':
        return '💙 Connecting';
      case 'romantic':
        return '❤️ Romantic';
      case 'playful':
        return '😄 Playful';
      case 'spicy':
        return '🔥 Spicy';
      case 'intimate':
        return '🌙 Intimate';
      default:
        return question.tone;
    }
  }

  String get _typeDisplay {
    return question.questionType == 'truth' ? '🗣 Truth' : '🎯 Dare';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with type, tone and menu
          Row(
            children: [
              // Type badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
                decoration: BoxDecoration(
                  color: question.questionType == 'truth'
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                ),
                child: Text(
                  _typeDisplay,
                  style: textTheme.labelSmall?.copyWith(
                    color: question.questionType == 'truth'
                        ? Colors.green
                        : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Gap(Spacing.sm.w),
              // Tone badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                ),
                child: Text(
                  _toneDisplay,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (isOwnQuestion)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (value) async {
                    if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete question?'),
                          content: const Text(
                            'This question will be removed for both you and your partner.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(
                          deleteCustomTruthOrDareQuestionProvider(question.id).future,
                        );
                        onDeleted?.call();
                      }
                    } else if (value == 'toggle_privacy') {
                      await ref.read(
                        toggleCustomTruthOrDarePrivacyProvider((
                          id: question.id,
                          isPrivate: !question.isPrivate,
                        )).future,
                      );
                      onPrivacyChanged?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'toggle_privacy',
                      child: Text('Share with partner / Make private'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              if (!isOwnQuestion)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (value) async {
                    if (value == 'report') {
                      final reason = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Report question'),
                          content: const Text('Why are you reporting this question?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'inappropriate'),
                              child: const Text('Inappropriate'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'offensive'),
                              child: const Text('Offensive'),
                            ),
                          ],
                        ),
                      );
                      if (reason != null) {
                        await ref.read(
                          reportCustomTruthOrDareQuestionProvider((
                            id: question.id,
                            reason: reason,
                          )).future,
                        );
                        onReported?.call();
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'report', child: Text('Report')),
                  ],
                ),
            ],
          ),
          Gap(Spacing.md.h),
          // Content
          Text(
            question.content,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.sm.h),
          // Usage count
          Row(
            children: [
              if (question.isPrivate)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.xs.w, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                  ),
                  child: Text(
                    'Private',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
              if (question.isPrivate) Gap(Spacing.sm.w),
              Text(
                'Used ${question.timesUsed} time${question.timesUsed != 1 ? 's' : ''}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
