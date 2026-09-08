import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_board.dart';
import 'package:flutter/material.dart';

/// Both results, and where the word was.
///
/// THE COPY IS THE DESIGN HERE. Two people who did not play at the same
/// time being told one "beat" the other is a small lie: nobody was
/// present for the other person's attempt, and a modified client could
/// solve a 10x10 grid without looking at it. So: two times, side by side,
/// never a winner, never a ranking.
///
/// Sub-second differences are shown as a tie, because the measurement
/// includes Start-response latency, render time and Submit latency -- a
/// player on a worse connection should not lose to network noise, and
/// ranking two numbers that close reports jitter as skill.
class WordHuntReveal extends StatelessWidget {
  const WordHuntReveal({
    super.key,
    required this.session,
    required this.onPlayAgain,
    required this.onBackToChat,
  });

  final WordHuntSession session;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToChat;

  /// Below this, the two times are called a tie.
  static const tieThresholdMs = 1000;

  String _time(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

  String _headline() {
    final mine = session.myElapsedMs;
    final theirs = session.partnerElapsedMs;
    final partnerStatus = session.partnerStatus;

    if (partnerStatus == WordHuntStatus.didNotPlay) {
      return session.myStatus.foundIt ? 'You found it' : 'Nobody found it';
    }

    // No speed comparison unless BOTH found it: there is nothing to
    // compare a time against.
    if (mine == null || theirs == null) {
      if (session.myStatus.foundIt) return 'You found it';
      if (partnerStatus?.foundIt == true) return 'They found it';
      return 'Neither of you found it';
    }

    if ((mine - theirs).abs() < tieThresholdMs) return 'Dead even';
    return mine < theirs ? 'You were quicker' : 'They were quicker';
  }

  @override
  Widget build(BuildContext context) {
    final grid = session.grid;
    final placement = session.placement;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _headline(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WordHuntPalette.letter,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (session.word != null) ...[
            const SizedBox(height: 6),
            Text(
              session.word!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WordHuntPalette.reveal,
                fontSize: 16,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ResultTile(
                  who: 'You',
                  status: session.myStatus,
                  elapsedMs: session.myElapsedMs,
                  accent: WordHuntPalette.found,
                  format: _time,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ResultTile(
                  who: 'Them',
                  status: session.partnerStatus ?? WordHuntStatus.didNotPlay,
                  elapsedMs: session.partnerElapsedMs,
                  accent: WordHuntPalette.reveal,
                  format: _time,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (grid != null)
            AspectRatio(
              aspectRatio: 1,
              child: WordHuntBoard(
                grid: grid,
                wordLength: session.wordLength,
                enabled: false,
                onSubmit: (_) {},
                // Shown to BOTH players, including whoever did not find
                // it: never learning where the word was is maddening
                // rather than kind.
                revealedCells: placement,
                lockedCells: session.myStatus.foundIt ? placement : null,
              ),
            ),
          const SizedBox(height: 28),
          // Play again is the prominent action, not the times. This game
          // sits in the Arcade, and the point of the screen is to get
          // back to playing rather than to dwell on two numbers.
          FilledButton(
            onPressed: onPlayAgain,
            style: FilledButton.styleFrom(
              backgroundColor: WordHuntPalette.found,
              foregroundColor: const Color(0xFF04201C),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Play again',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onBackToChat,
            style: TextButton.styleFrom(
              foregroundColor: WordHuntPalette.dim,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Back to chat', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.who,
    required this.status,
    required this.elapsedMs,
    required this.accent,
    required this.format,
  });

  final String who;
  final WordHuntStatus status;
  final int? elapsedMs;
  final Color accent;
  final String Function(int) format;

  /// A timeout and a surrender read identically here. The database
  /// distinguishes them; the screen must not, because reporting a quit
  /// as a quit would turn a kindness into something to be embarrassed
  /// about.
  String get _label => switch (status) {
    WordHuntStatus.found => elapsedMs == null ? 'Found it' : format(elapsedMs!),
    WordHuntStatus.didNotPlay => "Didn't play",
    _ => "Didn't find it",
  };

  @override
  Widget build(BuildContext context) {
    final found = status.foundIt;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: found ? accent.withValues(alpha: 0.4) : WordHuntPalette.grid,
        ),
      ),
      child: Column(
        children: [
          Text(
            who.toUpperCase(),
            style: const TextStyle(
              color: WordHuntPalette.dim,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: found ? accent : WordHuntPalette.dim,
              fontSize: found ? 24 : 15,
              fontWeight: found ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
