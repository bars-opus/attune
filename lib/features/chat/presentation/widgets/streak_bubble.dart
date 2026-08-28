import 'package:flutter/material.dart';

/// A streak in the message list.
///
/// Deliberately plain: a play affordance and a word, nothing else. No
/// thumbnail, no caption, no clip count — the row must reveal nothing
/// about the content before it is opened, which is the whole point of a
/// view-once message. The caption lives in the viewer only.
class StreakBubble extends StatelessWidget {
  const StreakBubble({
    super.key,
    required this.viewsRemaining,
    required this.hasBeenPlayed,
    required this.onTap,
  });

  /// Views left for the recipient. 0 means spent.
  final int viewsRemaining;

  /// Whether this viewer has already watched it once.
  final bool hasBeenPlayed;

  final VoidCallback onTap;

  bool get _isSpent => viewsRemaining <= 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (_isSpent) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_outlined,
              size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Streak expired',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    // "Play" before the first watch, "Tap to play" after — the second
    // wording signals that it is still available rather than already used
    // up, which is the question a recipient actually has once they have
    // seen it once.
    final label = hasBeenPlayed ? 'Tap to play' : 'Play';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 22, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(label, style: textTheme.bodyMedium),
            // Only meaningful once replays exist AND one has been used;
            // showing "1 left" on an unwatched view-once streak would be
            // noise.
            if (hasBeenPlayed && viewsRemaining > 0) ...[
              const SizedBox(width: 8),
              Text(
                '$viewsRemaining left',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
