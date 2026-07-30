// lib/features/community/presentation/widgets/community_question_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/community/data/models/community_question.dart';
import 'package:attune/features/community/presentation/providers/community_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class CommunityQuestionCard extends ConsumerStatefulWidget {
  final CommunityQuestion question;

  const CommunityQuestionCard({super.key, required this.question});

  @override
  ConsumerState<CommunityQuestionCard> createState() => _CommunityQuestionCardState();
}

class _CommunityQuestionCardState extends ConsumerState<CommunityQuestionCard> {
  bool _isSaving = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.question.isSaved;
  }

  Future<void> _toggleSave() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      if (_isSaved) {
        await ref.read(unsaveCommunityQuestionProvider((
          question: widget.question,
        )).future);
        setState(() => _isSaved = false);
      } else {
        await ref.read(saveCommunityQuestionProvider(widget.question).future);
        setState(() => _isSaved = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report question'),
        content: const Text('Why are you reporting this question?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final table = widget.question.type == 'this_or_that'
                  ? 'this_or_that'
                  : 'truth_or_dare';
              await ref.read(reportCommunityQuestionProvider((
                questionId: widget.question.id,
                table: table,
                reason: 'inappropriate',
              )).future);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Thank you for reporting. We will review it.')),
                );
              }
            },
            child: const Text('Inappropriate'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final table = widget.question.type == 'this_or_that'
                  ? 'this_or_that'
                  : 'truth_or_dare';
              await ref.read(reportCommunityQuestionProvider((
                questionId: widget.question.id,
                table: table,
                reason: 'offensive',
              )).future);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Thank you for reporting. We will review it.')),
                );
              }
            },
            child: const Text('Offensive'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // Header: type + tone badges
          Row(
            children: [
              // Type badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
                decoration: BoxDecoration(
                  color: widget.question.type == 'this_or_that'
                      ? colorScheme.primary.withOpacity(0.1)
                      : widget.question.questionType == 'truth'
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.question.typeIcon, style: const TextStyle(fontSize: 12)),
                    Gap(Spacing.xs.w),
                    Text(
                      widget.question.typeDisplay,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Gap(Spacing.sm.w),
              // Tone badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
                decoration: BoxDecoration(
                  color: widget.question.toneColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                ),
                child: Text(
                  widget.question.toneDisplay,
                  style: textTheme.labelSmall?.copyWith(
                    color: widget.question.toneColor,
                  ),
                ),
              ),
              const Spacer(),
              // Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (value) {
                  if (value == 'report') _showReportDialog();
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
            widget.question.content,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          // This or That options (if applicable)
          if (widget.question.type == 'this_or_that' &&
              widget.question.optionA != null &&
              widget.question.optionB != null) ...[
            Gap(Spacing.sm.h),
            Row(
              children: [
                Text(
                  '${widget.question.emojiA ?? ''} ${widget.question.optionA}',
                  style: textTheme.bodySmall,
                ),
                Gap(Spacing.sm.w),
                Text('vs', style: textTheme.bodySmall),
                Gap(Spacing.sm.w),
                Text(
                  '${widget.question.emojiB ?? ''} ${widget.question.optionB}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ],
          Gap(Spacing.md.h),
          // Footer: usage + save button
          Row(
            children: [
              Text(
                'Used ${widget.question.communityUsageCount} times',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const Spacer(),
              AppButton(
                label: _isSaved ? '✓ Saved' : 'Save →',
                onPressed: _isSaving ? null : _toggleSave,
                size: ButtonSize.small,
                width: 100.w,
                customColor: _isSaved
                    ? colorScheme.primary.withOpacity(0.1)
                    : colorScheme.surfaceContainerHighest,
                textColor: _isSaved
                    ? colorScheme.primary
                    : colorScheme.onSurface,
                isLoading: _isSaving,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
