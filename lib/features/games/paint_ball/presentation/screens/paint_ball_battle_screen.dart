// lib/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/paint_ball_models.dart';
import '../state/paint_ball_provider.dart';
import '../widgets/paint_ball_arena.dart';
import '../widgets/paint_ball_controls.dart';
import '../widgets/paint_ball_lives_display.dart';
import 'paint_ball_knockout_screen.dart';

class PaintBallBattleScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const PaintBallBattleScreen({
    super.key,
    required this.sessionId,
  });

  @override
  ConsumerState<PaintBallBattleScreen> createState() =>
      _PaintBallBattleScreenState();
}

class _PaintBallBattleScreenState extends ConsumerState<PaintBallBattleScreen> {
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
    ref.listen<PaintBallGamePhase>(paintBallGamePhaseProvider, (previous, next) {
      if (!mounted) return;
      if (next == PaintBallGamePhase.knockout) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PaintBallKnockoutScreen(sessionId: widget.sessionId),
          ),
        );
      }
    });

    final state = ref.watch(paintBallSessionProvider);
    final notifier = ref.read(paintBallSessionProvider.notifier);
    final lives = ref.watch(paintBallLivesProvider);
    final currentUserId = ref.watch(paintBallCurrentUserIdProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final session = state.session;
    if (session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Paint Ball - Round ${session.currentRound}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              _showHowToPlayDialog(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (session.isCompleted)
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.md.w,
                0,
                Spacing.md.w,
                Spacing.md.h,
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  'This session has ended.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          PaintBallLivesDisplay(
            myLives: lives.myLives,
            opponentLives: lives.opponentLives,
            isMyTurn: session.isCurrentUserTurn(currentUserId),
          ),
          Gap(Spacing.md.h),
          Expanded(
            child: PaintBallArena(
              isMyTurn: session.isCurrentUserTurn(currentUserId),
              showHitFeedback: state.showHitFeedback,
              showMissFeedback: state.showMissFeedback,
              showKnockout: state.showKnockout,
              onFire: (hit) => notifier.fireShot(hit: hit),
              isSubmitting: state.isSubmitting,
            ),
          ),
          PaintBallControls(
            isMyTurn: session.isCurrentUserTurn(currentUserId),
            isSubmitting: state.isSubmitting,
          ),
          Gap(Spacing.md.h),
          if (state.errorMessage != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text(
                state.errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
          Gap(Spacing.md.h),
        ],
      ),
    );
  }

  void _showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to Play'),
        content: const Text(
          'Wait for the moving marker to line up, then tap the arena.\n\n'
          'Hit: opponent loses 1 life\n'
          'Miss: no life lost\n'
          'Lose all 3 lives: Truth or Dare penalty',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
