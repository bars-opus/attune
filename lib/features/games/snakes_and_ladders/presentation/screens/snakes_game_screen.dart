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

/// The whole game, and the only Snakes screen: a board, two tokens, and
/// a die.
///
/// There used to be a lobby in front of this -- a screen that said "no
/// talking required" over a button to press before the game would open.
/// It was a toll gate. Every state it handled (start one, join theirs,
/// wait for them, carry on) is a state the board can show while ALSO
/// showing the board, so the board shows them and the lobby is gone.
class SnakesGameScreen extends ConsumerStatefulWidget {
  const SnakesGameScreen({
    super.key,
    required this.relationshipId,
    this.sessionId,
  });

  /// Whose game. Needed to start one, and to find the game in progress
  /// when the player arrived without a session in hand.
  final String relationshipId;

  /// The session a chat card pointed at. Null when the player came from
  /// the picker, in which case this screen finds or starts the game.
  final String? sessionId;

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

  /// The session this screen settled on: the one it was given, the one it
  /// found in progress, or the one it started.
  String? _sessionId;

  /// True while starting, finding, joining -- anything that changes which
  /// session this is. Distinct from the notifier's isLoading, which is
  /// about fetching a session's state.
  bool _resolving = true;

  /// Set once the player has been offered the invitation and joined it,
  /// so a rebuild cannot accept twice.
  bool _joining = false;
  String? _resolveError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_resolve()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Works out which game this is, and opens it.
  ///
  /// Given a session, that is the game -- including one that is still an
  /// unaccepted invitation, which is the whole point: tapping a card you
  /// sent shows the board with the die put away rather than a screen
  /// apologising for the wait.
  ///
  /// Given none, the couple's game in progress is the game, and if they
  /// have none, one is started. Starting from the picker used to need a
  /// button press on a lobby; the tap on the game in the picker already
  /// said what the player wants.
  Future<void> _resolve() async {
    final notifier = ref.read(snakesProvider.notifier)..clearError();

    var sessionId = widget.sessionId;
    if (sessionId == null) {
      final existing = await notifier.findActive(widget.relationshipId);
      if (!mounted) return;
      sessionId =
          existing?.sessionId ??
          await notifier.createSession(widget.relationshipId);
      if (!mounted) return;
      if (sessionId == null) {
        setState(() {
          _resolving = false;
          _resolveError =
              ref.read(snakesProvider).errorMessage ??
              'Could not start a game.';
        });
        return;
      }
    }

    setState(() {
      _sessionId = sessionId;
      _resolving = false;
    });
    await notifier.load(sessionId);
  }

  /// Accepts the partner's invitation, then reloads so the board is live.
  Future<void> _join(String sessionId) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _resolveError = null;
    });
    final ok = await ref.read(snakesProvider.notifier).acceptSession(sessionId);
    if (!mounted) return;
    setState(() => _joining = false);
    if (!ok) return;
    await ref.read(snakesProvider.notifier).load(sessionId);
  }

  /// Cancels an invitation, or declines the partner's, and leaves. The
  /// reason to be on this screen goes with it.
  Future<void> _decline(String sessionId) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _resolveError = null;
    });
    final ok = await ref
        .read(snakesProvider.notifier)
        .declineSession(sessionId);
    if (!mounted) return;
    setState(() => _joining = false);
    if (ok && mounted) Navigator.of(context).maybePop();
  }

  /// Starts the next game and swaps this screen onto it, so a rematch
  /// is one tap and stays where the players already are.
  Future<void> _playAgain() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _resolveError = null;
    });
    final next = await ref
        .read(snakesProvider.notifier)
        .createSession(widget.relationshipId);
    if (!mounted) return;
    setState(() {
      _joining = false;
      if (next != null) _sessionId = next;
    });
    if (next != null) await ref.read(snakesProvider.notifier).load(next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sessionId = _sessionId;
    if (state != AppLifecycleState.resumed || _walking || sessionId == null) {
      return;
    }
    final game = ref.read(snakesProvider);
    if (!game.isRolling && game.pendingTurn == null) {
      unawaited(ref.read(snakesProvider.notifier).load(sessionId));
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
    final sessionId = _sessionId;

    // Live, like every other game. Without this the screen loaded once
    // and never again: a partner's roll would not appear until the
    // player closed and reopened the game, on a board that still read
    // "Their roll". It also carries the invitation the moment the
    // partner accepts it, which turns the waiting board into a live one
    // with nothing to press.
    if (sessionId != null) {
      ref.listen(gameSessionLiveProvider(sessionId), (_, _) {
        final game = ref.read(snakesProvider);
        if (!_walking && !game.isRolling && game.pendingTurn == null) {
          unawaited(ref.read(snakesProvider.notifier).load(sessionId));
        }
      });
      ref.watch(gameSessionLiveProvider(sessionId));
    }

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

    if (_resolving || (state.isLoading && session == null)) {
      return const Scaffold(
        backgroundColor: SnakesPalette.field,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (session == null || sessionId == null) {
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
                  _resolveError ??
                      state.errorMessage ??
                      'Could not open this game.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _resolving = true;
                      _resolveError = null;
                    });
                    unawaited(_resolve());
                  },
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
                  busy: _joining,
                  // The rematch starts here rather than being handed
                  // back to a caller: with the lobby gone there is no
                  // screen behind this one that knows how to start a
                  // game, and the player asked for one HERE.
                  onPlayAgain: _playAgain,
                )
              else if (session.isInvited)
                // An invitation, seen from either end, over the real
                // board. No die: there is no turn to take yet, and a die
                // that cannot be rolled is a button that ignores you.
                _Invitation(
                  mine: session.isInitiator(userId),
                  busy: _joining,
                  textTheme: textTheme,
                  onJoin: () => _join(sessionId),
                  onDecline: () => _decline(sessionId),
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
                // The die is only there on your turn. Waiting for the
                // partner, what matters is the board and the last thing
                // that happened on it -- an idle die just invites taps
                // that do nothing.
                if (isMine || _walking || state.isRolling)
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
                        : "Your partner's turn",
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
    this.busy = false,
    this.onPlayAgain,
  });

  final bool youWon;
  final TextTheme textTheme;
  final bool busy;
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
            onPressed: busy ? null : onPlayAgain,
            style: FilledButton.styleFrom(
              backgroundColor: SnakesPalette.you,
              foregroundColor: SnakesPalette.field,
            ),
            child:
                busy
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                    : const Text('Play again'),
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

/// An unaccepted invitation, shown under the real board.
///
/// Both ends see the same board; only the offer differs. The sender's
/// side deliberately has no primary action -- there is nothing for them
/// to do but wait, and a button would imply otherwise.
class _Invitation extends StatelessWidget {
  const _Invitation({
    required this.mine,
    required this.busy,
    required this.textTheme,
    required this.onJoin,
    required this.onDecline,
  });

  /// True when this player sent the invitation.
  final bool mine;
  final bool busy;
  final TextTheme textTheme;
  final VoidCallback onJoin;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          mine ? "Your partner's turn" : 'They started a game',
          style: textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          mine
              ? 'They roll first once they open it.'
              : 'Roll whenever you like. There is no clock.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 14),
        if (!mine) ...[
          FilledButton(
            onPressed: busy ? null : onJoin,
            style: FilledButton.styleFrom(
              backgroundColor: SnakesPalette.you,
              foregroundColor: SnakesPalette.field,
            ),
            child:
                busy
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                    : const Text('Join the game'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          onPressed: busy ? null : onDecline,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Text(mine ? 'Cancel invitation' : 'Decline'),
        ),
      ],
    );
  }
}
