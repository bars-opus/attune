import 'package:flutter/material.dart';

/// Asks the subject whether their partner read them accurately (§8.4).
///
/// Deliberately shows ONE round and nothing else: no counter, no
/// progress bar, no running tally. The subject produces every mark that
/// composes their partner's score, so a running total would hand them
/// that score outright — precisely what §11.1 forbids ("never shown as a
/// judgment of the partner"). RLS hides the stored score from them; this
/// screen must not give it back.
class MirrorJudgeScreen extends StatelessWidget {
  const MirrorJudgeScreen({
    super.key,
    required this.yourTruth,
    required this.theirGuess,
    required this.onJudge,
  });

  /// What the subject said about themselves.
  final String yourTruth;

  /// What their partner guessed.
  final String theirGuess;

  /// true = read accurately.
  final ValueChanged<bool> onJudge;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('You said', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(yourTruth, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text('They guessed', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(theirGuess, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          Text('Did they read you right?', style: textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => onJudge(false),
                child: const Text('Not quite'),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: () => onJudge(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
