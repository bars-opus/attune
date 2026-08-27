import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Which direction the in-flight horizontal drag committed to. Locked once
/// per gesture at the first update with non-trivial movement, then every
/// later update in that same gesture routes through it — a per-event sign
/// check on `details.delta.dx` is NOT safe, since a real drag isn't
/// monotonic and one frame of jitter the other way (common right at the
/// start, before the gesture has committed) would misroute that frame.
enum _DragMode { reply, endPane }

/// Replaces flutter_slidable's groupTag "close my siblings" mechanism.
/// One registry entry per active groupTag; each open UniversalBubble
/// registers a close callback under its tag, overwriting any prior
/// registrant — opening a new bubble in the same group therefore only
/// needs to invoke whatever callback was registered before it, then
/// register its own. Scoped to process lifetime (a static field), which
/// is fine here since the only state is "how do I close myself," not
/// anything that needs disposal beyond what each bubble's own dispose()
/// already does (removing its registration).
class _EndPaneGroupRegistry {
  static final Map<Object, VoidCallback> _openCallbacks = {};

  static void notifyOpening(Object groupTag, VoidCallback closeSelf) {
    final previous = _openCallbacks[groupTag];
    if (previous != null && previous != closeSelf) {
      previous();
    }
    _openCallbacks[groupTag] = closeSelf;
  }

