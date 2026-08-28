import 'package:flutter/material.dart';

/// The comparison: what was guessed against what is true.
///
/// Shows no score, tally or percentage. Love Map accumulates rather than
/// grades (§11.1) — a running "you know them 62%" would turn an intimacy
/// tool into a scoreboard, and would show one partner a number the other
/// produced.
class LoveMapRevealScreen extends StatelessWidget {
  const LoveMapRevealScreen({
    super.key,
    required this.yourAnswer,
    required this.theirAnswer,
    required this.isSubject,
    this.previousAnswer,
    this.onNext,
  });

  final String yourAnswer;
  final String theirAnswer;
  final bool isSubject;

  /// The subject's own answer from a previous round of this question, when
  /// it has come round again after six months.
  final String? previousAnswer;

  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final previous = previousAnswer;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('You said', style: textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(yourAnswer, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Text('They said', style: textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(theirAnswer, textAlign: TextAlign.center),

              // Self-facing only: §11.1 permits showing someone their own
              // past answer. Showing it to the guesser would turn recall
              // into a lookup and defeat the §8.4 hidden reveal.
              if (isSubject && previous != null) ...[
                const SizedBox(height: 24),
                Text('Six months ago you said', style: textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(previous, textAlign: TextAlign.center),
              ],

              if (onNext != null) ...[
                const SizedBox(height: 32),
                FilledButton(onPressed: onNext, child: const Text('Next')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
