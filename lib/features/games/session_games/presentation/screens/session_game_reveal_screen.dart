import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:flutter/material.dart';

/// Shows both answers side by side once the gate has opened.
///
/// Takes an already-fetched [RevealedRound] rather than fetching one:
/// the caller obtained it from get_revealed_round, and a screen that
/// could fetch answers itself would be a second path to guard.
class SessionGameRevealScreen extends StatelessWidget {
  const SessionGameRevealScreen({
    super.key,
    required this.round,
    required this.yourAnswerIsA,
    required this.onNext,
  });

  final RevealedRound round;

  /// Which slot belongs to the viewer, so the labels are right.
  final bool yourAnswerIsA;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // Defensive: the caller should only build this once bothAnswered is
    // true, but rendering nulls as empty rather than "null" keeps a
    // mistake from displaying something that looks like an answer.
    final yours = (yourAnswerIsA ? round.answerA : round.answerB) ?? '';
    final theirs = (yourAnswerIsA ? round.answerB : round.answerA) ?? '';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('You said', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(yours, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text('They said', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(theirs, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          FilledButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}
