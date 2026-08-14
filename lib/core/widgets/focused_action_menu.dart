import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// One emoji in the focused menu's quick-reaction row.
class ReactionQuickOption {
  const ReactionQuickOption({required this.emoji});
  final String emoji;
}

/// iMessage-style long-press action menu: the anchor (a duplicate of the
/// long-pressed bubble, painted at its real screen position) scales up
/// slightly as the backdrop blurs and dims behind it, and the given
/// [actions] float anchored beside it — below by default, flipped above
/// when there isn't room. General-purpose: has no knowledge of chat or
/// Message — callers hand in exactly what to render.
///
/// See docs/superpowers/specs/2026-08-14-focused-message-menu-design.md.
Future<void> showFocusedActionMenu({
  required BuildContext context,
  required Rect anchorRect,
  required Widget anchorSnapshot,
  required List<Widget> actions,
  required List<ReactionQuickOption> quickReactions,
  required void Function(String emoji) onReact,
  required VoidCallback onOpenFullPicker,
}) {
  // Fires synchronously, before the route even opens — matches "the
  // instant the menu opens," not deferred to an animation-complete
  // callback.
  HapticFeedback.lightImpact();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: 'Message actions',
    // 350ms total, staged internally (see _FocusedActionMenuOverlay's
    // _menuInterval/_reactionRowInterval/_reactionItemStagger) so the
    // action menu, then the reaction row, then each emoji within it can
    // each read as a distinct step rather than one blurred-together pop.
    // Checklist 5.2's 200ms target is about time-to-FIRST-feedback (the
    // haptic + backdrop + bubble scale all start at t=0, satisfying that),
    // not that the whole entrance animation must finish within 200ms.
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _FocusedActionMenuOverlay(
        anchorRect: anchorRect,
        anchorSnapshot: anchorSnapshot,
        actions: actions,
        quickReactions: quickReactions,
        onReact: onReact,
        onOpenFullPicker: onOpenFullPicker,
        animation: animation,
      );
    },
  );
}

class _FocusedActionMenuOverlay extends StatelessWidget {
  const _FocusedActionMenuOverlay({
    required this.anchorRect,
    required this.anchorSnapshot,
    required this.actions,
    required this.quickReactions,
    required this.onReact,
    required this.onOpenFullPicker,
    required this.animation,
  });

  final Rect anchorRect;
  final Widget anchorSnapshot;
  final List<Widget> actions;
  final List<ReactionQuickOption> quickReactions;
  final void Function(String emoji) onReact;
  final VoidCallback onOpenFullPicker;
  final Animation<double> animation;

  // Rough per-item height estimate for the flip-above/below decision —
  // ListTile's default dense-false height is 56, plus a little breathing
  // room. Doesn't need to be exact: worst case the menu slightly overlaps
  // the safe area edge on an unusually tall action list, which is far
  // better than rendering fully off-screen.
  static const double _estimatedItemHeight = 56;
  static const double _gap = 8;

  // The quick-reaction row's own height, budgeted into the flip-above/below
  // decision below: the row is docked ABOVE the action list, so it adds real
  // height that must fit on screen alongside the actions. Exact: the 44px
  // tap target plus the row's own 6px top + 6px bottom padding.
  static const double _reactionRowHeight = 56;

  // Each item is a fixed 44x44 tap target (accessibility minimum touch
  // target size), so this is exact — not an estimate — plus the row's own
  // 8px horizontal padding each side.
  static const double _reactionItemWidth = 44;
  static const double _reactionRowPadding = 16;

  double get _estimatedReactionRowWidth =>
      // +1 for the trailing "+" button, which is always present.
      (quickReactions.length + 1) * _reactionItemWidth + _reactionRowPadding;

  // Staged entrance, matching the real iMessage sequence: the action menu
  // (Reply/Copy/...) animates in first, THEN the reaction row's own
  // container animates in starting partway through the menu's animation
  // (not simultaneously, not fully sequential either — a slight overlap
  // reads as one continuous motion rather than two disconnected pops),
  // and once the row itself is animating, each emoji inside it staggers in
  // left-to-right as a quick ripple. All three intervals share the SAME
  // underlying `animation` (the dialog route's own transition, still no
  // separate AnimationController — see the file-level doc comment on
  // showFocusedActionMenu) via Interval/CurvedAnimation, so reversing the
  // route (dismiss) automatically plays every stage backwards in the
  // correct reverse order: whatever finished animating in LAST is the
  // first to disappear.
  static const Interval _menuInterval = Interval(0.0, 0.55, curve: Curves.easeOut);
  static const Interval _reactionRowInterval = Interval(0.35, 0.75, curve: Curves.easeOut);

