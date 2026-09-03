import 'dart:async';
// lib/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/paint_ball_models.dart';
import '../state/paint_ball_provider.dart';
import '../widgets/paint_ball_arena.dart';
import '../widgets/paint_ball_controls.dart';
import '../widgets/paint_ball_lives_display.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:attune/core/ui/presence/breathing_dots.dart';

class PaintBallBattleScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const PaintBallBattleScreen({super.key, required this.sessionId});

  @override
  ConsumerState<PaintBallBattleScreen> createState() =>
      _PaintBallBattleScreenState();
}

class _PaintBallBattleScreenState extends ConsumerState<PaintBallBattleScreen>
    with SingleTickerProviderStateMixin {
  /// Drives the paintball across the field.
  ///
  /// The shot is sent to the server the moment Fire is tapped -- the
  /// animation is not a gate on the turn. If it were, a slow frame or a
  /// backgrounded app could cost someone their move.
  late final AnimationController _shotController;

  @override
  void initState() {
    super.initState();
    _shotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(paintBallSessionProvider);
      if (state.session?.sessionId != widget.sessionId) {
        ref
            .read(paintBallSessionProvider.notifier)
            .loadSession(widget.sessionId);
      }
    });
  }

  @override
  void dispose() {
    _shotController.dispose();
    super.dispose();
  }

  Future<void> _fire() async {
    final notifier = ref.read(paintBallSessionProvider.notifier);
    // Started together: the flight plays while the request is in the air,
    // so the animation costs nothing in waiting.
    unawaited(_shotController.forward(from: 0));
    await notifier.takeTurn();
    if (mounted) _shotController.reset();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaintBallGamePhase>(paintBallGamePhaseProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      if (next == PaintBallGamePhase.knockout) {
        context.pushReplacementNamed(
          'paintBallKnockout',
          pathParameters: {'sessionId': widget.sessionId},
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
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
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Column(
                children: [
                  // Both choices on one screen. The interesting decision
                  // is the PAIR: where you hide informs where you think
                  // they will shoot, which informs where they think you
                  // will be. Splitting it into two steps would hide half
                  // of that while making the other half.
                  // Rebuilt per frame while a shot is in flight;
                  // AnimatedBuilder rather than setState so only the
                  // field repaints, not the whole screen.
                  AnimatedBuilder(
                    animation: _shotController,
                    builder:
                        (context, _) => PaintBallField(
                          splats: _splatsFor(session, currentUserId),
                          myPosition: state.hidePosition,
                          selectedShot: state.shotPosition,
                          revealedPartnerPosition:
                              state.revealedPartnerPosition,
                          isMyTurn: session.isCurrentUserTurn(currentUserId),
                          onSelectShot: notifier.selectShot,
                          shotProgress:
                              _shotController.isAnimating
                                  ? _shotController.value
                                  : null,
                        ),
                  ),
                  Gap(Spacing.md.h),
                  _HideChooser(
                    selected: state.hidePosition,
                    enabled:
                        session.isCurrentUserTurn(currentUserId) &&
                        !state.isSubmitting,
                    onSelect: notifier.selectHide,
                  ),
                  Gap(Spacing.md.h),
                  _TurnPrompt(
                    state: state,
                    isMyTurn: session.isCurrentUserTurn(currentUserId),
                    onFire: _fire,
                    onNext: notifier.beginNextTurn,
                  ),
                ],
              ),
            ),
          ),
          Gap(Spacing.md.h),
          if (state.errorMessage != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text(
                state.errorMessage!,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
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
      builder:
          (context) => AlertDialog(
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

/// Turns the round history into paint on the field.
///
/// Derived from the rounds rather than stored: the server already records
/// every shot's position and result, so a separate paint table would be a
/// second copy of the same truth, free to drift.
List<PaintSplat> _splatsFor(PaintBallSessionState session, String? userId) {
  final splats = <PaintSplat>[];

  for (final round in session.rounds) {
    final position = round.shotPosition;
    // An opening move had nothing to shoot at, so it leaves no paint.
    if (position == null || round.shotResult == 'opening') continue;

    splats.add(
      PaintSplat(
        position: position,
        isMine: round.activePartnerId == userId,
        hit: round.shotResult == 'hit',
        round: round.roundNumber,
      ),
    );
  }

  return splats;
}

/// Where you take cover this turn.
///
/// Separate from the field's opponent row because they answer different
/// questions -- one is "where am I", the other "where are they" -- and a
/// single row of taps doing both would make it easy to spend a turn on
/// the wrong one.
class _HideChooser extends StatelessWidget {
  const _HideChooser({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final int? selected;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Take cover',
          style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.xs.h),
        Text(
          'They will shoot at where they think you are.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Gap(Spacing.sm.h),
        Row(
          children: List.generate(kPaintBallPositions, (index) {
            final isSelected = selected == index;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.xs.w),
                child: GestureDetector(
                  onTap: enabled ? () => onSelect(index) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48.h,
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? colorScheme.primary.withValues(alpha: 0.85)
                              : colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.md.r,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.shield_rounded,
                        size: 20.h,
                        color:
                            isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.primary.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// What to do next: fire, wait, or read the result.
class _TurnPrompt extends StatelessWidget {
  const _TurnPrompt({
    required this.state,
    required this.isMyTurn,
    required this.onFire,
    required this.onNext,
  });

  final PaintBallUiState state;
  final bool isMyTurn;
  final VoidCallback onFire;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // A resolved shot: hold the reveal until they choose to move on, so
    // the moment the field shows their partner's position is not swept
    // away by an animation they did not ask for.
    if (state.revealedPartnerPosition != null || state.showMissFeedback) {
      final hit = state.showHitFeedback;
      return Column(
        children: [
          Text(
            hit ? 'Direct hit' : 'They were somewhere else',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: hit ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            hit
                ? 'You read them right.'
                : 'Now you know where they were hiding.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.md.h),
          AppButton(
            label: 'Back to chat',
            onPressed: onNext,
            size: ButtonSize.medium,
            width: double.infinity,
          ),
        ],
      );
    }

    if (!isMyTurn) {
      return Column(
        children: [
          const BreathingDots(size: 6),
          Gap(Spacing.sm.h),
          Text(
            'Waiting for their move',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      );
    }

    return AppButton(
      label: state.isSubmitting ? 'Firing…' : 'Fire',
      // Both choices are required: submitting with either missing would
      // spend a turn on half a move.
      onPressed: state.canFire && !state.isSubmitting ? onFire : null,
      size: ButtonSize.large,
      width: double.infinity,
      isLoading: state.isSubmitting,
    );
  }
}
