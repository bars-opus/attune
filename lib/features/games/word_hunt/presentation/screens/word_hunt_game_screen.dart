import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/widgets/round_handoff.dart';
import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/state/word_hunt_provider.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_board.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// The hunt: the grid, the word, and a running number.
///
/// Nothing else on the screen. Everything a player needs while searching
/// is those three things, and the rest of it -- the partner, the result,
/// the comparison -- is deliberately absent until both attempts are over.
class WordHuntGameScreen extends ConsumerStatefulWidget {
  const WordHuntGameScreen({
    super.key,
    required this.relationshipId,
    this.sessionId,
  });

  /// Whose hunt. Needed to start one, and to find the hunt already open
  /// when the player arrived without a session in hand.
  final String relationshipId;

  /// The session a chat card pointed at. Null when the player came from
  /// the picker, in which case this screen finds or starts the hunt.
  final String? sessionId;

  @override
  ConsumerState<WordHuntGameScreen> createState() => _WordHuntGameScreenState();
}

/// Resolves which hunt this is, then hands off to the hunt itself.
///
/// The lobby that used to do this was a toll gate: it re-stated the
/// rules the board states better, and made the player press a button to
/// see a grid they had already asked for. Everything it decided --
/// start one, join theirs, resume the one in progress -- is decided here
/// without a screen.
///
/// It exists as a separate widget because the hunt's own state provider
/// is keyed by session id, and there is no session id until this runs.
class _WordHuntGameScreenState extends ConsumerState<WordHuntGameScreen> {
  String? _sessionId;
  bool _resolving = true;
  String? _error;

  /// The idempotency key for THIS attempt to start a hunt.
  ///
  /// Held across retries on purpose (checklist 1.1, 2.18). A create whose
  /// response was dropped may well have succeeded on the server, and
  /// minting a fresh key on "Try again" would start a second hunt for a
  /// couple who asked for one. Cleared once a create returns, so a later
  /// hunt is genuinely new.
  String? _createKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_resolve()));
  }

  Future<void> _resolve() async {
    final given = widget.sessionId;
    if (given != null) {
      setState(() {
        _sessionId = given;
        _resolving = false;
      });
      return;
    }

    // From the picker: resume the couple's open hunt, or start one. The
    // tap on the game already said what the player wants; the lobby
    // asking "Invite them to hunt?" was asking it twice.
    final gateway = ref.read(wordHuntGatewayProvider);
    try {
      final existing = await gateway.getActiveSession(widget.relationshipId);
      if (!mounted) return;

      String sessionId;
      if (existing != null) {
        sessionId = existing.sessionId;
      } else {
        final key =
            _createKey ??=
                'word_hunt:${widget.relationshipId}:${const Uuid().v4()}';
        sessionId = await gateway.createSession(
          relationshipId: widget.relationshipId,
          idempotencyKey: key,
        );
        // Only a create that came back retires its key. A failure keeps
        // it, so the retry is the same request rather than a new one.
        _createKey = null;
      }

      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _resolving = false;
      });
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'Could not reach the game. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = _sessionId;
    if (_resolving || sessionId == null) {
      return Scaffold(
        backgroundColor: WordHuntPalette.field,
        appBar: AppBar(
          backgroundColor: WordHuntPalette.field,
          foregroundColor: WordHuntPalette.letter,
          elevation: 0,
          title: const Text('Word Hunt'),
        ),
        body: SafeArea(
          child:
              _error == null
                  ? const Center(
                    child: CircularProgressIndicator(
                      color: WordHuntPalette.found,
                    ),
                  )
                  : _Message(
                    text: _error!,
                    actionLabel: 'Try again',
                    onAction: () {
                      setState(() {
                        _resolving = true;
                        _error = null;
                      });
                      unawaited(_resolve());
                    },
                  ),
        ),
      );
    }

    return _WordHuntSessionView(sessionId: sessionId);
  }
}

