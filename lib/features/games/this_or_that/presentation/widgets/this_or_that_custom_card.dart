// lib/features/games/this_or_that/presentation/widgets/this_or_that_custom_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class ThisOrThatCustomCard extends ConsumerWidget {
  final CustomThisOrThatQuestion question;
  final bool isOwnQuestion;
  final VoidCallback? onDeleted;
  final VoidCallback? onPrivacyChanged;
  final VoidCallback? onSharedChanged;
  final VoidCallback? onReported;

  const ThisOrThatCustomCard({
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
      case 'connecting': return '💙 Connecting';
      case 'romantic': return '❤️ Romantic';
      case 'playful': return '😄 Playful';
      case 'spicy': return '🔥 Spicy';
      case 'intimate': return '🌙 Intimate';
      default: return question.tone;
    }
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
          // Header with tone and menu
          Row(
            children: [
              // Type badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                ),
                child: Text(
                  '🔀 This or That',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
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
                        await ref.read(deleteThisOrThatCustomQuestionProvider(question.id).future);
                        onDeleted?.call();
                      }
                    } else if (value == 'toggle_privacy') {
                      await ref.read(toggleThisOrThatCustomPrivacyProvider((
                        id: question.id,
                        isPrivate: !question.isPrivate,
                      )).future);
                      onPrivacyChanged?.call();
                    } else if (value == 'share_community') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Share with community?'),
                          content: const Text(
                            'This question will be visible to other Attune users anonymously. '
                            'You can unshare anytime.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Share'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(toggleThisOrThatCommunityShareProvider((
                          id: question.id,
                          share: true,
                        )).future);
                        onSharedChanged?.call();
                      }
                    } else if (value == 'unshare_community') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove from community?'),
                          content: const Text(
                            'This question will no longer be visible to other users.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(toggleThisOrThatCommunityShareProvider((
                          id: question.id,
                          share: false,
                        )).future);
                        onSharedChanged?.call();
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    if (question.sharedToCommunity)
                      const PopupMenuItem(
                        value: 'unshare_community',
                        child: Text('Remove from community'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'share_community',
                        child: Text('Share with community'),
                      ),
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
                        await ref.read(reportThisOrThatCustomQuestionProvider((
                          id: question.id,
                          reason: reason,
                        )).future);
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
          // Question text
          Text(
            question.questionText,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.sm.h),
          // Options
          Row(
            children: [
              _buildOptionChip(question.optionA, question.emojiA, colorScheme, textTheme),
              Gap(Spacing.md.w),
              _buildOptionChip(question.optionB, question.emojiB, colorScheme, textTheme),
            ],
          ),
          Gap(Spacing.sm.h),
          // Footer: privacy + usage
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
              if (question.sharedToCommunity)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.xs.w, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                  ),
                  child: Text(
                    '🌐 Community',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              if (question.sharedToCommunity) Gap(Spacing.sm.w),
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

  Widget _buildOptionChip(String text, String? emoji, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null && emoji.isNotEmpty) Text(emoji),
          if (emoji != null && emoji.isNotEmpty) Gap(Spacing.xs.w),
          Text(text, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
