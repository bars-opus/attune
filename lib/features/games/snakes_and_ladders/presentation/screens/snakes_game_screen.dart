import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/state/snakes_provider.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_board.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_die.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The whole game: a board, two tokens, and a die.
class SnakesGameScreen extends ConsumerStatefulWidget {
  const SnakesGameScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SnakesGameScreen> createState() => _SnakesGameScreenState();
}

class _SnakesGameScreenState extends ConsumerState<SnakesGameScreen> {
  /// Where the animating token is right now. Null when nothing is moving
  /// and the board draws from the session's own positions.
  int? _walkCell;
  bool _walking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(snakesProvider.notifier).load(widget.sessionId);
    });
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
      if (turn.movement == SnakesMovement.bounce) {
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
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) return;
        final climbing = turn.movement == SnakesMovement.ladder;
        sound.play(climbing ? AppSound.gameLadder : AppSound.gameSnake);
        climbing ? haptics.light() : haptics.medium();
        setState(() => _walkCell = turn.movedTo);
        await Future<void>.delayed(const Duration(milliseconds: 460));
      }
    }

    if (!mounted) return;
    setState(() {
      _walking = false;
      _walkCell = null;
    });
    await ref.read(snakesProvider.notifier).settleTurn();
  }

  @override
  Widget build(BuildContext context) {
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

    if (state.isLoading || session == null) {
      return const Scaffold(
        backgroundColor: SnakesPalette.field,
        body: Center(child: CircularProgressIndicator()),
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
  const _Finished({required this.youWon, required this.textTheme});

  final bool youWon;
  final TextTheme textTheme;

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
