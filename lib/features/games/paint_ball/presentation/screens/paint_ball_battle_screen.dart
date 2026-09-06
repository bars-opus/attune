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
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';

class PaintBallBattleScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const PaintBallBattleScreen({super.key, required this.sessionId});

  @override
  ConsumerState<PaintBallBattleScreen> createState() =>
      _PaintBallBattleScreenState();
}

class _PaintBallBattleScreenState extends ConsumerState<PaintBallBattleScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Drives the paintball across the field.
  ///
  /// The shot is sent to the server the moment Fire is tapped -- the
  /// animation is not a gate on the turn. If it were, a slow frame or a
  /// backgrounded app could cost someone their move.
  late final AnimationController _shotController;

  /// Drives the round replay: both sides emerge, aim, fire, and land.
  ///
  /// Longer than a single shot because it choreographs four beats rather
  /// than one, and because it is the moment the round is *for* -- rushing
  /// it would waste the only point at which the game shows the players
  /// what they did to each other.
  late final AnimationController _replayController;
  bool _routingToKnockout = false;
  bool _shotInFlight = false;
  bool _replayInFlight = false;

  /// Guards the automatic exit so a rebuild cannot schedule a second pop.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _shotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _replayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
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
    _replayController.dispose();
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

  /// Plays a resolved round, then hands the field back.
  ///
  /// Driven here rather than in the provider because the widget owns the
  /// animation clock: state that ticked frames would be responsible for
  /// timing, and a rebuild mid-flight would restart the beat.
  Future<void> _playReplay() async {
    if (_replayInFlight) return;
    setState(() => _replayInFlight = true);
    final notifier = ref.read(paintBallSessionProvider.notifier);
    try {
      if (!reduceMotionOf(context)) {
        await _replayController.forward(from: 0);
      }
    } finally {
      if (mounted) {
        _replayController.reset();
        setState(() => _replayInFlight = false);
        // Clearing sends the opponent's triangle back into hiding and
        // resets the choices, so the next round starts from nothing.
        notifier.clearReplay();
      }
    }
  }

  /// A tap anywhere jumps to the end state. The replay must never gate a
  /// player from acting, and someone who has seen it should not be made
  /// to sit through it again.
  void _skipReplay() {
    if (!_replayInFlight) return;
    _replayController.stop();
    _replayController.value = 1;
  }

  Future<void> _fire() async {
    if (_shotInFlight) return;
    final notifier = ref.read(paintBallSessionProvider.notifier);
    setState(() {
      _shotInFlight = true;
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

    // A queued replay drives the field until it has played. It starts on
    // the next frame rather than during build, since starting an
    // animation while building is a framework error.
    // Null until it loads; the field falls back to "THEIR COVER" rather
    // than showing a gap where a name will appear.
    final partnerName = ref.watch(partnerNameProvider).valueOrNull;

    final replay = state.pendingReplay;
    if (replay != null && !_replayInFlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_playReplay());
      });
    }
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Your move is in and the round is with your partner: there is
    // nothing left to do here, so leave rather than parking the player on
    // a dead board behind a button. They land back in the chat, where the
    // game's own bubble shows the move they just made.
    //
    // Held until any replay has finished, so the exchange the player came
    // to watch is never cut off by the exit.
    // lastReplay is checked as well as pendingReplay because there is a
    // frame between the shot clearing and the replay's post-frame
    // callback starting where neither flag is set -- and leaving in that
    // gap would cut the exchange the player came to watch.
    // beginNextTurn clears it, which is exactly when leaving is right.
    if (session.status == 'active' &&
        !session.isCurrentUserTurn(currentUserId) &&
        state.pendingReplay == null &&
        state.lastReplay == null &&
        !_shotInFlight &&
        !_replayInFlight &&
        !_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(paintBallSessionProvider.notifier).beginNextTurn();
        Navigator.of(context).pop(PaintBallExitAction.backToChat);
      });
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
                partnerName: partnerName,
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
                      // A tap anywhere during a replay skips to the end.
                      // Wrapping rather than absorbing: when nothing is
                      // playing this is inert, so the field's own taps
                      // still reach it.
                      GestureDetector(
                        onTap: _replayInFlight ? _skipReplay : null,
                        behavior:
                            _replayInFlight
                                ? HitTestBehavior.opaque
                                : HitTestBehavior.deferToChild,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            _shotController,
                            _replayController,
                          ]),
                          builder:
                              (context, _) => PaintBallField(
                                splats: _splatsFor(
                                  session,
                                  currentUserId,
                                  // Only while a replay is on screen: the
                                  // paint belongs to the shot you are
                                  // watching land, not to the match.
                                  onlyRound: replay?.roundNumber,
                                ),
                                // During a replay the field shows what the
                                // round actually was, not what this player
                                // chose -- both sides are on screen, so the
                                // positions come from the resolved halves.
                                myPosition:
                                    replay != null
                                        ? replay.mine.hidePosition
                                        : state.hidePosition,
                                selectedShot:
                                    replay != null
                                        ? replay.mine.shotPosition
                                        : state.shotPosition,
                                revealedPartnerPosition:
                                    replay != null
                                        ? replay.theirs.hidePosition
                                        : _shotInFlight
                                        ? null
                                        : state.revealedPartnerPosition,
                                theirRevealedShot:
                                    replay != null
                                        ? replay.theirs.shotPosition
                                        : null,
                                replayProgress:
                                    _replayInFlight
                                        ? _replayController.value
                                        : null,
                                isReplaying: _replayInFlight,
                                isMyTurn: session.isCurrentUserTurn(
                                  currentUserId,
                                ),
                                partnerName: partnerName,
                                theirStreak: replay?.theirStreak ?? 1,
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
/// Paint for the round currently being replayed, and nothing else.
///
/// The field used to accumulate every past shot. That is a map of where
/// your partner has already fired -- a record of their habits sitting on
/// the board, free to read, which is exactly the clue this game asks you
/// to earn instead. It also meant the board grew steadily dirtier until
/// the covers were hard to make out.
///
/// So paint appears with the shot that made it and leaves with the
/// replay.
List<PaintSplat> _splatsFor(
  PaintBallSessionState session,
  String? userId, {
  int? onlyRound,
}) {
  if (onlyRound == null) return const [];

  final splats = <PaintSplat>[];

  for (final round in session.rounds) {
    final position = round.shotPosition;
    if (position == null || round.roundNumber != onlyRound) continue;

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

    // Deliberately quiet.
    //
    // The field already says everything: where you are, where you aimed,
    // whether it landed. Narrating it underneath ("Direct hit", "They were
    // behind the middle shield") did two bad things -- it handed out a
    // read the player should have earned by watching, and it turned a duel
    // into a scoreboard. This game is a small moment between two people,
    // not a match report.
    //
    // So: nothing while a round is playing, nothing after it resolves. The
    // only text that stays is the one thing the board cannot show -- that
    // it is now the other person's turn.
    if (shotInFlight || state.pendingReplay != null) {
      return const SizedBox.shrink();
    }

    // Not your turn: the screen is already leaving on its own, so this is
    // only ever on screen for the frame between the round passing and the
    // pop. A "Back to chat" button here would be asking the player to
    // dismiss something that was about to dismiss itself.
    if (!isMyTurn) {
      return const BreathingDots(size: 6);
    }

    // Your turn, nothing in flight. There is no Fire button: firing is
    // tapping your own character once you have aimed (see the field), so
    // a button here would be a second way to do the same thing and would
    // pull attention off the board where the game actually is.
    //
    // A single line survives only until the player has done both things,
    // because a board with no instructions is a puzzle the first time.
    if (state.canFire) {
      return const SizedBox.shrink();
    }

    return Text(
      state.shotPosition == null ? 'Tap a target.' : 'Tap yourself to fire.',
      style: textTheme.bodySmall?.copyWith(
        color: Colors.white.withValues(alpha: 0.5),
      ),
      textAlign: TextAlign.center,
    );
  }
}