  // The per-emoji ripple lives inside the row's own [0.75, 1.0] tail —
  // after the row container itself has finished scaling in — so each
  // emoji's individual pop is layered on top of an already-settled row,
  // not fighting the row's own still-growing size.
  static const double _staggerStart = 0.75;
  static const double _staggerEnd = 1.0;

  /// The Nth item's own [start, end] window within [_staggerStart,
  /// _staggerEnd], evenly spaced so the ripple reads as one continuous
  /// left-to-right wave rather than N independent pops. [itemCount]
  /// includes the trailing "+" button, so a 6-emoji row staggers 7 items.
  Interval _staggerFor(int index, int itemCount) {
    if (itemCount <= 1) {
      return const Interval(_staggerStart, _staggerEnd, curve: Curves.easeOut);
    }
    // Each item's window overlaps its neighbors' by half — a pure
    // back-to-back split (window width = totalSpan / itemCount) would make
    // a 7-item row's ripple imperceptibly fast within a 250ms tail; the
    // overlap keeps each item's own motion long enough to read while still
    // finishing in order.
    final totalSpan = _staggerEnd - _staggerStart;
    final step = totalSpan / itemCount;
    final windowWidth = step * 1.5;
    final start = _staggerStart + step * index;
    final end = (start + windowWidth).clamp(start, _staggerEnd);
    return Interval(start, end, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final estimatedMenuHeight =
        actions.length * _estimatedItemHeight + _reactionRowHeight + _gap;

    final fitsBelow = anchorRect.bottom + _gap + estimatedMenuHeight <=
        screenSize.height - safeAreaBottom;

    final menuWidth = 240.0;
    // The reaction row is a SEPARATE card from the 240px action list and is
    // sized by its own content, so with a realistic tapback set (6 emoji plus
    // the "+") it measures wider than menuWidth. Clamping only against
    // menuWidth would leave the wider card hanging off the right edge — the
    // same overflow class already fixed once for the action list. Budget the
    // widest card for the clamp, and cap the row itself to the usable width so
    // an unusually long emoji list scrolls instead of overflowing.
    final maxCardWidth = (screenSize.width - 16.0).clamp(0.0, double.infinity);
    final reactionRowMaxWidth = maxCardWidth;
    // clamp's lower bound must not exceed its upper bound, which it would on a
    // viewport narrower than menuWidth — take the min explicitly instead.
    final widestCardWidth = _estimatedReactionRowWidth > menuWidth
        ? (_estimatedReactionRowWidth < maxCardWidth
            ? _estimatedReactionRowWidth
            : maxCardWidth)
        : menuWidth;
    final maxLeft =
        (screenSize.width - widestCardWidth - 8.0).clamp(8.0, double.infinity);
    final clampedLeft = anchorRect.left.clamp(8.0, maxLeft);

    // Navigator.of(context) here reads THIS widget's own build context — the
    // dialog route's context, obtained fresh on every build — not a context
    // captured from the call site outside the route. Same reasoning as the
    // scrim's onTap below.
    //
    // itemCount includes the trailing "+" button, so the ripple staggers
    // across quickReactions.length + 1 items total.
    final itemCount = quickReactions.length + 1;
    final reactionRow = Material(
      borderRadius: BorderRadius.circular(24),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: reactionRowMaxWidth),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < quickReactions.length; i++)
                  _StaggeredScaleFade(
                    interval: _staggerFor(i, itemCount),
                    animation: animation,
                    scaleFrom: 0.6,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        onReact(quickReactions[i].emoji);
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Text(
                            quickReactions[i].emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
                _StaggeredScaleFade(
                  interval: _staggerFor(quickReactions.length, itemCount),
                  animation: animation,
                  scaleFrom: 0.6,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenFullPicker();
                    },
                    borderRadius: BorderRadius.circular(22),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(child: Icon(Icons.add, size: 22)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Stack(
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black
                        .withValues(alpha: 0.3 * animation.value),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: anchorRect,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1.0 + 0.05 * animation.value,
                    // The snapshot is a bare widget subtree lifted out of
                    // the page below and re-rendered under this dialog
                    // route, where there is no enclosing Material. Text
                    // with no Material ancestor falls back to Flutter's
                    // 48px red-on-yellow "consider putting your text in a
                    // Material" debug style — which is both visibly wrong
                    // and, at that size, wraps and overflows the tight
                    // anchorRect box it is pinned into. A transparent
                    // Material restores the normal DefaultTextStyle
                    // inheritance so the snapshot re-derives exactly the
                    // layout the real bubble already has.
                    child: Material(
                      type: MaterialType.transparency,
                      child: anchorSnapshot,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: clampedLeft,
                top: fitsBelow ? anchorRect.bottom + _gap : null,
                bottom: fitsBelow
                    ? null
                    : screenSize.height - anchorRect.top + _gap,
                child: GestureDetector(
                  // Swallow taps on the menu itself so they don't fall
                  // through to the scrim's dismiss-on-tap-outside handler —
                  // individual action ListTiles still handle their own
                  // onTap and pop the route themselves.
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The reaction row animates on its OWN interval
                      // (_reactionRowInterval), staged to start after the
                      // action menu below has begun animating — matching
                      // the real sequence: menu first, then the row,
                      // then (inside the row) each emoji in turn. Anchored
                      // to the same corner as the menu below so both grow
                      // out of the bubble rather than their own centers.
                      _StaggeredScaleFade(
                        interval: _reactionRowInterval,
                        animation: animation,
                        alignment:
                            fitsBelow ? Alignment.topLeft : Alignment.bottomLeft,
                        child: reactionRow,
                      ),
                      const SizedBox(height: _gap),
                      // The action menu (Reply/Copy/...) is the FIRST stage
                      // to animate in, on _menuInterval — everything else
                      // (the reaction row and its own per-emoji ripple)
                      // follows this rather than running alongside it.
                      _StaggeredScaleFade(
                        interval: _menuInterval,
                        animation: animation,
                        alignment:
                            fitsBelow ? Alignment.topLeft : Alignment.bottomLeft,
                        child: Material(
                          borderRadius: BorderRadius.circular(14),
                          elevation: 8,
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            width: menuWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fades and scales [child] in across its own [interval] of the shared
/// [animation], driving [CurvedAnimation]/[Interval] rather than a separate
/// [AnimationController] per stage/item — up to 9 of these can exist at
/// once (the menu, the reaction row, and up to 7 items inside it), and a
/// controller each would mean 9 extra tickers for something the single
/// route-owned animation already drives cleanly via interval slicing.
/// [Interval] clamps its input to the interval's own [0, 1] range outside
/// that window (Flutter's own documented behavior), so this needs no extra
/// clamping here — before the interval starts the child is fully
/// transparent/at [scaleFrom], after it ends the child is fully
/// opaque/at rest (scale 1.0).
///
/// Used both for the menu/reaction-row's own entrance (wider scale range,
/// alignment anchored toward the bubble) and the per-emoji ripple inside
/// the reaction row (tighter range, no meaningful alignment since each
/// item is small and centered in its own 44x44 box — [alignment] defaults
/// to [Alignment.center] for that case).
class _StaggeredScaleFade extends StatelessWidget {
  const _StaggeredScaleFade({
    required this.interval,
    required this.animation,
    required this.child,
    this.alignment = Alignment.center,
    this.scaleFrom = 0.85,
  });

  final Interval interval;
  final Animation<double> animation;
  final Widget child;
  final Alignment alignment;
  final double scaleFrom;

  @override
  Widget build(BuildContext context) {
    final staggered = CurvedAnimation(parent: animation, curve: interval);
    return FadeTransition(
      opacity: staggered,
      child: AnimatedBuilder(
        animation: staggered,
        builder: (context, builtChild) => Transform.scale(
          scale: scaleFrom + (1.0 - scaleFrom) * staggered.value,
          alignment: alignment,
          child: builtChild,
        ),
        child: child,
      ),
    );
  }
}
