import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

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
    // 220ms: comfortably under the checklist's 250ms interactive-feel
    // target for the full open animation, matching iOS's own
    // context-menu transition speed.
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _FocusedActionMenuOverlay(
        anchorRect: anchorRect,
        anchorSnapshot: anchorSnapshot,
        actions: actions,
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
    required this.animation,
  });

  final Rect anchorRect;
  final Widget anchorSnapshot;
  final List<Widget> actions;
  final Animation<double> animation;

  // Rough per-item height estimate for the flip-above/below decision —
  // ListTile's default dense-false height is 56, plus a little breathing
  // room. Doesn't need to be exact: worst case the menu slightly overlaps
  // the safe area edge on an unusually tall action list, which is far
  // better than rendering fully off-screen.
  static const double _estimatedItemHeight = 56;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final estimatedMenuHeight = actions.length * _estimatedItemHeight;

    final fitsBelow = anchorRect.bottom + _gap + estimatedMenuHeight <=
        screenSize.height - safeAreaBottom;

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
                    child: anchorSnapshot,
                  ),
                ),
              ),
              Positioned(
                left: anchorRect.left,
                top: fitsBelow ? anchorRect.bottom + _gap : null,
                bottom: fitsBelow
                    ? null
                    : screenSize.height - anchorRect.top + _gap,
                child: FadeTransition(
                  opacity: animation,
                  child: GestureDetector(
                    // Swallow taps on the menu itself so they don't fall
                    // through to the scrim's dismiss-on-tap-outside handler —
                    // individual action ListTiles still handle their own
                    // onTap and pop the route themselves.
                    onTap: () {},
                    child: Material(
                      borderRadius: BorderRadius.circular(14),
                      elevation: 8,
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: 240,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: actions,
                        ),
                      ),
                    ),
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