  static void notifyClosed(Object groupTag, VoidCallback closeSelf) {
    if (_openCallbacks[groupTag] == closeSelf) {
      _openCallbacks.remove(groupTag);
    }
  }
}

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
    this.endActions,
    this.quotedText,
    this.onJumpToParent,
    this.isHighlighted = false,
    this.replyIconColor,
    this.highlightColor,
    this.maxWidth = 320,
    this.bubbleKey,
    this.groupTag,
    this.onLongPress,
    this.quoteBackgroundColor,
    this.quoteForegroundColor,
    this.quoteTextStyle,
    this.quoteIconSize = 20,
    this.quoteAuthorLabel,
    this.quoteAuthorIsMine,
    this.quoteMineBorderColor,
    this.quotePartnerBorderColor,
    this.showShadow = false,
    this.showCardBorder = false,
    this.verticalPadding = 4,
    this.bubbleBorderRadius = 18,
    this.bubbleBorderRadiusOverride,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 10,
    ),
    this.bubbleGradient,
    this.startReveal,
    this.endReveal,
    this.dragOffsetOverride,
    this.onEndRevealDragChanged,
    this.footerSpacing = 4,
    this.showFooter = true,
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

  /// Widgets revealed by a left-to-right drag (e.g. Report/Delete buttons).
  /// Null disables that swipe direction entirely. Stays open once past the
  /// reveal threshold until a revealed action is tapped, the bubble is
  /// dragged back closed, or another bubble sharing [groupTag] opens.
  final List<Widget>? endActions;

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

  /// Color of the reply icon revealed during a reply-direction drag. Falls
  /// back to `isMine ? bubbleColor : onBubbleColor` when null — chat's
  /// look. Forums passes its for/against sideColor to match the design
  /// spec's "Reply icon reveal" requirement.
  final Color? replyIconColor;

  /// Color of the highlight-flash ring. Kept separate from [bubbleColor]
  /// because a ring drawn in the bubble's own fill color sits directly
  /// against that fill and is effectively invisible — forums passes a
  /// distinct for/against side color here; callers without one (chat's
  /// MessageBubble) can omit it and fall back to [bubbleColor].
  final Color? highlightColor;

  /// Max bubble width in logical pixels before content wraps.
  final double maxWidth;

  /// Key on the bubble's own row — needed so per-item drag/open state stays
  /// attached to the right item when this widget is rendered in a
  /// rebuilt/reordered list (e.g. `ValueKey(id)`). Null is fine for a
  /// single bubble with no list identity to preserve.
  final Key? bubbleKey;

  /// Groups bubbles so only one in the group has its [endActions] pane open
  /// at a time — opening one closes any sibling sharing this tag.
  final Object? groupTag;

  /// Long-press handler on the bubble's fill (not the quote block, which
  /// has its own tap-to-jump gesture). Receives the bubble's captured
  /// on-screen Rect and a duplicate of its visual content, for a caller
  /// to render into a focused-menu overlay (see
  /// docs/superpowers/specs/2026-08-14-focused-message-menu-design.md).
  /// Null (the default) means no long-press behavior — ForumPostBubble,
  /// this widget's other caller, does not pass this and must see zero
  /// behavior change.
  final void Function(Rect bubbleRect, Widget bubbleSnapshot)? onLongPress;

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

  /// Optional label shown above the quoted text (e.g. "You" / a partner's
  /// name) — who the quoted/replied-to message originally belonged to.
  /// Null (the default) renders no label, preserving ForumPostBubble's
  /// exact prior appearance; MessageBubble passes this to identify whose
  /// message is being replied to.
  final String? quoteAuthorLabel;

  /// Who the quoted/replied-to message ORIGINALLY belonged to — true for
  /// your own earlier message, false for your partner's, null when the
  /// parent isn't loaded (so genuinely unknown, not guessed). Drives the
  /// COLOR of a side bar on the quote block ([quoteMineBorderColor] when
  /// true, [quotePartnerBorderColor] when false); the bar's SIDE instead
  /// follows [isMine] — this bubble's own screen alignment — so a
  /// partner's bubble always gets a left-side bar regardless of who's
  /// quoted inside it, just tinted differently. Null (the default) renders
  /// no side bar at all, preserving ForumPostBubble's exact prior
  /// appearance.
  final bool? quoteAuthorIsMine;

  /// Side-border color when [quoteAuthorIsMine] is true. Defaults to
  /// colorScheme.error (chat's "red for you" look) when null.
  final Color? quoteMineBorderColor;

  /// Side-border color when [quoteAuthorIsMine] is false. Defaults to
  /// colorScheme.primary (chat's "primary for partner" look) when null.
  final Color? quotePartnerBorderColor;

  /// Adds a slight drop shadow to the bubble fill. Defaults to false so
  /// ForumPostBubble (this widget's other caller) sees zero visual change —
  /// MessageBubble opts in to match the composer's own floating-shadow look.
  final bool showShadow;

  /// Draws a subtle 1px outline around the bubble fill, matching
  /// CardInkWell's own border look (colorScheme.outline at 10% opacity,
  /// hairline width) — the shared "card" visual language used elsewhere in
  /// the app. Defaults to false so ForumPostBubble sees zero visual
  /// change; MessageBubble opts in. A real Card/InkWell isn't used
  /// directly here since the bubble fill already carries its own
  /// swipe-to-reply, swipe-to-reveal-actions, and long-press gestures —
  /// wrapping it in InkWell would conflict with that GestureDetector
  /// stack, so only the border/radius LOOK is borrowed, not the widget.
  final bool showCardBorder;

  /// Vertical space above and below the whole bubble row (outside the
  /// fill), i.e. half the gap between two consecutive bubbles. Defaults to
  /// 4 (the original fixed value, unconditionally used before this
  /// parameter existed) so ForumPostBubble sees zero visual change.
  /// MessageBubble passes a smaller value (0) for consecutive same-sender
  /// messages so a grouped run of bubbles sits close together, like
  /// WhatsApp/iMessage — the per-item Padding chat_screen.dart's list adds
  /// between items only controls the gap on ONE side of each bubble; this
  /// controls the bubble's own built-in gap on the OTHER side, which stays
  /// fixed at 4 regardless of grouping unless this is also threaded
  /// through, otherwise "no padding between them" is only half true (4px
  /// of this widget's own padding remains even when the list item's own
  /// extra gap is removed).
  final double verticalPadding;

  /// Corner radius for the filled bubble surface. MessageBubble overrides
  /// this for Instagram-style pills; other callers keep the prior 18px look.
  final double bubbleBorderRadius;

  /// Optional per-corner radius for grouped message runs. When omitted the
  /// bubble uses [bubbleBorderRadius] on every corner.
  final BorderRadius? bubbleBorderRadiusOverride;

  /// Padding inside the filled bubble surface. Kept configurable so chat can
  /// move toward a denser messaging pill without changing forum bubbles.
  final EdgeInsetsGeometry contentPadding;

  /// Optional fill gradient for callers that need richer bubble surfaces.
  /// Defaults to null so existing uses keep their solid [bubbleColor].
  final Gradient? bubbleGradient;

  /// Widget revealed behind the bubble during a rightward drag. Null keeps
  /// the original reply-icon reveal.
  final Widget? startReveal;

  /// Widget revealed behind the bubble during a leftward drag. Chat uses
  /// this for iMessage-style timestamps; null keeps the existing action pane.
  final Widget? endReveal;

  /// Paint/layout offset controlled by a parent. Used by ChatScreen so one
  /// leftward drag can reveal timestamps for every visible message together.
  final double? dragOffsetOverride;

  /// Called with the absolute leftward reveal amount while dragging left.
  final ValueChanged<double>? onEndRevealDragChanged;

  /// Vertical gap between the filled bubble and footer. Chat sets this to
  /// zero when no visible footer is present.
  final double footerSpacing;

  /// Whether to lay out [footer] at all. A zero-sized footer widget can still
  /// interact with column spacing and parent measurement, so chat turns the
  /// whole footer block off when no metadata should be visible.
  final bool showFooter;

  @override
  State<UniversalBubble> createState() => _UniversalBubbleState();
}

