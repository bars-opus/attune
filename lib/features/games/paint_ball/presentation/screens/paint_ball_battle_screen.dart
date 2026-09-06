import 'dart:async';
// lib/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/paint_ball_models.dart';
import '../state/paint_ball_provider.dart';
import '../widgets/paint_ball_lives_display.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';

class PaintBallBattleScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const PaintBallBattleScreen({super.key, required this.sessionId});

  @override
  ConsumerState<PaintBallBattleScreen> createState() =>
      _PaintBallBattleScreenState();
}

class _PaintBallBattleScreenState extends ConsumerState<PaintBallBattleScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Drives the paintball across the field.
  ///
  /// The shot is sent to the server the moment Fire is tapped -- the
  /// animation is not a gate on the turn. If it were, a slow frame or a
  /// backgrounded app could cost someone their move.
  late final AnimationController _shotController;
  bool _routingToKnockout = false;
  bool _shotInFlight = false;
  int? _firingRound;

  @override
  void initState() {
    super.initState();
    _shotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Fetch on every open, even when Riverpod still holds this session from a
      // previous route. Realtime is a convenience; this read is the guarantee.
      ref.read(paintBallSessionProvider.notifier).loadSession(widget.sessionId);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shotController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(paintBallSessionProvider.notifier)
            .loadSession(widget.sessionId),
      );
    }
  }

  Future<void> _fire() async {
    if (_shotInFlight) return;
    final notifier = ref.read(paintBallSessionProvider.notifier);
    final firingRound =
        ref.read(paintBallSessionProvider).session?.currentRound;
    setState(() {
      _shotInFlight = true;
      _firingRound = firingRound;
    });
    // Started together: the flight plays while the request is in the air,
    // so the animation costs nothing in waiting.
    try {
      final flight =
          reduceMotionOf(context)
              ? Future<void>.value()
              : _shotController.forward(from: 0).then<void>((_) {});
      final request = notifier.takeTurn();
      await Future.wait([flight, request]);
    } finally {
      if (mounted) {
        _shotController.reset();
        setState(() {
          _shotInFlight = false;
          _firingRound = null;
        });
      }
    }
  }

  Future<void> _routeToKnockout() async {
    if (_routingToKnockout || !mounted) return;
    _routingToKnockout = true;
    final delay =
        reduceMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 640);
    await Future<void>.delayed(delay);
    if (!mounted) return;
    final action = await context.pushNamed<PaintBallExitAction>(
      'paintBallKnockout',
      pathParameters: {'sessionId': widget.sessionId},
    );
    if (!mounted) return;
    Navigator.of(context).pop(action ?? PaintBallExitAction.backToChat);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaintBallGamePhase>(paintBallGamePhaseProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      if (next == PaintBallGamePhase.knockout) {
        unawaited(_routeToKnockout());
      } else if (next == PaintBallGamePhase.ended) {
        unawaited(_routeToKnockout());
      }
    });

    final state = ref.watch(paintBallSessionProvider);
    final notifier = ref.read(paintBallSessionProvider.notifier);
    final lives = ref.watch(paintBallLivesProvider);
    final currentUserId = ref.watch(paintBallCurrentUserIdProvider);
    final textTheme = Theme.of(context).textTheme;

    final session = state.session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      // Black regardless of theme, matching the field. Paint Ball is a
      // schematic on a dark ground; a light surface would leave the field
      // as a black rectangle floating on white.
      backgroundColor: PaintBallPalette.field,
      appBar: AppBar(
        title: Text('Paint Ball - Round ${session.currentRound}'),
        foregroundColor: Colors.white,
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
      body: Stack(
        children: [
          Column(
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
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      'This session has ended.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
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
                              splats: _splatsFor(
                                session,
                                currentUserId,
                                excludedRound:
                                    _shotInFlight ? _firingRound : null,
                              ),
                              myPosition: state.hidePosition,
                              selectedShot: state.shotPosition,
                              revealedPartnerPosition:
                                  _shotInFlight
                                      ? null
                                      : state.revealedPartnerPosition,
                              isMyTurn: session.isCurrentUserTurn(
                                currentUserId,
                              ),
                              onSelectShot: notifier.selectShot,
                              onSelectHide: notifier.selectHide,
                              onFire: state.canFire ? _fire : null,
                              shotProgress:
                                  _shotController.isAnimating &&
                                          !reduceMotionOf(context)
                                      ? _shotController.value
                                      : null,
                            ),
                      ),
                      Gap(Spacing.md.h),
                      _TurnPrompt(
                        state: state,
                        isMyTurn: session.isCurrentUserTurn(currentUserId),
                        shotInFlight: _shotInFlight,
                        onFire: _fire,
                        onDone: () {
                          notifier.beginNextTurn();
                          Navigator.of(
                            context,
                          ).pop(PaintBallExitAction.backToChat);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Gap(Spacing.md.h),
              if (state.errorMessage != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                  child: _TurnErrorBanner(
                    message: state.errorMessage!,
                    onRetry: () {
                      if (state.canFire) {
                        unawaited(_fire());
                      } else {
                        unawaited(notifier.loadSession(widget.sessionId));
                      }
                    },
                    onDismiss: notifier.clearError,
                  ),
                ),
              Gap(Spacing.md.h),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: state.showKnockout && !_shotInFlight ? 1 : 0,
                duration:
                    reduceMotionOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                child: ColoredBox(
                  color: PaintBallPalette.theirs.withValues(alpha: 0.14),
                  child: Center(
                    child: AnimatedScale(
                      scale: state.showKnockout && !_shotInFlight ? 1 : 0.9,
                      duration:
                          reduceMotionOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: Spacing.lg.w,
                          vertical: Spacing.md.h,
                        ),
                        decoration: BoxDecoration(
                          color: PaintBallPalette.field,
                          borderRadius: BorderRadius.circular(18.r),
                          border: Border.all(
                            color: PaintBallPalette.player,
                            width: 1.5.r,
                          ),
                        ),
                        child: Text(
                          'KNOCKOUT',
                          style: textTheme.headlineSmall?.copyWith(
                            color: PaintBallPalette.player,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
              'Choose one shield to hide behind, then choose where you think '
              'your partner hid. Both choices are sent together.\n\n'
              'A correct read removes one life. After each shot, you learn '
              'where your partner really was. The first move is a free opening '
              'because nobody has hidden yet.\n\n'
              'At zero lives, one optional Truth or Dare prompt closes the game.',
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

class _TurnErrorBanner extends StatelessWidget {
  const _TurnErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$message. Retry available.',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          Spacing.md.w,
          Spacing.sm.h,
          Spacing.xs.w,
          Spacing.sm.h,
        ),
        decoration: BoxDecoration(
          color: PaintBallPalette.theirs.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: PaintBallPalette.theirs.withValues(alpha: 0.42),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: PaintBallPalette.theirs,
              size: 20,
            ),
            Gap(Spacing.sm.w),
            Expanded(
              child: Text(
                message,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              tooltip: 'Dismiss error',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns the round history into paint on the field.
///
/// Derived from the rounds rather than stored: the server already records
/// every shot's position and result, so a separate paint table would be a
/// second copy of the same truth, free to drift.
List<PaintSplat> _splatsFor(
  PaintBallSessionState session,
  String? userId, {
  int? excludedRound,
}) {
  final splats = <PaintSplat>[];

  for (final round in session.rounds) {
    final position = round.shotPosition;
    if (position == null || round.roundNumber == excludedRound) continue;

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
class _TurnPrompt extends StatelessWidget {
  const _TurnPrompt({
    required this.state,
    required this.isMyTurn,
    required this.shotInFlight,
    required this.onFire,
    required this.onDone,
  });

  final PaintBallUiState state;
  final bool isMyTurn;
  final bool shotInFlight;
  final VoidCallback onFire;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (shotInFlight) {
      return Column(
        children: [
          Text(
            'Paint is in the air.',
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          Gap(Spacing.sm.h),
          AppButton(
            label: 'Firing...',
            onPressed: null,
            size: ButtonSize.large,
            width: double.infinity,
            isLoading: true,
            animateButton: !reduceMotionOf(context),
          ),
        ],
      );
    }

    // A resolved shot: hold the reveal until they choose to move on, so
    // the moment the field shows their partner's position is not swept
    // away by an animation they did not ask for.
    if (state.pendingReplay != null) {
      final replay = state.pendingReplay!;
      final hit = replay.mine.isHit;
      final wasHit = replay.theirs.isHit;
      final positionCopy =
          'They were behind the '
          '${paintBallPositionName(replay.theirs.hidePosition).toLowerCase()} '
          'shield.';

      // Both landing is its own outcome, and naming it as a shared thing
      // rather than two separate results is what keeps a mutual round
      // feeling like a moment between two people.
      final headline =
          hit && wasHit
              ? 'You got each other'
              : hit
              ? 'Direct hit'
              : wasHit
              ? 'They read you'
              : 'Both missed';

      return Column(
        children: [
          Text(
            headline,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: hit ? PaintBallPalette.mine : PaintBallPalette.player,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            '$positionCopy '
            '${hit ? 'You read them right.' : 'Your next guess has a clue.'}'
            '${wasHit ? ' They found you too.' : ''}',
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.md.h),
          AppButton(
            label: 'Done for now',
            onPressed: onDone,
            size: ButtonSize.medium,
            width: double.infinity,
            animateButton: !reduceMotionOf(context),
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
            'Your move is saved. Waiting for theirs.',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          Gap(Spacing.md.h),
          AppButton(
            label: 'Back to chat',
            onPressed: onDone,
            variant: ButtonVariant.outline,
            size: ButtonSize.medium,
            width: double.infinity,
            animateButton: !reduceMotionOf(context),
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          state.canFire
              ? 'Cover chosen. Target locked.'
              : 'Choose your cover and one target.',
          style: textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.62),
          ),
        ),
        Gap(Spacing.sm.h),
        AppButton(
          label: state.isSubmitting ? 'Firing...' : 'Fire',
          onPressed: state.canFire && !state.isSubmitting ? onFire : null,
          size: ButtonSize.large,
          width: double.infinity,
          isLoading: state.isSubmitting,
          animateButton: !reduceMotionOf(context),
        ),
      ],
    );
  }
}
