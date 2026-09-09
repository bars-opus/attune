import 'dart:async';
import 'dart:math' as math;

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/state/snakes_provider.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_board.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_die.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the player chose on the way out, so the caller can offer a
/// rematch without this screen knowing how a game is created.
enum SnakesExitAction { backToChat, playAgain }

/// The whole game: a board, two tokens, and a die.
class SnakesGameScreen extends ConsumerStatefulWidget {
  const SnakesGameScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SnakesGameScreen> createState() => _SnakesGameScreenState();
}

class _SnakesGameScreenState extends ConsumerState<SnakesGameScreen>
    with WidgetsBindingObserver {
  /// Where the animating token is right now. Null when nothing is moving
  /// and the board draws from the session's own positions.
  int? _walkCell;
  SnakesFeatureMotion? _featureMotion;
  bool _walking = false;

  /// Guards the automatic exit so a rebuild cannot schedule two pops.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(snakesProvider.notifier).load(widget.sessionId);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _walking) return;
    final game = ref.read(snakesProvider);
    if (!game.isRolling && game.pendingTurn == null) {
      unawaited(ref.read(snakesProvider.notifier).load(widget.sessionId));
    }
  }

  /// Walks a token cell by cell, then slides it if a snake or ladder
  /// caught it.
  ///
  /// The walk is most of what makes a good roll feel good -- a token that
  /// teleported would turn the game into a number changing.
  Future<void> _animate(SnakesTurn turn) async {
    if (_walking) return;
    setState(() => _walking = true);

    final sound = ref.read(soundServiceProvider);
    final haptics = ref.read(hapticsProvider);
    final reduceMotion = reduceMotionOf(context);

    if (reduceMotion) {
      // Same information, no movement: the token is simply there.
      setState(() => _walkCell = turn.movedTo);
    } else {
      sound.play(AppSound.gameDice);

      // The walk to where the die pointed. A bounce walks past 100 and
      // comes back, which is why rolled_to is stored rather than derived.
      final forward = turn.rolledTo >= turn.movedFrom;
      final steps = <int>[];
      // didBounce, not movement == bounce: a turn that bounced AND then
      // hit a snake reports the snake, and reading only movement would
      // skip the walk to 100 and back -- the most dramatic thing the
      // game does.
      if (turn.didBounce) {
        for (var cell = turn.movedFrom + 1; cell <= 100; cell++) {
          steps.add(cell);
        }
        for (var cell = 99; cell >= turn.rolledTo; cell--) {
          steps.add(cell);
        }
      } else {
        for (
          var cell = turn.movedFrom + (forward ? 1 : -1);
          forward ? cell <= turn.rolledTo : cell >= turn.rolledTo;
          cell += forward ? 1 : -1
        ) {
          steps.add(cell);
        }
      }

      for (final cell in steps) {
        if (!mounted) return;
        setState(() => _walkCell = cell);
        sound.play(AppSound.gameStep);
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }

      if (turn.movement.isFeature) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        final climbing = turn.movement == SnakesMovement.ladder;
        sound.play(climbing ? AppSound.gameLadder : AppSound.gameSnake);
        climbing ? haptics.light() : haptics.medium();

        // Travels the feature rather than appearing at the far end. A
        // token that teleported would leave the drawn snake decorative --
        // the player would never see it used.
        final span = (turn.movedTo - turn.rolledTo).abs();
        final hops = math.min(span, 12);
        for (var hop = 1; hop <= hops; hop++) {
          if (!mounted) return;
          setState(
            () =>
                _featureMotion = SnakesFeatureMotion(
                  from: turn.rolledTo,
                  to: turn.movedTo,
                  progress: hop / hops,
                  movement: turn.movement,
                ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 46));
        }
        if (!mounted) return;
        setState(() {
          _walkCell = turn.movedTo;
          _featureMotion = null;
        });
        await Future<void>.delayed(const Duration(milliseconds: 240));
      }
    }

    // The result sits on screen before anything moves on. The walk ends
    // and the board is immediately correct, but the player has had no
    // moment to READ it -- the number they rolled, where they landed.
    // Without this the screen left the instant the token stopped.
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    if (!mounted) return;
    setState(() {
      _walking = false;
      _walkCell = null;
      _featureMotion = null;
    });
    await ref.read(snakesProvider.notifier).settleTurn();
  }

  @override
  Widget build(BuildContext context) {
    // Live, like every other game. Without this the screen loaded once
    // and never again: a partner's roll would not appear until the
    // player closed and reopened the game, on a board that still read
    // "Their roll".
    ref.listen(gameSessionLiveProvider(widget.sessionId), (_, _) {
      final game = ref.read(snakesProvider);
      if (!_walking && !game.isRolling && game.pendingTurn == null) {
        unawaited(ref.read(snakesProvider.notifier).load(widget.sessionId));
      }
    });
    ref.watch(gameSessionLiveProvider(widget.sessionId));

    final state = ref.watch(snakesProvider);
    final userId = ref.watch(snakesCurrentUserIdProvider);
    final session = state.session;
    final textTheme = Theme.of(context).textTheme;

    // A queued turn animates on the next frame -- starting an animation
    // during build is a framework error.
    final pending = state.pendingTurn;
    if (pending != null && !_walking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_animate(pending));
      });
    }

    // Nothing left to do here: the roll is in and the board is with the
    // partner. Leaving on its own beats parking the player on a dead
    // board, and matches Paint Ball. Held until any animation finishes
    // so the walk the player came to watch is never cut short.
    if (session != null &&
        session.isActive &&
        !session.isMyTurn(userId) &&
        state.pendingTurn == null &&
        !_walking &&
        !state.isRolling &&
        !_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    if (state.isLoading) {
      return const Scaffold(
        backgroundColor: SnakesPalette.field,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (session == null) {
      return Scaffold(
        backgroundColor: SnakesPalette.field,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Snakes and Ladders'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.errorMessage ?? 'Could not open this game.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed:
                      () => ref
                          .read(snakesProvider.notifier)
                          .load(widget.sessionId),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final yours = session.positionFor(userId);
    final theirs = session.partnerPositionFor(userId);
    final isMine = session.isMyTurn(userId);
    final animatingMine = pending?.playerId == userId;

    return Scaffold(
      backgroundColor: SnakesPalette.field,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Snakes and Ladders'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SnakesBoardView(
                    board: session.board,
                    yourCell:
                        _walkCell != null && animatingMine ? _walkCell! : yours,
                    theirCell:
                        _walkCell != null && !animatingMine
                            ? _walkCell!
                            : theirs,
                    highlightCell: _walkCell,
                    featureMotion: _featureMotion,
                    movingYourToken: animatingMine,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Readout(yours: yours, theirs: theirs),
              const SizedBox(height: 12),
              if (session.isFinished)
                _Finished(
                  youWon: session.winnerUserId == userId,
                  textTheme: textTheme,
                  onPlayAgain:
                      () => Navigator.of(
                        context,
                      ).maybePop(SnakesExitAction.playAgain),
                )
              else ...[
                // §12.1: the exact-finish rule only frustrates when it is
                // a surprise. Said out loud in the last stretch, it reads
                // as the board being cheeky rather than the app refusing
                // to let you finish.
                if (yours >= 94)
                  Text(
                    'Needs an exact roll to finish',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                const SizedBox(height: 8),
                SnakesDie(
                  face: state.dieFace,
                  rolling: state.isRolling,
                  enabled: isMine && !_walking,
                  onTap: () {
                    ref.read(hapticsProvider).selection();
                    unawaited(ref.read(snakesProvider.notifier).roll());
                  },
                ),
                const SizedBox(height: 10),
                // THE NUMBER, large, while the roll plays out. Pips on a
                // die read at a glance only if you are looking at the
                // die -- and during the walk the player is watching their
                // token, not the corner of the screen. The digit says
                // what happened without being read.
                if (state.dieFace != null && !state.isRolling)
                  Text(
                    '${state.dieFace}',
                    style: textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  )
                else
                  Text(
                    _walking
                        ? ''
                        : isMine
                        ? 'Your roll'
                        : 'Their roll',
                    style: textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                      letterSpacing: 1.2,
                    ),
                  ),
              ],
              if (state.errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: SnakesPalette.them,
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where each token stands, in words.
///
/// A 10x10 grid on a phone makes "where am I" a squinting exercise; this
/// is the reliable answer regardless of whether a numeral is visible.
class _Readout extends StatelessWidget {
  const _Readout({required this.yours, required this.theirs});

  final int yours;
  final int theirs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget entry(String label, int cell, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          '$label  ${cell == 0 ? '–' : cell}',
          style: textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        entry('You', yours, SnakesPalette.you),
        entry('Them', theirs, SnakesPalette.them),
      ],
    );
  }
}

/// The ending. Who arrived, and nothing else.
///
/// No confetti, no record, no forfeit: a die decided it, and dressing
/// that up as an achievement would be the opposite of cooling off.
class _Finished extends StatelessWidget {
  const _Finished({
    required this.youWon,
    required this.textTheme,
    this.onPlayAgain,
  });

  final bool youWon;
  final TextTheme textTheme;
  final VoidCallback? onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          youWon ? 'You got there first.' : 'They got there first.',
          style: textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        if (onPlayAgain != null) ...[
          FilledButton(
            onPressed: onPlayAgain,
            style: FilledButton.styleFrom(
              backgroundColor: SnakesPalette.you,
              foregroundColor: SnakesPalette.field,
            ),
            child: const Text('Play again'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: const Text('Back to chat'),
        ),
      ],
    );
  }
}
