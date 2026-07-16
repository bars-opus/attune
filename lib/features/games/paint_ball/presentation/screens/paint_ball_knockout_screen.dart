// lib/features/games/paint_ball/presentation/screens/paint_ball_knockout_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/paint_ball_provider.dart';

class PaintBallKnockoutScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const PaintBallKnockoutScreen({
    super.key,
    required this.sessionId,
  });

  @override
  ConsumerState<PaintBallKnockoutScreen> createState() =>
      _PaintBallKnockoutScreenState();
}

class _PaintBallKnockoutScreenState
    extends ConsumerState<PaintBallKnockoutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(paintBallSessionProvider);
      if (state.session?.sessionId != widget.sessionId) {
        ref.read(paintBallSessionProvider.notifier).loadSession(widget.sessionId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paintBallSessionProvider);
    final notifier = ref.read(paintBallSessionProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final session = state.session;
    if (session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final penaltyType = session.penaltyType ?? 'truth';
    final penaltyPrompt = session.penaltyPromptSnapshot ?? '';
    final isResolved = session.penaltyStatus == 'completed' ||
        session.penaltyStatus == 'declined' ||
        session.isCompleted;

    // Only the LOSER resolves the penalty (spec §6.1/§10.5). The winner is
    // navigated here too (both clients enter the knockout phase via realtime),
    // but must see a spectator view — not "you lost" copy and not the
    // Complete/Skip buttons, which would 403 for them.
    final currentUserId = ref.watch(paintBallCurrentUserIdProvider);
    final isLoser = session.winnerUserId != null &&
        session.winnerUserId != currentUserId;
    final isWinner = session.winnerUserId != null &&
        session.winnerUserId == currentUserId;

    if (isWinner && !isResolved) {
      return _buildWinnerWaitingView(context, penaltyType);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Truth or Dare'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: Colors.purple.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    isResolved
                        ? 'SESSION COMPLETE'
                        : isWinner
                            ? 'KNOCKOUT'
                            : 'KNOCKED OUT',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  Gap(Spacing.xs.h),
                  Text(
                    isResolved
                        ? 'The penalty has been handled.'
                        : isWinner
                            ? 'You won this round.'
                            : 'You lost all 3 lives.',
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),
            if (!isResolved) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.lg.w),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      penaltyType.toUpperCase(),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: penaltyType == 'truth'
                            ? colorScheme.primary
                            : colorScheme.secondary,
                      ),
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      penaltyPrompt,
                      style: textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Gap(Spacing.xl.h),
              Text(
                'Complete the prompt or skip it for free.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Gap(Spacing.md.h),
              // Only the loser gets the resolve controls. The winner never
              // reaches this branch (early-returned to the waiting view above),
              // but gate explicitly so the safety-critical buttons can never
              // render for the wrong player.
              if (isLoser)
                if (state.isSubmitting)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Complete',
                          onPressed: () =>
                              notifier.resolvePenalty(completed: true),
                          size: ButtonSize.small,
                        ),
                      ),
                      Gap(Spacing.md.w),
                      Expanded(
                        child: AppButton(
                          label: 'Skip',
                          onPressed: () =>
                              notifier.resolvePenalty(completed: false),
                          size: ButtonSize.small,
                        ),
                      ),
                    ],
                  ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.lg.w),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Nice round.',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      session.penaltyStatus == 'declined'
                          ? 'The prompt was skipped, and the game is complete.'
                          : 'The prompt was completed, and the game is complete.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Gap(Spacing.lg.h),
              AppButton(
                label: 'Back to Games',
                onPressed: () => Navigator.pop(context),
                size: ButtonSize.small,
                width: double.infinity,
              ),
            ],
            if (state.errorMessage != null) ...[
              Gap(Spacing.md.h),
              Text(
                state.errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const Spacer(),
            if (isLoser)
              Text(
                'You can always skip with no penalty. 💚',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Spectator view for the WINNER while the loser decides on their prompt.
  /// The winner never sees the prompt content or any resolve control — the
  /// penalty is the loser's private choice, and it is always declinable.
  Widget _buildWinnerWaitingView(BuildContext context, String penaltyType) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Truth or Dare'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    'KNOCKOUT',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                  Gap(Spacing.xs.h),
                  Text(
                    'You won this round.',
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),
            Text(
              'Your partner got a ${penaltyType == 'dare' ? 'dare' : 'truth'} prompt. '
              'It is theirs to complete or skip — you will see when the game wraps up.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            const CircularProgressIndicator(),
            const Spacer(),
            Text(
              'They can complete or skip — both are fine. 💚',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