class _UniversalBubbleState extends State<UniversalBubble>
    with SingleTickerProviderStateMixin {
  static const double _fireThreshold = 60;
  static const double _maxDrag = 75;
  static const double _timestampRevealLimit = 112;
  static const double _timestampRevealDragGain = 1;
  static const Duration _springBackDuration = Duration(milliseconds: 200);

  /// Matches the old ActionPane's extentRatio: 0.25.
  static const double _endPaneRevealRatio = 0.25;

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

  /// Current horizontal drag offset in logical pixels. Positive = dragged
  /// right (reply direction), negative = dragged left (end pane). 0 at
  /// rest. Rubber-banded to _maxDrag once a rightward drag exceeds
  /// _fireThreshold; clamped to the reveal width leftward.
  double _dragOffset = 0;
  bool _hapticFired = false;

  /// True while the end pane is held open at its full reveal width.
  bool _endPaneOpen = false;

  /// Whether the current gesture began with the end pane already open —
  /// captured in [_onHorizontalDragStart] before [_endPaneOpen] is cleared,
  /// and read once by [_onHorizontalDragUpdate] to seed [_activeDragMode].
  bool _startedFromOpenEndPane = false;

  /// The direction this gesture committed to, locked at the first
  /// meaningful update. Null between gestures.
  _DragMode? _activeDragMode;

  /// The reveal width measured at the start of the current gesture, kept so
  /// build() can lay the pane out without touching `context.size` — reading
  /// a render object's size during build asserts ("Cannot get size during
  /// build"), and it is only legal from paint callbacks and interaction
  /// event handlers, which is exactly where [_measureEndPaneRevealWidth]
  /// runs. Seeded with the same fallback used before first layout.
  double _endPaneRevealWidth = 200 * _endPaneRevealRatio;

  /// Measures the bubble row itself, not this State's own context: the
  /// State's render object is the full-width Align, so measuring it would
  /// scale the reveal to the screen rather than to the bubble the way the
  /// old ActionPane's extentRatio: 0.25 did.
  final GlobalKey _bubbleRowKey = GlobalKey();

  /// Color for the quote side bar AND its author label — red when the
  /// quoted message is yours, primary (or the caller's override) when it's
  /// your partner's. Shared by [_quoteWithSideBar] and both quote blocks'
  /// author-label Text so the label always matches the bar beside it.
  Color _quoteSideBarColor(BuildContext context, bool quoteAuthorIsMine) {
    final colorScheme = Theme.of(context).colorScheme;
    return quoteAuthorIsMine
        ? (widget.quoteMineBorderColor ?? colorScheme.error)
        : (widget.quotePartnerBorderColor ?? colorScheme.primary);
  }

  BorderRadius get _bubbleBorderRadius =>
      widget.bubbleBorderRadiusOverride ??
      BorderRadius.circular(widget.bubbleBorderRadius);

  /// The quote-mark icon, mirrored horizontally on your own bubble so it
  /// visually "faces" the text column beside it — Icons.format_quote only
  /// ships as a left-facing glyph, and on the mine side (icon leading,
  /// text trailing) an unflipped icon reads backwards.
  Widget _quoteIcon() {
    final icon = Icon(
      Icons.format_quote,
      size: widget.quoteIconSize,
      color: widget.quoteForegroundColor ?? widget.onBubbleColor,
    );
    if (!widget.isMine) return icon;
    return Transform.flip(flipX: true, child: icon);
  }

  /// Quote block's own corner radius, squared off on whichever side the
  /// side bar sits (see [_quoteWithSideBar]) so the bar reads as directly
  /// attached to the block instead of a rounded block floating next to a
  /// rounded bar. Only squares when a bar is actually rendered
  /// ([widget.quoteAuthorIsMine] non-null) — with no bar, all 4 corners
  /// stay rounded exactly as before.
  BorderRadius _quoteBlockRadius() {
    const radius = Radius.circular(8);
    if (widget.quoteAuthorIsMine == null) return BorderRadius.circular(8);
    return widget.isMine
        ? const BorderRadius.only(topLeft: radius, bottomLeft: radius)
        : const BorderRadius.only(topRight: radius, bottomRight: radius);
  }

  /// Wraps [quoteBlock] with a WhatsApp-style colored side bar. The SIDE
  /// follows [widget.isMine] — this bubble's own screen alignment: right
  /// for your own bubbles, left for your partner's. The COLOR follows
  /// [quoteAuthorIsMine] — who originally wrote the quoted text: red if
  /// you're being quoted, primary if your partner is. These are
  /// deliberately independent: a partner's bubble (left side) quoting
  /// YOUR message still gets a left-side bar, just in red — the bar always
  /// sits on this bubble's own side, only its color changes.
  ///
  /// Returns [quoteBlock] unchanged when quoteAuthorIsMine is null
  /// (ForumPostBubble, which never sets it, sees zero visual change).
  ///
  /// A real solid Container bar in a Row, not BoxDecoration's `border:` —
  /// a single-side Border combined with a rounded borderRadius on the same
  /// decoration is unreliable in Flutter (one side silently failed to
  /// paint in practice here), where a plain colored widget always renders.
  Widget _quoteWithSideBar(BuildContext context, Widget quoteBlock) {
    final quoteAuthorIsMine = widget.quoteAuthorIsMine;
    if (quoteAuthorIsMine == null) return quoteBlock;
    final color = _quoteSideBarColor(context, quoteAuthorIsMine);
    // Rounded on the outer edge only; the inner edge (against quoteBlock)
    // stays square. quoteBlock's own touching corners are squared off too
    // (see _quoteBlockRadius) so the two pieces meet as one continuous
    // shape, the bar reading as directly attached to the block rather than
    // a rounded rectangle floating next to another rounded rectangle.
    const radius = Radius.circular(8);
    final bar = Container(
      width: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius:
            widget.isMine
                ? const BorderRadius.only(topRight: radius, bottomRight: radius)
                : const BorderRadius.only(topLeft: radius, bottomLeft: radius),
      ),
    );
    // IntrinsicHeight (not CrossAxisAlignment.stretch, which demands
    // infinite height from an unbounded parent like the Column above this)
    // lets the bar match quoteBlock's own natural height without either
    // side needing bounded constraints from outside.
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:
            widget.isMine
                ? [Flexible(child: quoteBlock), bar]
                : [bar, Flexible(child: quoteBlock)],
      ),
    );
  }

  /// Measures the revealed actions' own intrinsic width, so the reveal
  /// never collapses narrower than what the actions themselves need to be
  /// tappable — a short bubble's 25%-of-width reveal can otherwise be
  /// smaller than a single IconButton's 48px minimum tap target, making
  /// Report/Delete physically untappable on short posts.
  final GlobalKey _endActionsRowKey = GlobalKey();

  /// Keys the actual bubble-fill DecoratedBox (not the outer Row/Padding
  /// wrappers) so onLongPress can read its exact on-screen Rect at the
  /// moment of a long-press — safe to call here specifically because
  /// onLongPress only fires after the widget has already been laid out
  /// and painted at least once, unlike the reveal-width measurement
  /// elsewhere in this file, which has to avoid reading size during
  /// build().
  final GlobalKey _bubbleFillKey = GlobalKey();

  void _handleLongPress() {
    final onLongPress = widget.onLongPress;
    if (onLongPress == null) return;
    final renderBox =
        _bubbleFillKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;
    final rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    // Reconstructs the SAME visual bubble fill — same decoration, same
    // padding, same quote block, same content — as a fresh widget subtree
    // to paint into the overlay, rather than an async
    // RepaintBoundary.toImage() capture (avoids the pixel-ratio/async
    // round-trip that would introduce for a menu that needs to open
    // instantly).
    //
    // The quote block has to be reproduced here, not just widget.content:
    // `rect` above is the real bubble fill's on-screen rectangle, whose
    // height already includes the quote block whenever quotedText != null.
    // A snapshot of content alone would paint shorter than the rect it is
    // given, leaving visible empty space under a reply's bubble in the
    // overlay. Kept in sync with the quote block in build() below — same
    // padding, same decoration fallback chain, same icon and text styling
    // — since any divergence moves the visual bug rather than fixing it.
    // The one deliberate difference: the real block is a GestureDetector
    // wired to onJumpToParent, while this static copy is wrapped in
    // IgnorePointer so tapping the overlay's quote does nothing.
    final snapshot = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.bubbleColor,
        gradient: widget.bubbleGradient,
        borderRadius: _bubbleBorderRadius,
      ),
      child: Padding(
        padding: widget.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.quotedText != null) ...[
              _quoteWithSideBar(
                context,
                IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color:
                          widget.quoteBackgroundColor ??
                          widget.onBubbleColor.withValues(alpha: 0.15),
                      borderRadius: _quoteBlockRadius(),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      // Icon sits at the container's OPPOSITE outer edge
                      // from the side bar/author label: leading (before the
                      // text column) for your own bubble (bar+label on the
                      // right), trailing for the partner's (bar+label on
                      // the left) — icon and text column pinned to
                      // opposite ends of the row.
                      children: [
                        if (widget.isMine) ...[
                          _quoteIcon(),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.quoteAuthorLabel != null)
                                Align(
                                  alignment:
                                      widget.isMine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                  child: Text(
                                    widget.quoteAuthorLabel!,
                                    style: (widget.quoteTextStyle ??
                                            TextStyle(
                                              color:
                                                  widget.quoteForegroundColor ??
                                                  widget.onBubbleColor,
                                              fontSize: 12,
                                            ))
                                        .copyWith(
                                          color:
                                              widget.quoteAuthorIsMine == null
                                                  ? null
                                                  : _quoteSideBarColor(
                                                    context,
                                                    widget.quoteAuthorIsMine!,
                                                  ),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              Text(
                                widget.quotedText!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    widget.quoteTextStyle ??
                                    TextStyle(
                                      color:
                                          widget.quoteForegroundColor ??
                                          widget.onBubbleColor,
                                      fontSize: 12,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (!widget.isMine) ...[
                          const SizedBox(width: 4),
                          _quoteIcon(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            widget.content,
          ],
        ),
      ),
    );
    onLongPress(rect, snapshot);
  }

  /// A quarter of the bubble's own rendered width (matching the old
  /// ActionPane's extentRatio: 0.25), floored at the actions' own measured
  /// width so they always fit. Safe to call from gesture handlers only —
  /// reading a render object's size during build asserts.
  void _measureEndPaneRevealWidth() {
    final bubbleWidth = _bubbleRowKey.currentContext?.size?.width;
    final actionsWidth = _endActionsRowKey.currentContext?.size?.width;
    if (bubbleWidth == null || bubbleWidth <= 0) return;
    final proportional = bubbleWidth * _endPaneRevealRatio;
    _endPaneRevealWidth =
        (actionsWidth != null && actionsWidth > proportional)
            ? actionsWidth
            : proportional;
  }

  /// Extra layout width reserved to the left of the bubble so the Stack —
  /// and with it the outer GestureDetector's hit-test rectangle — still
  /// contains the bubble once the end pane translates it left. See the
  /// build() comment at the Padding that consumes this.
  ///
  /// Tracks the live reveal width (which _measureEndPaneRevealWidth updates
  /// per gesture) rather than a constant, so the reserve is exactly the
  /// bubble's maximum possible leftward travel and never more.
  ///
  /// Gated on `_dragOffset < 0`, NOT on `endActions != null`: the reserve is
  /// real layout width, so applying it whenever endActions exists permanently
  /// narrowed and shifted every forums bubble AT REST — and because
  /// _endPaneRevealWidth is only measured on the first gesture, that resting
  /// geometry silently jumped the first time a bubble was ever touched.
  /// `_dragOffset < 0` is exactly the "reserve is needed" condition:
  ///  - At rest with the pane closed it is 0, so the bubble lays out at its
  ///    natural width, as it did before this feature existed.
  ///  - _openEndPane sets _dragOffset = -_endPaneRevealWidth, so the reserve
  ///    is present for as long as the pane stays open — including at the
  ///    start of the drag that closes it, which is what keeps a short
  ///    bubble's hit region reachable.
  ///  - A reply-direction drag drives _dragOffset positive, and that
  ///    direction needs no reserve (see the build() comment at the
  ///    consuming Padding).
  /// Deliberately not gated on _endPaneOpen: _onHorizontalDragStart clears
  /// that flag at the start of every gesture, including the closing one, which
  /// would drop the reserve at the exact moment it is needed.
  double get _endPaneTranslationReserve =>
      widget.endActions != null && _effectiveDragOffset < 0
          ? _endPaneRevealWidth
          : 0;

  double get _effectiveDragOffset => widget.dragOffsetOverride ?? _dragOffset;

  bool get _hasEndDrag =>
      widget.endActions != null ||
      widget.endReveal != null ||
      widget.onEndRevealDragChanged != null;

  @override
  void dispose() {
    if (widget.groupTag != null && _endPaneOpen) {
      _EndPaneGroupRegistry.notifyClosed(widget.groupTag!, _closeEndPane);
    }
    _springController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _springController.stop();
    _hapticFired = false;
    _activeDragMode = null;
    _measureEndPaneRevealWidth();
    // Any new drag on an open pane is a fresh interaction with it: drop the
    // open flag and the group registration up front so the pane can't stay
    // registered as "the open one in this group" after being dragged shut
    // in either direction.
    _startedFromOpenEndPane = _endPaneOpen;
    if (_endPaneOpen) {
      _endPaneOpen = false;
      if (widget.groupTag != null) {
        _EndPaneGroupRegistry.notifyClosed(widget.groupTag!, _closeEndPane);
      }
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    // Direction alone only decides the mode from REST. A gesture that starts
    // with the end pane already revealed belongs to the end pane whichever
    // way it moves — dragging an open pane right is "close it" (the design
    // spec's "dragging the bubble back right past the reveal threshold closes
    // it without firing anything"), not the start of a reply swipe. Seeding
    // the lock from the open state rather than the first delta's sign is what
    // makes that closing drag reachable at all on a bubble that also has
    // onReply, where the reply branch would otherwise swallow it.
    _activeDragMode ??=
        _startedFromOpenEndPane
            ? _DragMode.endPane
            : (details.delta.dx > 0 ? _DragMode.reply : _DragMode.endPane);
    if (_activeDragMode == _DragMode.reply && widget.onReply != null) {
      _onReplyDragUpdate(details);
    } else if (_activeDragMode == _DragMode.endPane && _hasEndDrag) {
      _onEndPaneDragUpdate(details);
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_activeDragMode == _DragMode.reply) {
      _onReplyDragEnd(details);
    } else if (_activeDragMode == _DragMode.endPane) {
      _onEndPaneDragEnd(details);
    }
    _activeDragMode = null;
  }

  void _onHorizontalDragCancel() {
    if (_activeDragMode == _DragMode.reply) {
      _animateSpringBackFrom(_dragOffset);
    } else if (_activeDragMode == _DragMode.endPane) {
      if (widget.endActions == null) {
        widget.onEndRevealDragChanged?.call(0);
        setState(() => _dragOffset = 0);
      } else {
        _closeEndPane();
      }
    }
    _activeDragMode = null;
  }

  void _onEndPaneDragUpdate(DragUpdateDetails details) {
    if (!_hasEndDrag) return;
    final dragDelta =
        widget.endActions == null
            ? details.delta.dx * _timestampRevealDragGain
            : details.delta.dx;
    final rawOffset = _dragOffset + dragDelta;
    final clamped = rawOffset > 0 ? 0.0 : rawOffset;
    final revealLimit =
        widget.endActions == null ? _timestampRevealLimit : _endPaneRevealWidth;
    setState(() {
      _dragOffset = clamped.clamp(-revealLimit, 0.0);
    });
    widget.onEndRevealDragChanged?.call(_dragOffset.abs());
  }

  void _onEndPaneDragEnd(DragEndDetails details) {
    if (!_hasEndDrag) return;
    if (widget.endActions == null) {
      widget.onEndRevealDragChanged?.call(0);
      setState(() => _dragOffset = 0);
      return;
    }
    final shouldOpen = _dragOffset.abs() >= _endPaneRevealWidth / 2;
    if (shouldOpen) {
      _openEndPane();
    } else {
      _closeEndPane();
    }
  }

  void _openEndPane() {
    setState(() {
      _dragOffset = -_endPaneRevealWidth;
      _endPaneOpen = true;
    });
    if (widget.groupTag != null) {
      _EndPaneGroupRegistry.notifyOpening(widget.groupTag!, _closeEndPane);
    }
  }

  void _closeEndPane() {
    // Deregister BEFORE the early return, never conditionally after it:
    // _onHorizontalDragStart already clears _endPaneOpen at the start of
    // every new gesture, so a later _closeEndPane can find _endPaneOpen
    // false while a group registration is still live — returning early
    // first would leave that stale entry in the registry. notifyClosed only
    // removes an entry that matches this bubble's own callback, so calling
    // it unconditionally is idempotent.
    if (widget.groupTag != null) {
      _EndPaneGroupRegistry.notifyClosed(widget.groupTag!, _closeEndPane);
    }
    if (!_endPaneOpen && _dragOffset == 0) return;
    setState(() {
      _endPaneOpen = false;
    });
    _animateSpringBackFrom(_dragOffset);
  }

  void _onReplyDragUpdate(DragUpdateDetails details) {
    if (widget.onReply == null) return;
    final rawOffset = _dragOffset + details.delta.dx;
    // Only rightward (positive) drag matters for reply — clamp at 0 so a
    // leftward jitter inside a committed reply drag has no visual effect
    // (the leftward direction is _onEndPaneDragUpdate's business).
    final clamped = rawOffset < 0 ? 0.0 : rawOffset;
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
        _dragOffset = compressed;
      }
    });
    if (!_hapticFired && _dragOffset.abs() >= _fireThreshold) {
      _hapticFired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onReplyDragEnd(DragEndDetails details) {
    if (widget.onReply == null) return;
    final shouldFire = _dragOffset.abs() >= _fireThreshold;
    _animateSpringBackFrom(_dragOffset);
    if (shouldFire) {
      widget.onReply!();
    }
  }

  /// Shared by the reply bounce-back and the end-pane close — both animate
  /// [start] back to rest (0) over [_springBackDuration].
  void _animateSpringBackFrom(double start) {
    // Drop the previous animation's listener before replacing it: the
    // controller is reused across gestures, and a stale listener left
    // attached would keep writing its own (now-dead) tween's value into
    // _dragOffset on every tick of the next animation.
    _springAnimation?.removeListener(_onSpringTick);
    _springAnimation = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOut),
    )..addListener(_onSpringTick);
    _springController.forward(from: 0);
  }

  void _onSpringTick() {
    setState(() => _dragOffset = _springAnimation!.value);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDragOffset = _effectiveDragOffset;
    final highlightInset = widget.isHighlighted ? 2.0 : 0.0;
    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: widget.verticalPadding,
        ),
        // Wired unconditionally: each direction has its own null-check
        // inside its handler (onReply for rightward, endActions for
        // leftward), so gating the recognizer on onReply alone would
        // silently kill the end-pane direction for a caller that sets
        // endActions but no onReply.
        child: GestureDetector(
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onHorizontalDragCancel: _onHorizontalDragCancel,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (effectiveDragOffset > 0 && widget.startReveal != null)
                Positioned(
                  left: _endPaneTranslationReserve,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (effectiveDragOffset.abs() / _fireThreshold)
                          .clamp(0.0, 1.0),
                      alwaysIncludeSemantics: true,
                      child: widget.startReveal,
                    ),
                  ),
                )
              else if (effectiveDragOffset > 0)
                Positioned(
                  // Offset by the reserved translation slot (see
                  // _endPaneTranslationReserve) so the icon still sits at the
                  // bubble's own left edge, not the widened Stack's.
                  left: _endPaneTranslationReserve,
                  child: Opacity(
                    opacity: (effectiveDragOffset.abs() / _fireThreshold).clamp(
                      0.0,
                      1.0,
                    ),
                    child: Transform.scale(
                      scale:
                          0.7 +
                          0.3 *
                              (effectiveDragOffset.abs() / _fireThreshold)
                                  .clamp(0.0, 1.0),
                      child: Icon(
                        Icons.reply,
                        color:
                            widget.replyIconColor ??
                            (widget.isMine
                                ? widget.bubbleColor
                                : widget.onBubbleColor),
                      ),
                    ),
                  ),
                ),
              if (effectiveDragOffset < 0 && widget.endReveal != null)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (effectiveDragOffset.abs() / _fireThreshold)
                          .clamp(0.0, 1.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: widget.endReveal,
                      ),
                    ),
                  ),
                ),
              // End-pane actions, revealed behind the bubble on the RIGHT as
              // it is dragged left. Mirrors the reply icon's Positioned
              // layer above. The SizedBox width tracks the live drag offset
              // while OverflowBox keeps the children laid out at their full
              // intrinsic width, so they are never squeezed and the ClipRect
              // just wipes them into view.
              // Gated on endActions, NOT on `_dragOffset < 0`: the reveal
              // width is floored at the actions' own measured width, and
              // that measurement needs the actions Row to have been laid
              // out at least once. Gating on the offset made this circular
              // — the pane only rendered once dragged, so at drag start
              // _endActionsRowKey had no RenderBox, the floor never
              // applied, and a short bubble stayed stuck at its unusable
              // 25%-of-width reveal. At rest the SizedBox below is 0 wide
              // and the ClipRect paints nothing, so rendering it always is
              // visually identical.
              if (widget.endActions != null)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  // top/bottom anchor the pane to the bubble's own height:
                  // a Positioned with only `left` set inherits the Stack's
                  // unbounded height, and OverflowBox/ClipRect below both
                  // try to fill it, which asserts at layout.
                  child: Listener(
                    // Tapping a revealed action fires it AND closes the pane
                    // (the pre-replacement SlidableAction behavior). A
                    // Listener rather than a wrapping GestureDetector: it
                    // observes the pointer without entering the arena, so the
                    // caller's own button still wins its tap. Closing is
                    // deferred to the end of the frame so the action's
                    // onPressed — which may open a dialog — runs first.
                    onPointerUp: (_) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _closeEndPane();
                      });
                    },
                    child: SizedBox(
                      // Clamped, never the raw signed offset: this pane is
                      // mounted whenever endActions != null (so the actions
                      // Row can be measured on the very first gesture), which
                      // includes bubbles that ALSO have onReply — and a
                      // reply-direction drag on one of those drives
                      // _dragOffset positive. A negative width here throws
                      // "BoxConstraints has a negative minimum width" and
                      // cascades into an infinite-size assert. Zero is also
                      // the visually correct width mid-reply-swipe: the end
                      // pane has no business showing while the user is
                      // dragging the other way.
                      width: effectiveDragOffset < 0 ? -effectiveDragOffset : 0,
                      child: ClipRect(
                        child: OverflowBox(
                          // minWidth: 0 with an unbounded max lets the
                          // actions lay out at their own intrinsic width and
                          // stay put while the SizedBox above narrows to the
                          // live drag offset — the ClipRect then wipes them
                          // into view instead of the Row being squeezed (and
                          // overflowing) at every intermediate offset.
                          minWidth: 0,
                          maxWidth: double.infinity,
                          alignment: Alignment.centerRight,
                          child: Row(
                            key: _endActionsRowKey,
                            mainAxisSize: MainAxisSize.min,
                            children: widget.endActions ?? const [],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Reserved layout space on the left, so the Stack's own box
              // (and therefore the GestureDetector's hit-test rectangle above
              // it) always contains the bubble at its most-open position.
              // Transform.translate moves PAINT only — layout and hit-testing
              // stay at the untranslated position, and RenderBox.hitTest
              // rejects any pointer outside its own size before it ever
              // reaches a child. Without this reserve, an open end pane on a
              // short bubble left the painted bubble almost entirely outside
              // the detector, so a drag-to-close gesture started on the
              // visible bubble missed the recognizer and the pane was stuck
              // open. It also kept an isMine bubble's translated left edge
              // from running past the viewport, since the reserve is real
              // layout width that Align now accounts for.
              //
              // Left-side only, and only while the bubble is actually
              // translated left (_dragOffset < 0 — see
              // _endPaneTranslationReserve):
              //  - The reply direction translates RIGHT but always springs
              //    back within the same gesture, and a gesture that starts at
              //    rest (bubble inside the box) keeps receiving its moves via
              //    the arena regardless of later hit-testing — so it needs no
              //    reserve.
              //  - The end pane is the only direction with a persistent open
              //    state, hence the only one needing a hit region that
              //    survives the translation.
              //  - At rest (and for endActions == null, chat's MessageBubble,
              //    which can never reach a negative _dragOffset) nothing is
              //    reserved and the layout is byte-for-byte the previous one.
              Padding(
                padding: EdgeInsets.only(left: _endPaneTranslationReserve),
                child: Transform.translate(
                  offset: Offset(effectiveDragOffset, 0),
                  // IntrinsicWidth: the enclosing Stack expands to fill
                  // whatever width it is handed regardless of this child's own
                  // size — without this every bubble renders full-width and
                  // Align's left/right positioning above is silently defeated.
                  child: IntrinsicWidth(
                    key: _bubbleRowKey,
                    child: Row(
                      key: widget.bubbleKey,
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
                                      width: widget.isHighlighted ? 2 : 0,
                                    ),
                                  ),
                                  padding: EdgeInsets.all(highlightInset),
                                  child: GestureDetector(
                                    onLongPress:
                                        widget.onLongPress == null
                                            ? null
                                            : _handleLongPress,
                                    behavior: HitTestBehavior.opaque,
                                    child: DecoratedBox(
                                      key: _bubbleFillKey,
                                      decoration: BoxDecoration(
                                        color: widget.bubbleColor,
                                        gradient: widget.bubbleGradient,
                                        borderRadius: _bubbleBorderRadius,
                                        border:
                                            widget.showCardBorder
                                                ? Border.all(
                                                  // Same values CardInkWell
                                                  // itself uses.
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline
                                                      .withValues(alpha: 0.1),
                                                  width: 0.3,
                                                )
                                                : null,
                                        // A restrained 1dp-style lift for
                                        // chat bubbles. Kept faint so grouped
                                        // message runs still feel connected.
                                        boxShadow:
                                            widget.showShadow
                                                ? const [
                                                  BoxShadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 1,
                                                    spreadRadius: -1,
                                                    color: Color(0x0F000000),
                                                  ),
                                                  BoxShadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 1,
                                                    color: Color(0x0A000000),
                                                  ),
                                                  BoxShadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 2,
                                                    color: Color(0x08000000),
                                                  ),
                                                ]
                                                : null,
                                      ),
                                      child: Padding(
                                        padding: widget.contentPadding,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (widget.quotedText != null) ...[
                                              _quoteWithSideBar(
                                                context,
                                                GestureDetector(
                                                  onTap: widget.onJumpToParent,
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          widget
                                                              .quoteBackgroundColor ??
                                                          widget.onBubbleColor
                                                              .withValues(
                                                                alpha: 0.15,
                                                              ),
                                                      borderRadius:
                                                          _quoteBlockRadius(),
                                                    ),
                                                    child: Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (widget.isMine) ...[
                                                          _quoteIcon(),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                        ],
                                                        Flexible(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              if (widget
                                                                      .quoteAuthorLabel !=
                                                                  null)
                                                                Align(
                                                                  alignment:
                                                                      widget.isMine
                                                                          ? Alignment
                                                                              .centerRight
                                                                          : Alignment
                                                                              .centerLeft,
                                                                  child: Text(
                                                                    widget
                                                                        .quoteAuthorLabel!,
                                                                    style: (widget.quoteTextStyle ??
                                                                            TextStyle(
                                                                              color:
                                                                                  widget.quoteForegroundColor ??
                                                                                  widget.onBubbleColor,
                                                                              fontSize:
                                                                                  12,
                                                                            ))
                                                                        .copyWith(
                                                                          color:
                                                                              widget.quoteAuthorIsMine ==
                                                                                      null
                                                                                  ? null
                                                                                  : _quoteSideBarColor(
                                                                                    context,
                                                                                    widget.quoteAuthorIsMine!,
                                                                                  ),
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                        ),
                                                                  ),
                                                                ),
                                                              Text(
                                                                widget
                                                                    .quotedText!,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    widget
                                                                        .quoteTextStyle ??
                                                                    TextStyle(
                                                                      color:
                                                                          widget
                                                                              .quoteForegroundColor ??
                                                                          widget
                                                                              .onBubbleColor,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        if (!widget.isMine) ...[
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          _quoteIcon(),
                                                        ],
                                                      ],
                                                    ),
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
                              if (widget.showFooter) ...[
                                SizedBox(height: widget.footerSpacing),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: widget.maxWidth,
                                  ),
                                  child: widget.footer,
                                ),
                              ],
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
