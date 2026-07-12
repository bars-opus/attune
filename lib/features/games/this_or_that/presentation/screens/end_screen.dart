// lib/features/games/this_or_that/presentation/screens/end_screen.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EndScreen extends ConsumerStatefulWidget {
  final int matchCount;
  final int totalRounds;
  final Map<String, dynamic> mostInterestingPick;
  final VoidCallback onPlayAgain;
  final VoidCallback onTryAnotherGame;

  const EndScreen({
    super.key,
    required this.matchCount,
    required this.totalRounds,
    required this.mostInterestingPick,
    required this.onPlayAgain,
    required this.onTryAnotherGame,
  });

  @override
  ConsumerState<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends ConsumerState<EndScreen> {
  double get matchPercentage =>
      widget.totalRounds > 0
          ? (widget.matchCount / widget.totalRounds) * 100
          : 0;

  bool get showMatchBar => matchPercentage >= 60;

  @override
  void initState() {
    super.initState();
    // Close the session on a warm note: a completion sound, plus a celebratory
    // haptic when the couple matched strongly.
    ref.read(soundServiceProvider).play(AppSound.gameComplete);
    if (showMatchBar) {
      ref.read(hapticsProvider).light();
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Game over!'), centerTitle: true),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            // Match count — settles in as the closing reveal.
            SettleIn(
              child: Text(
                'You matched on ${widget.matchCount} out of ${widget.totalRounds}',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Gap(Spacing.md.h),
            // Progress bar (only if 60% or higher)
            if (showMatchBar) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                child: LinearProgressIndicator(
                  value: matchPercentage / 100,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
              Gap(Spacing.sm.h),
              Text(
                '${matchPercentage.toStringAsFixed(0)}%',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ] else ...[
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Text(
                  'You see things differently — that\'s what makes it interesting.',
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            Gap(Spacing.xl.h),
            // Most interesting pick
            if (widget.mostInterestingPick.isNotEmpty) ...[
              const Divider(),
              Gap(Spacing.md.h),
              Text(
                'Most interesting pick:',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Gap(Spacing.sm.h),
              Text(
                '"${widget.mostInterestingPick['question_text']}"',
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              Gap(Spacing.md.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildChoicePill(
                    text: widget.mostInterestingPick['answer_a_text'] ?? '',
                    emoji: widget.mostInterestingPick['answer_a_emoji'] ?? '',
                    isUser: true,
                    context: context,
                  ),
                  Gap(Spacing.md.w),
                  Text('vs'),
                  Gap(Spacing.md.w),
                  _buildChoicePill(
                    text: widget.mostInterestingPick['answer_b_text'] ?? '',
                    emoji: widget.mostInterestingPick['answer_b_emoji'] ?? '',
                    isUser: false,
                    context: context,
                  ),
                ],
              ),
              const Divider(),
            ],
            const Spacer(),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Play again',
                    onPressed: widget.onPlayAgain,
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Try another game',
                    onPressed: widget.onTryAnotherGame,
                    size: ButtonSize.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoicePill({
    required String text,
    required String emoji,
    required bool isUser,
    required BuildContext context,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md.w,
        vertical: Spacing.sm.h,
      ),
      decoration: BoxDecoration(
        color:
            isUser
                ? colorScheme.primary.withValues(alpha: 0.1)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Row(
        children: [
          if (emoji.isNotEmpty) Text(emoji),
          if (emoji.isNotEmpty) Gap(Spacing.xs.w),
          Text(text),
        ],
      ),
    );
  }
}
