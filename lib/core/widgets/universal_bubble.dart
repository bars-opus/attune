import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// The shared bubble shell behind both MessageBubble (1:1 chat) and
/// ForumPostBubble (debate room) — alignment, fill color, swipe gestures,
/// quoted-reply preview + tap-to-jump, and the jump highlight-flash all
/// used to be duplicated between the two features (ForumPostBubble's own
/// doc comment: "This mirrors MessageBubble in the 1:1 chat feature
/// exactly"). Extracted here so it exists once; each caller supplies its
/// own content, footer, colors, and swipe actions.
///
/// See docs/superpowers/specs/2026-08-12-chat-universal-bubble-reply-design.md.
class UniversalBubble extends StatelessWidget {
  const UniversalBubble({
    super.key,
    required this.isMine,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.content,
    required this.footer,
    this.leading,
    this.startActionPane,
    this.endActionPane,
    this.quotedText,
    this.onJumpToParent,
    this.isHighlighted = false,
    this.maxWidth = 320,
  });

  /// True puts the bubble on the right, false on the left.
  final bool isMine;

  /// Bubble fill color. Chat passes colorScheme.primary (mine) /
  /// surfaceContainerHighest (theirs); forums passes colorScheme.primary
  /// (mine) / onBackground (theirs) — each caller keeps its own existing
  /// pairing, this widget does not choose one.
  final Color bubbleColor;

  /// Color for content painted on top of [bubbleColor] (text, icons).
  final Color onBubbleColor;

  /// The bubble's main content — a Text for a forum post, a richer
  /// image+caption layout for a chat message with media.
  final Widget content;

  /// The row below the bubble, outside its fill — chat's time/status-chip
  /// row, or forum's time/like/reply/report/side-badge row.
  final Widget footer;

  /// Leading widget beside the bubble (forum's status avatar). Null means
  /// nothing renders there — chat has no per-message avatar today.
  final Widget? leading;

  /// Swipe-right-to-left action pane (e.g. Reply). Null disables that
  /// swipe direction entirely.
  final ActionPane? startActionPane;

  /// Swipe-left-to-right action pane (e.g. Report/Delete). Null disables
  /// that swipe direction entirely.
  final ActionPane? endActionPane;

  /// The quoted parent-message preview text, shown above [content] inside
  /// the bubble when this message/post IS a reply. Null means this isn't a
  /// reply — no quote block renders at all.
  final String? quotedText;

  /// Tapping the quote block calls this — the caller is responsible for
  /// scrolling to and highlighting the actual parent (see
  /// ChatScreen/DebateRoomScreen's own jump implementations). Null means
  /// the quote block renders without a tap affordance (e.g. inside a
  /// replies-only bottom sheet with no independent scroll position).
  final VoidCallback? onJumpToParent;

  /// True while this bubble is the current jump-to target — flashes a
  /// colored border ring that fades back out, so the eye lands on the
  /// right bubble after a jump.
  final bool isHighlighted;

  /// Max bubble width in logical pixels before content wraps.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // IntrinsicWidth: Slidable internally builds a Stack for its action
        // panes, which expands to fill whatever width it's handed
        // regardless of its child's own size — without this every bubble
        // renders full-width and Align's left/right positioning above is
        // silently defeated (see ForumPostBubble's identical comment on
        // this, which is where this fix was first discovered).
        child: IntrinsicWidth(
          child: Slidable(
            startActionPane: startActionPane,
            endActionPane: endActionPane,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 4)],
                Flexible(
                  child: Column(
                    crossAxisAlignment:
                        isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  isHighlighted
                                      ? bubbleColor
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (quotedText != null) ...[
                                    GestureDetector(
                                      onTap: onJumpToParent,
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: onBubbleColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.format_quote,
                                              size: 20,
                                              color: onBubbleColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                quotedText!,
                                                style: TextStyle(
                                                  color: onBubbleColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  content,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: footer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
