import 'dart:async';

import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shown after this user submits, until the partner does too.
///
/// Polls get_revealed_round rather than streaming game_session_rounds.
/// this_or_that's watchRound streams the raw row, and RLS grants
/// relationship members every column of it — so a Realtime subscription
/// delivers the partner's answer the instant they submit, before the
/// reveal. §8.4 calls that mechanic non-negotiable, so this flow uses
/// the one read path that is gated, at the cost of a few seconds'
/// latency.
class SessionGameWaitingScreen extends StatefulWidget {
  const SessionGameWaitingScreen({
    super.key,
    required this.roundId,
    required this.onRevealed,
    this.onLeaveToChat,
    SessionGameRepository? repository,
  }) : _repository = repository,
       _testBothAnswered = null;

  /// Renders a fixed state without polling, for widget tests.
  ///
  /// [partnerAnswer] exists so a test can describe a round's state
  /// symmetrically (both_answered alongside what was answered) but is
  /// deliberately NOT stored: this screen renders before the reveal and
  /// must never hold a partner's answer, even in a dead field, or a
  /// later reader could wire it into build() and defeat the §8.4 gate.
  const SessionGameWaitingScreen.forTesting({
    super.key,
    required bool bothAnswered,
    required String? partnerAnswer,
    VoidCallback? onRevealed,
    this.onLeaveToChat,
  }) : roundId = 'test',
       onRevealed = onRevealed ?? _noop,
       _repository = null,
       _testBothAnswered = bothAnswered;

  static void _noop() {}

  final String roundId;
  final VoidCallback onRevealed;

  /// Called when the grace window expires without the partner answering.
  ///
  /// Session games are asynchronous: a partner may answer in an hour or
  /// tomorrow, and holding someone on a blocking spinner until then made
  /// the game feel broken. After the window, the player returns to the
  /// chat, where the game card carries the state instead.
  final VoidCallback? onLeaveToChat;
  final SessionGameRepository? _repository;
  final bool? _testBothAnswered;

  @override
  State<SessionGameWaitingScreen> createState() =>
      _SessionGameWaitingScreenState();
}

class _SessionGameWaitingScreenState extends State<SessionGameWaitingScreen> {
  Timer? _poll;
  Timer? _grace;
  bool _revealed = false;
  bool _left = false;

  /// Three seconds: fast enough that a partner answering feels
  /// near-immediate, slow enough that a five-minute wait costs ~100
  /// requests rather than thousands.
  static const _pollInterval = Duration(seconds: 3);

  /// How long to wait before handing off to the chat card.
  ///
  /// Twenty seconds covers a partner who is answering right now without
  /// stranding one who is not: session games have no turn order, so the
  /// other player may not even have the app open.
  static const _graceWindow = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    if (widget._testBothAnswered == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fireReveal());
      return;
    }
    if (widget._testBothAnswered != null) return; // test, not yet revealed
    _poll = Timer.periodic(_pollInterval, (_) => unawaited(_check()));

    // The same-room case: partners playing together answer within
    // seconds, and bouncing them to the chat only to tap back in would be
    // worse than a brief wait. Past this window they are not in the same
    // room, so the chat card takes over.
    _grace = Timer(_graceWindow, _leaveToChat);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _grace?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final repository = widget._repository ?? SessionGameRepository();
    try {
      final round = await repository.fetchRevealedRound(widget.roundId);
      if (round.bothAnswered && mounted) _fireReveal();
    } catch (_) {
      // A transient failure just means waiting one more interval. The
      // reveal is not time-critical and a visible error here would be
      // noise during a normal wait.
    }
  }

  void _fireReveal() {
    if (_revealed || _left) return; // exactly once, even if a poll overlaps
    _revealed = true;
    _poll?.cancel();
    _grace?.cancel();
    widget.onRevealed();
  }

  void _leaveToChat() {
    // A reveal that landed first wins: the partner answered inside the
    // window, so showing the result beats returning to the chat.
    if (_revealed || _left) return;
    _left = true;
    _poll?.cancel();
    _grace?.cancel();
    widget.onLeaveToChat?.call();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Waiting for your partner', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            // Says what happens next, so the wait does not read as a
            // stuck screen. Their answer is already saved; nothing is
            // lost by leaving.
            Text(
              'Your answer is saved. You can carry on in the chat — '
              'we will let you know when they answer.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            // Available immediately, not only after the grace window: a
            // player who already knows their partner is asleep should not
            // have to wait out a timer to leave.
            if (widget.onLeaveToChat != null)
              TextButton(
                onPressed: _leaveToChat,
                child: const Text('Back to chat'),
              ),
          ],
        ),
      ),
    );
  }
}