/// The hunt itself, once there is a session to hunt in.
class _WordHuntSessionView extends ConsumerStatefulWidget {
  const _WordHuntSessionView({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_WordHuntSessionView> createState() =>
      _WordHuntSessionViewState();
}

class _WordHuntSessionViewState extends ConsumerState<_WordHuntSessionView>
    with WidgetsBindingObserver {
  final WordHuntBoardController _board = WordHuntBoardController();
  Timer? _tick;
  int _seenMissNonce = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // One second is enough for a display that only shows whole seconds,
    // and it keeps a game that lasts thirty seconds from repainting sixty
    // times a second for a number that changes once.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Time keeps running through backgrounding -- there is no pause,
    // because a client-controlled pause is a client-controlled clock. On
    // return the state is refetched so the display reseeds from the
    // server rather than drifting.
    if (state == AppLifecycleState.resumed) {
      ref.read(wordHuntProvider(widget.sessionId).notifier).refresh();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _board.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _format(Duration d) {
    final seconds = d.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }

  Future<void> _confirmGiveUp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF141414),
            title: const Text(
              "Stop looking?",
              style: TextStyle(color: WordHuntPalette.letter),
            ),
            content: const Text(
              "You'll see where it was once you both finish. Nothing is "
              "scored either way.",
              style: TextStyle(color: WordHuntPalette.dim, height: 1.45),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Keep looking',
                  style: TextStyle(color: WordHuntPalette.dim),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  "I can't find it",
                  style: TextStyle(color: WordHuntPalette.reveal),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) {
      await ref.read(wordHuntProvider(widget.sessionId).notifier).giveUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(wordHuntProvider(widget.sessionId).notifier);
    final state = ref.watch(wordHuntProvider(widget.sessionId));

    // The second terminal attempt completes the session, which is a
    // game_sessions row change -- so the waiting player's screen leaves on
    // its own rather than needing a tap. The FIRST finish deliberately
    // touches nothing public: that event alone would reveal that the
    // partner had finished.
    ref.listen(gameSessionLiveProvider(widget.sessionId), (_, _) {
      notifier.refresh();
    });
    ref.watch(gameSessionLiveProvider(widget.sessionId));

    // A wrong guess: animate the pill off, say nothing.
    if (state.missNonce != _seenMissNonce) {
      _seenMissNonce = state.missNonce;
      final cells = state.missCells;
      if (cells != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _board.showMiss(cells),
        );
      }
    }

    final session = state.session;

    return Scaffold(
      backgroundColor: WordHuntPalette.field,
      appBar: AppBar(
        backgroundColor: WordHuntPalette.field,
        foregroundColor: WordHuntPalette.letter,
        elevation: 0,
        title: const Text('Word Hunt'),
        actions: [
          if (session != null &&
              session.hasStarted &&
              !session.myStatus.isTerminal)
            TextButton(
              onPressed: state.isSubmitting ? null : _confirmGiveUp,
              child: const Text(
                "Can't find it",
                style: TextStyle(color: WordHuntPalette.dim, fontSize: 14),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child:
            state.isLoading
                ? const Center(
                  child: CircularProgressIndicator(
                    color: WordHuntPalette.found,
                  ),
                )
                : session == null
                ? _Message(
                  text:
                      state.errorMessage ?? 'This hunt is no longer available.',
                  actionLabel: 'Back to chat',
                  onAction: () => context.pop(),
                )
                : _body(context, notifier, state, session),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WordHuntNotifier notifier,
    WordHuntUiState state,
    WordHuntSession session,
  ) {
    // Both attempts terminal: the reveal, for both players, including
    // whoever did not find it.
    if (session.bothTerminal) {
      return WordHuntReveal(
        session: session,
        partnerName: partnerNameOr(ref),
        onPlayAgain: () => context.pop(),
        onBackToChat: () => context.pop(),
      );
    }

    // Finished, waiting on the partner. Their own time is shown; nothing
    // of the partner's is, because nothing of it has been sent.
    if (session.isWaitingForPartner) {
      // Their attempt is over and the hunt is with the partner, who may
      // answer in an hour. The result is held long enough to read, then
      // the game leaves on its own -- it used to sit here behind a
      // button the player had to press to leave a screen that had
      // nothing more to say.
      return RoundHandoff(
        onLeave: () {
          if (context.mounted) Navigator.of(context).maybePop();
        },
        child: _WaitingView(
          elapsed: session.myElapsedMs,
          foundIt: session.myStatus.foundIt,
          onBackToChat: () => context.pop(),
        ),
      );
    }

    // An invitation, from either end. Both used to be a lobby: the
    // sender got "Waiting for them to join" over a cancel button, the
    // receiver got a screen asking whether they meant to tap the thing
    // they tapped. Neither is a screen; both are a line and a choice.
    if (session.isInvited) {
      final me = ref.read(wordHuntCurrentUserIdProvider);
      return _InvitationView(
        mine: session.initiatorId == me,
        partnerName: partnerNameOr(ref),
        busy: state.isSubmitting,
        error: state.errorMessage,
        onJoin: notifier.accept,
        onDecline: () async {
          await notifier.decline();
          // Navigator rather than context.pop(): the invitation is gone,
          // so is the reason to be here, and maybePop leaves correctly
          // whether this was pushed by GoRouter or anything else.
          if (context.mounted) Navigator.of(context).maybePop();
        },
      );
    }

    if (!session.hasStarted) {
      return _StartView(
        wordLength: session.wordLength,
        busy: state.isSubmitting,
        error: state.errorMessage,
        onStart: notifier.start,
      );
    }

    final grid = session.grid;
    final word = session.word;
    if (grid == null || word == null) {
      return _Message(
        text: 'The grid did not load. Pull back and open it again.',
        actionLabel: 'Retry',
        onAction: notifier.refresh,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FIND',
                    style: TextStyle(
                      color: WordHuntPalette.dim,
                      fontSize: 11,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    word,
                    style: const TextStyle(
                      color: WordHuntPalette.letter,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
              Semantics(
                // Read as a live region so a screen reader announces the
                // elapsed time on demand rather than interrupting.
                liveRegion: false,
                label: 'Elapsed time',
                child: Text(
                  _format(notifier.displayElapsed),
                  style: const TextStyle(
                    color: WordHuntPalette.dim,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: WordHuntBoard(
                controller: _board,
                grid: grid,
                wordLength: word.length,
                enabled: !state.isSubmitting && !session.myStatus.isTerminal,
                lockedCells:
                    session.myStatus.foundIt ? session.placement : null,
                onSubmit: notifier.submit,
              ),
            ),
          ),
        ),
        if (state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              state.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 13),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _StartView extends StatelessWidget {
  const _StartView({
    required this.wordLength,
    required this.busy,
    required this.error,
    required this.onStart,
  });

  final int wordLength;
  final bool busy;
  final String? error;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            wordLength > 0
                ? 'A $wordLength-letter word is hidden in the grid.'
                : 'One word is hidden in the grid.',
            style: const TextStyle(
              color: WordHuntPalette.letter,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'It can run in any direction, including backwards and '
            'diagonally. Drag across the letters when you find it.',
            style: TextStyle(
              color: WordHuntPalette.dim,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Tapping Start begins your clock.',
            style: TextStyle(color: WordHuntPalette.reveal, fontSize: 14),
          ),
          const Spacer(),
          if (error != null) ...[
            Text(
              error!,
              style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 14),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: busy ? null : onStart,
            style: FilledButton.styleFrom(
              backgroundColor: WordHuntPalette.found,
              foregroundColor: const Color(0xFF04201C),
              disabledBackgroundColor: WordHuntPalette.grid,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child:
                busy
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: WordHuntPalette.dim,
                      ),
                    )
                    : const Text(
                      'Start',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Finished, and the partner has not. Shows their own time and nothing
/// else, because nothing else has been sent.
class _WaitingView extends StatefulWidget {
  const _WaitingView({
    required this.elapsed,
    required this.foundIt,
    required this.onBackToChat,
  });

  final int? elapsed;
  final bool foundIt;
  final VoidCallback onBackToChat;

  @override
  State<_WaitingView> createState() => _WaitingViewState();
}

class _WaitingViewState extends State<_WaitingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool _configured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not readable in initState, and a reduce-motion user
    // must not get a looping animation.
    if (!_configured) {
      _configured = true;
      if (!reduceMotionOf(context)) _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.elapsed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          // The breathing mark the other session games use, rather than a
          // spinner: nothing is loading, someone is thinking.
          AnimatedBuilder(
            animation: _breath,
            builder:
                (context, _) => SizedBox(
                  height: 96,
                  width: 96,
                  child: CustomPaint(painter: _BreathPainter(_breath.value)),
                ),
          ),
          const SizedBox(height: 32),
          Text(
            widget.foundIt ? 'You found it.' : "You didn't find it.",
            style: const TextStyle(
              color: WordHuntPalette.letter,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (elapsed != null) ...[
            const SizedBox(height: 8),
            Text(
              '${(elapsed / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(
                color: WordHuntPalette.found,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            "You'll both see the result once they finish.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WordHuntPalette.dim,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: widget.onBackToChat,
            style: TextButton.styleFrom(
              foregroundColor: WordHuntPalette.dim,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Back to chat', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _BreathPainter extends CustomPainter {
  const _BreathPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final base = size.width * 0.22;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.28) % 1.0;
      canvas.drawCircle(
        centre,
        base + phase * size.width * 0.26,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = WordHuntPalette.found.withValues(alpha: 0.42 * (1 - phase)),
      );
    }
    canvas.drawCircle(
      centre,
      base,
      Paint()..color = WordHuntPalette.found.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(_BreathPainter old) => old.t != t;
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WordHuntPalette.dim,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: WordHuntPalette.found),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

/// An unaccepted invitation, from either end.
///
/// Replaces two lobby states: "Waiting for them to join" over a cancel
/// button, and a screen asking the receiver to confirm the tap they just
/// made. The sender's side has no primary action on purpose -- there is
/// nothing for them to do but wait, and a button would imply otherwise.
class _InvitationView extends StatelessWidget {
  const _InvitationView({
    required this.mine,
    required this.partnerName,
    required this.busy,
    required this.error,
    required this.onJoin,
    required this.onDecline,
  });

  /// True when this player sent the invitation.
  final bool mine;

  /// What to call the other player, by name rather than "them".
  final String partnerName;
  final bool busy;
  final String? error;
  final Future<void> Function() onJoin;
  final Future<void> Function() onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            mine
                ? 'Waiting for $partnerName to join.'
                : '$partnerName started a hunt.',
            style: const TextStyle(
              color: WordHuntPalette.letter,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            mine
                ? 'One word is hidden in a grid you will both search. '
                    'Nothing starts until they open it.'
                : 'One word is hidden in a grid you will both search. '
                    'Your clock starts when you do, not now.',
            style: const TextStyle(
              color: WordHuntPalette.dim,
              fontSize: 15,
              height: 1.45,
            ),
          ),
          const Spacer(),
          if (error != null) ...[
            Text(
              error!,
              style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 14),
            ),
            const SizedBox(height: 16),
          ],
          if (!mine)
            _PrimaryButton(
              label: 'Join the hunt',
              busy: busy,
              onPressed: () => onJoin(),
            ),
          if (!mine) const SizedBox(height: 12),
          _SecondaryButton(
            label: mine ? 'Cancel the invitation' : 'Not now',
            busy: busy,
            onPressed: () => onDecline(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: WordHuntPalette.found,
      foregroundColor: const Color(0xFF04201C),
      disabledBackgroundColor: WordHuntPalette.grid,
      disabledForegroundColor: WordHuntPalette.dim,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child:
        busy
            ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WordHuntPalette.dim,
              ),
            )
            : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
  );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: busy ? null : onPressed,
    style: TextButton.styleFrom(
      foregroundColor: WordHuntPalette.dim,
      minimumSize: const Size.fromHeight(48),
    ),
    child: Text(label, style: const TextStyle(fontSize: 15)),
  );
}
