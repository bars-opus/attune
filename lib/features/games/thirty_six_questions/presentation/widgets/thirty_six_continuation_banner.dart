// lib/features/games/thirty_six_questions/presentation/widgets/thirty_six_continuation_banner.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart'
    show inviteToChapterProvider, partnerNameProvider;
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class ThirtySixContinuationBanner extends ConsumerWidget {
  final String journeyId;
  final int nextChapter;

  ThirtySixContinuationBanner({
    super.key,
    required this.journeyId,
    required this.nextChapter,
  });

  final Map<int, String> _chapterNames = {
    1: 'Warm Up',
    2: 'Deeper',
    3: 'Vulnerable',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';
    final chapterName = _chapterNames[nextChapter] ?? 'Chapter $nextChapter';

    return Container(
      margin: EdgeInsets.all(Spacing.md.w),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withOpacity(0.1),
            colorScheme.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_people, color: Colors.green),
              Gap(Spacing.sm.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue the journey',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Chapter $nextChapter: $chapterName',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Invite →',
                onPressed: () => _sendInvite(context, ref),
                size: ButtonSize.small,
              ),
            ],
          ),
          Gap(Spacing.sm.h),
          Text(
            'Invite $partnerName to continue when you\'re both ready.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  void _sendInvite(BuildContext context, WidgetRef ref) async {
    try {
      final chapter = await ref.read(
        inviteToChapterProvider((
          journeyId: journeyId,
          chapter: nextChapter,
        )).future,
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ThirtySixChapterInvitationScreen(
                  sessionId: chapter.sessionId,
                  chapter: chapter.chapterNumber,
                  isInitiator: true,
                ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send invite: $e')));
      }
    }
  }
}
