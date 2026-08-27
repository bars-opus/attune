import 'package:flutter/material.dart';

/// Closes a completed session.
///
/// [yourScore] is populated for Mirror only, and is the VIEWER'S OWN
/// score. §11.1 makes it self-facing: this screen must never receive or
/// render the partner's score, and there is deliberately no parameter
/// for it. mirror_scores' RLS (USING user_id = auth.uid()) means a
/// caller could not fetch one even if this screen asked.
class SessionGameEndScreen extends StatelessWidget {
  const SessionGameEndScreen({
    super.key,
    required this.onDone,
    this.yourScore,
    this.totalRounds,
  });

  final VoidCallback onDone;
  final int? yourScore;
  final int? totalRounds;

  @override
  Widget build(BuildContext context) {
    final score = yourScore;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('That is the end', style: Theme.of(context).textTheme.titleLarge),
          if (score != null && totalRounds != null) ...[
            const SizedBox(height: 24),
            // Framed as the viewer's own reading of their partner, never
            // as a verdict on either person (§11.1, and §8.4's "no
            // diagnosis language").
            Text('You read them $score of $totalRounds times'),
          ],
          const SizedBox(height: 40),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}
