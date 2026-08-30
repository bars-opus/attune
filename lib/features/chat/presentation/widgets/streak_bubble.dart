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
    this.isMine = false,
    this.openedByRecipient = false,
    this.isSending = false,
  });

  /// Views left for the recipient. 0 means spent.
  final int viewsRemaining;

  /// Whether this viewer has already watched it once.
  final bool hasBeenPlayed;

  final VoidCallback onTap;

  /// Whether the viewer sent this streak.
  final bool isMine;

  /// Still uploading. The upload now happens behind this bubble rather
  /// than on the camera screen, so this is where the user watches it.
  final bool isSending;

  /// Whether the recipient has opened it. Only meaningful to the sender:
  /// it is what ends their replay window, and their only read receipt.
  final bool openedByRecipient;

  /// The sender is done the moment the recipient opens it. Until then
  /// they may replay freely — the streak is still in flight, and
  /// re-watching what you sent costs the recipient nothing.
  bool get _senderLockedOut => isMine && openedByRecipient;

  /// The recipient's budget never governs the sender: an unopened streak
  /// stays playable for them regardless of how many views it carries.
  bool get _isSpent => _senderLockedOut || (!isMine && viewsRemaining <= 0);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (isSending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),
          ),
          const SizedBox(width: 8),
          Text('Sending…', style: textTheme.bodyMedium),
        ],
      );
    }

    if (_isSpent) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One glyph and one word for both parties. The recipient used to
          // see a struck-out camera and "Streak expired", which describes
          // time running out rather than the streak having been watched —
          // and left the two sides of the same conversation disagreeing
          // about what had happened.
          Icon(
            Icons.drafts_outlined,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            // The only read receipt a streak gives, and now the same
            // word the recipient sees.
            'Opened',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    // The remaining count lives IN the label — "Play 3x", "Play 2x", then
    // plain "Play" on the last one — rather than in a separate chip beside
    // it, so one glance answers both "can I play this" and "how many
    // times". A count on the final view would be noise: "Play 1x" and
    // "Play" say the same thing.
    //
    // The sender never sees a count: the budget is the recipient's, and
    // reporting their viewing back would be a different feature.
    final showCount = !isMine && viewsRemaining > 1;
    final label = showCount ? 'Play ${viewsRemaining}x' : 'Play';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(label, style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
