import 'dart:ui';

import 'package:attune/core/utils/animations/animated_scale_fade.dart';
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
    // This governs only the backdrop blur/dim and the bubble snapshot's
    // own scale-up below — the menu, reaction row, and per-emoji ripple
    // each run their own independent AnimatedScaleFade with its own
    // duration/stagger (see _FocusedActionMenuOverlay's _entranceDuration/
    // _staggerDelay). Checklist 5.2's 200ms target is about
    // time-to-FIRST-feedback (the haptic + backdrop + bubble scale all
    // start at t=0, satisfying that), not that the whole entrance must
    // finish within 200ms.
    transitionDuration: const Duration(milliseconds: 220),
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
  // (Reply/Copy/...) scales+fades in first, THEN the reaction row's own
  // container, THEN — once the row itself is in — each emoji inside it in
  // turn, left-to-right, as a quick ripple. Built with this codebase's own
  // AnimatedScaleFade (already used for chat's reply-preview strip and
  // forums' equivalent — see chat_screen.dart/debate_room_screen.dart) via
  // its staggerIndex/staggerDelay, rather than hand-rolled Interval-slicing
  // of the dialog route's shared `animation`: each stage below is its own
  // independent, self-contained AnimatedScaleFade instance (own
  // AnimationController, autoStart on mount), which is simpler to reason
  // about than threading N different Interval windows through one shared
  // animation, at the cost of no longer riding the SAME animation as the
  // backdrop blur/bubble scale below (those two still do, unchanged) and
  // no reverse-on-dismiss stagger (dismiss just uses the dialog route's
  // own default close, matching this feature's the-open-animation-is-what-
  // matters scope).
  //
  // staggerDelay is per-INDEX, not per-stage — the whole sequence (menu,
  // then row, then each emoji) is one continuous stagger sharing one
  // duration, indices 0..N in visual order.
  static const Duration _entranceDuration = Duration(milliseconds: 500);
  static const double _staggerDelay = 0.12;
  static const int _menuStaggerIndex = 0;
  static const int _reactionRowStaggerIndex = 1;

  // Each emoji's own index starts right after the row's, so the ripple
  // continues the same stagger sequence rather than restarting at 0.
  int _emojiStaggerIndex(int emojiPosition) =>
      _reactionRowStaggerIndex + 1 + emojiPosition;

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
                  AnimatedScaleFade(
                    duration: _entranceDuration,
                    curve: Curves.easeOutBack,
                    beginScale: 0.4,
                    staggerIndex: _emojiStaggerIndex(i),
                    staggerDelay: _staggerDelay,
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
                AnimatedScaleFade(
                  duration: _entranceDuration,
                  curve: Curves.easeOutBack,
                  beginScale: 0.4,
                  staggerIndex: _emojiStaggerIndex(quickReactions.length),
                  staggerDelay: _staggerDelay,
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
                      // The reaction row animates in on its own stagger
                      // index (_reactionRowStaggerIndex), starting after
                      // the action menu below has begun — matching the
                      // real sequence: menu first, then the row, then
                      // (inside the row) each emoji in turn.
                      AnimatedScaleFade(
                        duration: _entranceDuration,
                        curve: Curves.easeOutBack,
                        staggerIndex: _reactionRowStaggerIndex,
                        staggerDelay: _staggerDelay,
                        child: reactionRow,
                      ),
                      const SizedBox(height: _gap),
                      // The action menu (Reply/Copy/...) is the FIRST stage
                      // to animate in (staggerIndex 0) — everything else
                      // (the reaction row and its own per-emoji ripple)
                      // follows this rather than running alongside it.
                      AnimatedScaleFade(
                        duration: _entranceDuration,
                        curve: Curves.easeOutBack,
                        staggerIndex: _menuStaggerIndex,
                        staggerDelay: _staggerDelay,
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
