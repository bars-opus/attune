// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_invitation_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_introduction_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../providers/thirty_six_question_providers.dart';

class ThirtySixChapterInvitationScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final int chapter;
  final bool isInitiator;

  const ThirtySixChapterInvitationScreen({
    super.key,
    required this.sessionId,
    required this.chapter,
    required this.isInitiator,
  });

  @override
  ConsumerState<ThirtySixChapterInvitationScreen> createState() =>
      _ThirtySixChapterInvitationScreenState();
}

class _ThirtySixChapterInvitationScreenState
    extends ConsumerState<ThirtySixChapterInvitationScreen> {
  bool _isLoading = false;

  final Map<int, String> _chapterNames = {
    1: 'Warm Up',
    2: 'Deeper',
    3: 'Vulnerable',
  };

  final Map<int, String> _chapterDescriptions = {
    1: 'The conversation starts here. Let\'s get comfortable together.',
    2: 'You have warmed up together. Level 2 goes deeper.',
    3: 'You have gone deeper than most couples do. Level 3 is the most vulnerable.',
  };

  Future<void> _acceptInvitation() async {
    setState(() => _isLoading = true);

    try {
      await ref.read(acceptChapterInvitationProvider(widget.sessionId).future);

      if (mounted) {
        // Navigate to chapter introduction screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (_) => ThirtySixChapterIntroductionScreen(
                  sessionId: widget.sessionId,
                  chapter: widget.chapter,
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept invitation: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    final chapterName =
        _chapterNames[widget.chapter] ?? 'Chapter ${widget.chapter}';
    final description = _chapterDescriptions[widget.chapter] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('36 Questions Journey'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment:
              widget.isInitiator
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
          children: [
            if (widget.isInitiator) ...[
              Text(
                'Invitation sent to $partnerName',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              Gap(Spacing.md.h),
              const Icon(Icons.emoji_people, size: 64),
              Gap(Spacing.md.h),
              Text(
                'Waiting for $partnerName to accept\nChapter $widget.chapter: $chapterName',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
              Gap(Spacing.sm.h),
              Text(
                'This invitation expires in 48 hours.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              Gap(Spacing.xl.h),
              AppButton(
                label: 'Cancel invitation',
                onPressed: () {
                  // Cancel invitation logic
                  Navigator.pop(context);
                },
                size: ButtonSize.medium,
                customColor: colorScheme.surfaceContainerHighest,
                textColor: colorScheme.error,
              ),
            ] else ...[
              Text(
                '$partnerName invited you to continue\nthe 36 Questions Journey',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall,
              ),
              Gap(Spacing.md.h),
              const Icon(Icons.emoji_people, size: 64),
              Gap(Spacing.md.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Column(
                  children: [
                    Text(
                      'Chapter $widget.chapter: $chapterName',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      description,
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      '~20 minutes',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Gap(Spacing.xl.h),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Maybe later',
                      onPressed: () => Navigator.pop(context),
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                  Gap(Spacing.md.w),
                  Expanded(
                    child: AppButton(
                      label: 'Continue →',
                      onPressed: _isLoading ? null : _acceptInvitation,
                      size: ButtonSize.medium,
                      isLoading: _isLoading,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
