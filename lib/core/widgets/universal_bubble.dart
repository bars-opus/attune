import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_slidable/flutter_slidable.dart';

/// The shared bubble shell behind both MessageBubble (1:1 chat) and
/// ForumPostBubble (debate room) — alignment, fill color, swipe gestures,
/// quoted-reply preview + tap-to-jump, and the jump highlight-flash all
/// used to be duplicated between the two features (ForumPostBubble's own
/// doc comment: "This mirrors MessageBubble in the 1:1 chat feature
/// exactly"). Extracted here so it exists once; each caller supplies its
/// own content, footer, colors, and swipe actions.
///
/// See docs/superpowers/specs/2026-08-12-chat-universal-bubble-reply-design.md
/// and docs/superpowers/specs/2026-08-14-custom-swipe-to-reply-design.md.
class UniversalBubble extends StatefulWidget {
  const UniversalBubble({
    super.key,
    required this.isMine,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.content,
    required this.footer,
    this.leading,
    this.onReply,
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

  /// Swipe-right-to-left-to-reply target. Null disables the reply swipe
  /// gesture entirely (e.g. a read-only/archived conversation has nothing
  /// sensible to reply into). Fires immediately on release once the drag
  /// has passed the fire threshold — no separate tap required, matching
  /// WhatsApp's swipe-to-reply.
  final VoidCallback? onReply;

  /// Swipe-left-to-right action pane (e.g. Report/Delete). Null disables
  /// that swipe direction entirely. Still flutter_slidable-backed as of
  /// this task — Task 2 replaces it with the custom endActions pane.
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
  State<UniversalBubble> createState() => _UniversalBubbleState();
}

class _UniversalBubbleState extends State<UniversalBubble>
    with SingleTickerProviderStateMixin {
  static const double _fireThreshold = 60;
  static const double _maxDrag = 75;
  static const Duration _springBackDuration = Duration(milliseconds: 200);

  /// Created eagerly in [initState], NOT via a `late final` initializer: a
  /// lazily-created controller whose first touch is [dispose] would call
  /// `createTicker` on an already-deactivated element, and
  /// `SingleTickerProviderStateMixin` does an inherited-widget (TickerMode)
  /// lookup there — which throws "Looking up a deactivated widget's
  /// ancestor is unsafe" for every bubble that is never dragged.
  late final AnimationController _springController;
  Animation<double>? _springAnimation;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: _springBackDuration,
    );
  }

  /// Current horizontal drag offset in logical pixels. Negative = dragged
  /// left (reply direction). 0 at rest. Rubber-banded to _maxDrag once the
  /// raw drag exceeds _fireThreshold.
  double _dragOffset = 0;
  bool _hapticFired = false;

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (widget.onReply == null) return;
    _springController.stop();
    _hapticFired = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.onReply == null) return;
    final rawOffset = _dragOffset + details.delta.dx;
    // Only leftward (negative) drag matters for reply in this task —
    // clamp at 0 so a rightward drag has no visual effect (Task 2 adds
    // rightward behavior for endActions).
    final clamped = rawOffset > 0 ? 0.0 : rawOffset;
    final magnitude = clamped.abs();
    setState(() {
      if (magnitude <= _fireThreshold) {
        _dragOffset = clamped;
      } else {
        // Rubber-band: linearly compress the excess past the threshold
        // into the remaining (_maxDrag - _fireThreshold) budget.
        final excess = magnitude - _fireThreshold;
        final compressed =
            _fireThreshold +
            (excess / (excess + 40)) * (_maxDrag - _fireThreshold);
        _dragOffset = -compressed;
      }
    });
    if (!_hapticFired && _dragOffset.abs() >= _fireThreshold) {
      _hapticFired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.onReply == null) return;
    final shouldFire = _dragOffset.abs() >= _fireThreshold;
    _animateSpringBack();
    if (shouldFire) {
      widget.onReply!();
    }
  }

  void _animateSpringBack() {
    final start = _dragOffset;
    _springAnimation = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOut),
    )..addListener(() {
      setState(() => _dragOffset = _springAnimation!.value);
    });
    _springController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: GestureDetector(
          onHorizontalDragStart:
              widget.onReply == null ? null : _onHorizontalDragStart,
          onHorizontalDragUpdate:
              widget.onReply == null ? null : _onHorizontalDragUpdate,
          onHorizontalDragEnd:
              widget.onReply == null ? null : _onHorizontalDragEnd,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              if (_dragOffset < 0)
                Positioned(
                  right: 0,
                  child: Opacity(
                    opacity: (_dragOffset.abs() / _fireThreshold).clamp(
                      0.0,
                      1.0,
                    ),
                    child: Transform.scale(
                      scale:
                          0.7 +
                          0.3 *
                              (_dragOffset.abs() / _fireThreshold).clamp(
                                0.0,
                                1.0,
                              ),
                      child: Icon(
                        Icons.reply,
                        color:
                            widget.isMine
                                ? widget.bubbleColor
                                : widget.onBubbleColor,
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(_dragOffset, 0),
                // IntrinsicWidth: Slidable internally builds a Stack for its
                // action panes, which expands to fill whatever width it's
                // handed regardless of its child's own size — without this
                // every bubble renders full-width and Align's left/right
                // positioning above is silently defeated.
                child: IntrinsicWidth(
                  child: Slidable(
                    key: widget.slidableKey,
                    groupTag: widget.groupTag,
                    // Slidable installs ONE HorizontalDragGestureRecognizer
                    // for the whole widget whenever `enabled` is true — gated
                    // on that flag alone, NOT on whether the pane for a given
                    // direction is null (see flutter_slidable 4.0.3's
                    // gesture_detector.dart: `canDragHorizontally =
                    // directionIsXAxis && widget.enabled`). Left enabled it
                    // wins the arena over the outer reply recognizer above —
                    // two same-type recognizers on identical bounds — and the
                    // reply swipe never fires at all. Disabling it when there
                    // is no end pane hands the whole horizontal axis to the
                    // custom gesture. Chat never sets endActionPane, so chat
                    // gets the reply swipe; forums still sets it, so its
                    // Report/Delete pane keeps working exactly as today until
                    // Task 2 replaces this Slidable outright.
                    enabled: widget.endActionPane != null,
                    startActionPane: null,
                    endActionPane: widget.endActionPane,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.leading != null) ...[
                          widget.leading!,
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment:
                                widget.isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: widget.maxWidth,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOut,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color:
                                          widget.isHighlighted
                                              ? (widget.highlightColor ??
                                                  widget.bubbleColor)
                                              : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: GestureDetector(
                                    onLongPress: widget.onLongPress,
                                    behavior: HitTestBehavior.opaque,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: widget.bubbleColor,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (widget.quotedText != null) ...[
                                              GestureDetector(
                                                onTap: widget.onJumpToParent,
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        widget.quoteBackgroundColor ??
                                                        widget.onBubbleColor
                                                            .withValues(
                                                              alpha: 0.15,
                                                            ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.format_quote,
                                                        size:
                                                            widget
                                                                .quoteIconSize,
                                                        color:
                                                            widget.quoteForegroundColor ??
                                                            widget
                                                                .onBubbleColor,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Flexible(
                                                        child: Text(
                                                          widget.quotedText!,
                                                          style:
                                                              widget.quoteTextStyle ??
                                                              TextStyle(
                                                                color:
                                                                    widget.quoteForegroundColor ??
                                                                    widget
                                                                        .onBubbleColor,
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
                                            widget.content,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: widget.maxWidth,
                                ),
                                child: widget.footer,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
