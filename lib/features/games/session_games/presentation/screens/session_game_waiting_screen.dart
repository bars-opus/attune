import 'dart:async';

import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
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
    SessionGameRepository? repository,
  })  : _repository = repository,
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
  })  : roundId = 'test',
        onRevealed = onRevealed ?? _noop,
        _repository = null,
        _testBothAnswered = bothAnswered;

  static void _noop() {}

  final String roundId;
  final VoidCallback onRevealed;
  final SessionGameRepository? _repository;
  final bool? _testBothAnswered;

  @override
  State<SessionGameWaitingScreen> createState() =>
      _SessionGameWaitingScreenState();
}

class _SessionGameWaitingScreenState extends State<SessionGameWaitingScreen> {
  Timer? _poll;
  bool _revealed = false;

  /// Three seconds: fast enough that a partner answering feels
  /// near-immediate, slow enough that a five-minute wait costs ~100
  /// requests rather than thousands.
  static const _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    if (widget._testBothAnswered == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fireReveal());
      return;
    }
    if (widget._testBothAnswered != null) return; // test, not yet revealed
    _poll = Timer.periodic(_pollInterval, (_) => unawaited(_check()));
  }

  @override
  void dispose() {
    _poll?.cancel();
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
    if (_revealed) return; // exactly once, even if a poll overlaps
    _revealed = true;
    _poll?.cancel();
    widget.onRevealed();
  }

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Waiting for your partner'),
        ],
      ),
    );
  }
}
