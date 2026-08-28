import 'package:flutter/material.dart';

/// The Love Map entry point in the games hub.
///
/// Shows coverage — how much of the map the couple has filled — and never
/// accuracy. §11.1: a running "you read them 62%" would be a score, and
/// would show one partner a number the other produced.
class LoveMapCard extends StatelessWidget {
  const LoveMapCard({
    super.key,
    required this.answered,
    required this.total,
    required this.newCount,
    required this.onTap,
  });

  final int answered;
  final int total;
  final int newCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // A bank that has not loaded yet (or an empty one) must not divide by
    // zero; an empty bar is the honest rendering.
    final progress = total > 0 ? (answered / total).clamp(0.0, 1.0) : 0.0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Love Map',
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (newCount > 0)
                  Text('$newCount new', style: textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text('You know $answered of $total answers',
                style: textTheme.bodySmall),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
          ],
        ),
      ),
    );
  }
}
