import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestEntry, BoxHitTestResult, RenderProxyBox;

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
    this.isFailed = false,
    this.isExpired = false,
    this.onRetry,
    this.foregroundColor,
    this.metadataColor,
    this.accentColor,
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

  /// The upload gave up (automatic attempts exhausted). Wins over
  /// [isSending]: a failed row still carries its optimistic id.
  final bool isFailed;

  /// Destroyed before anyone saw it: the recipient's read started the
  /// replay window, nothing was ever presented, and the sweep spent the
  /// budget when the window closed (budget 0 with no viewed_at). Both
  /// parties read "Expired" and neither may open it — "Opened" would be a
  /// false receipt, and "Play" would open an empty viewer forever.
  final bool isExpired;

  /// Tapping the failed state retries; null renders it inert.
  final VoidCallback? onRetry;

  /// Whether the recipient has opened it. Only meaningful to the sender:
  /// it is what ends their replay window, and their only read receipt.
  final bool openedByRecipient;
  final Color? foregroundColor;
  final Color? metadataColor;
  final Color? accentColor;

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
    final foreground = foregroundColor ?? colorScheme.onSurface;
    final metadata = metadataColor ?? colorScheme.onSurfaceVariant;
    final accent = accentColor ?? colorScheme.primary;

    if (isFailed) {
      // Plain words and the error colour, never a spinner: "Failed" in the
      // UI means "will not send without you" (CHAT_SYSTEM_SPEC §3.3).
      final errorColor = colorScheme.error;
      final canRetry = onRetry != null;
      return _MinHitTarget(
        minHeight: 44,
        child: Semantics(
          // Its own node, so the statement is not folded into the row's.
          container: true,
          button: canRetry,
          label: 'Streak not sent',
          onTap: onRetry,
          onTapHint: canRetry ? 'Retry' : null,
          excludeSemantics: true,
          child: InkWell(
            onTap: onRetry,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: errorColor,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      canRetry ? 'Not sent. Tap to retry' : 'Not sent',
                      style: textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (isSending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Sending…',
            style: textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    if (isExpired) {
      return Semantics(
        container: true,
        label: 'Streak expired',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off_outlined, size: 18, color: metadata),
            const SizedBox(width: 6),
            Text(
              'Expired',
              style: textTheme.bodyMedium?.copyWith(color: metadata),
            ),
          ],
        ),
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
            Icons.check_box_outline_blank_rounded,
            size: 18,
            color: metadata,
          ),
          const SizedBox(width: 6),
          Text(
            // The only read receipt a streak gives, and now the same
            // word the recipient sees.
            'Opened',
            style: textTheme.bodyMedium?.copyWith(color: metadata),
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

    // Three states, three glyphs: play it for the first time, play it
    // again, or (above) it is spent. hasBeenPlayed alone is the divider —
    // a watched streak with views left is a REPLAY, which is a different
    // offer from a first watch.
    //
    // Green marks the bonus views the sender opted into, distinct from
    // the theme accent an ordinary first play uses. Fixed rather than
    // colorScheme.tertiary, which carries no green guarantee.
    final isReplay = !isMine && hasBeenPlayed;
    const replayGreen = Color(0xFF2E9E5B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (isReplay ? replayGreen : accent).withValues(
                  alpha: 0.14,
                ),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                isReplay ? Icons.replay_rounded : Icons.play_arrow_rounded,
                size: 24,
                color: isReplay ? replayGreen : accent,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widens a small control's hit area to [minHeight] without growing its
/// layout (same approach as the message footer's wider hit target): the
/// position is clamped into the child so its own handlers fire. Reach is
/// bounded by the ancestors' boxes.
class _MinHitTarget extends SingleChildRenderObjectWidget {
  const _MinHitTarget({required this.minHeight, required super.child});

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinHitTarget(minHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMinHitTarget renderObject,
  ) {
    renderObject.minHeight = minHeight;
  }
}

class _RenderMinHitTarget extends RenderProxyBox {
  _RenderMinHitTarget(this.minHeight);

  double minHeight;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final box = child;
    if (box == null) return super.hitTest(result, position: position);
    final slop = size.height < minHeight ? (minHeight - size.height) / 2 : 0.0;
    if (position.dx < 0 ||
        position.dx >= size.width ||
        position.dy < -slop ||
        position.dy >= size.height + slop) {
      return false;
    }
    final clamped = Offset(
      position.dx,
      position.dy.clamp(0.0, size.height > 0.01 ? size.height - 0.01 : 0.0),
    );
    final hit = box.hitTest(result, position: clamped);
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }
}
