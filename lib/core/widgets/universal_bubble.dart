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
    this.highlightColor,
    this.maxWidth = 320,
    this.slidableKey,
    this.groupTag,
    this.onLongPress,
    this.quoteBackgroundColor,
    this.quoteForegroundColor,
    this.quoteTextStyle,
    this.quoteIconSize = 20,
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

  /// Color of the highlight-flash ring. Kept separate from [bubbleColor]
  /// because a ring drawn in the bubble's own fill color sits directly
  /// against that fill and is effectively invisible — forums passes a
  /// distinct for/against side color here; callers without one (chat's
  /// MessageBubble) can omit it and fall back to [bubbleColor].
  final Color? highlightColor;

  /// Max bubble width in logical pixels before content wraps.
  final double maxWidth;

  /// Forwarded to the inner [Slidable]'s `key` — needed so per-item
  /// slide-open/closed state stays attached to the right item when this
  /// widget is rendered in a rebuilt/reordered list (e.g. `ValueKey(id)`).
  /// Null is fine for a single bubble with no list identity to preserve.
  final Key? slidableKey;

  /// Forwarded to the inner [Slidable]'s `groupTag` — lets a caller ensure
  /// only one bubble in a group has its action pane open at a time.
  final Object? groupTag;

  /// Long-press handler on the bubble's fill (not the quote block, which
  /// has its own tap-to-jump gesture). Null (the default) means no
  /// long-press behavior — ForumPostBubble, this widget's other caller,
  /// does not pass this and must see zero behavior change.
  final VoidCallback? onLongPress;

  /// Quote-block fill color. Falls back to `onBubbleColor.withValues(alpha:
  /// 0.15)` (chat's look) when null. Forums passes
  /// `colorScheme.onBackground.withOpacity(0.5)` to preserve its
  /// pre-refactor appearance exactly.
  final Color? quoteBackgroundColor;

  /// Quote-block icon/fallback text color. Falls back to [onBubbleColor]
  /// when null. Forums passes `colorScheme.background` to preserve its
  /// pre-refactor appearance exactly.
  final Color? quoteForegroundColor;

  /// Quote-block text style. Falls back to a hardcoded
  /// `TextStyle(color: quoteForegroundColor, fontSize: 12)` (chat's look)
  /// when null. Forums passes `textTheme.bodySmall` (color-adjusted) to
  /// preserve its pre-refactor appearance exactly.
  final TextStyle? quoteTextStyle;

  /// Quote-block leading icon size. Defaults to 20 (chat's look). Forums
  /// passes `30.h` to preserve its pre-refactor appearance exactly.
  final double quoteIconSize;

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
            key: slidableKey,
            groupTag: groupTag,
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
                                      ? (highlightColor ?? bubbleColor)
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: GestureDetector(
                            onLongPress: onLongPress,
                            behavior: HitTestBehavior.opaque,
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
                                            color:
                                                quoteBackgroundColor ??
                                                onBubbleColor.withValues(
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
                                                size: quoteIconSize,
                                                color:
                                                    quoteForegroundColor ??
                                                    onBubbleColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  quotedText!,
                                                  style:
                                                      quoteTextStyle ??
                                                      TextStyle(
                                                        color:
                                                            quoteForegroundColor ??
                                                            onBubbleColor,
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
