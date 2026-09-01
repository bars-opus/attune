import 'dart:async';
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
    // This governs only the backdrop blur/dim and the bubble snapshot's
    // own scale-up below — the menu, reaction row, and per-emoji ripple
    // each run their own independent AnimatedScaleFade with its own
    // duration/stagger (see _FocusedActionMenuOverlay's _entranceDuration/
    // _staggerDelay). Checklist 5.2's 200ms target is about
    // time-to-FIRST-feedback (the haptic + backdrop + bubble scale all
    // start at t=0, satisfying that), not that the whole entrance must
    // finish within 200ms.
    transitionDuration: const Duration(milliseconds: 260),
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

class _FocusedActionMenuOverlay extends StatefulWidget {
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

  @override
  State<_FocusedActionMenuOverlay> createState() =>
      _FocusedActionMenuOverlayState();
}

class _FocusedActionMenuOverlayState extends State<_FocusedActionMenuOverlay> {
  // Set once dismissal starts (scrim tap, back gesture, or an action/
  // reaction firing — anything that pops this route) so every
  // AnimatedScaleFade below flips to reverse and plays the SAME stagger
  // backwards. See the Interval-reverses-in-place reasoning on
  // AnimatedScaleFade.reverse: reusing each item's existing staggerIndex
  // under reverse:true naturally gives last-in-first-out — row+emoji
  // (entered last) exit first, menu (entered first) exits last — with no
  // index inversion needed.
  //
  // This is driven by PopScope rather than a _dismiss() method the menu
  // calls directly: individual action tiles (buildMessageActionItems)
  // pop via their OWN tile-local BuildContext for deactivated-context
  // safety (see that file's doc comment) and are not routed through this
  // widget at all, so intercepting every dismiss path uniformly means
  // intercepting the pop itself, not the many call sites that trigger it.
  bool _dismissing = false;
  Timer? _dismissTimer;
  Completer<bool>? _dismissCompleter;

  // Captured in didChangeDependencies (below) — the standard place to
  // safely read ModalRoute.of(context) for a State — rather than at pop
  // time: onOpenFullPicker (fired eagerly, before the reverse delay
  // in _handlePop below) pushes its own route, the full picker's bottom
  // sheet, on top of this one, and a bare Navigator.of(context).pop() at
  // that point closes whichever route is topmost. Without capturing THIS
  // route up front, the delayed pop below closes the picker sheet instead
  // of this menu — it would open, then silently vanish moments later.
  ModalRoute<void>? _ownRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ownRoute ??= ModalRoute.of(context);
  }

  Future<bool> _handlePop() {
    if (_dismissing) return _dismissCompleter?.future ?? Future.value(true);
    setState(() => _dismissing = true);
    final completer = Completer<bool>();
    _dismissCompleter = completer;
    _dismissTimer = Timer(_dismissDuration, () {
      _dismissTimer = null;
      _dismissCompleter = null;
      completer.complete(true);
    });
    return completer.future;
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (_dismissCompleter case final completer? when !completer.isCompleted) {
      completer.complete(true);
    }
    _dismissCompleter = null;
    super.dispose();
  }

  // Rough per-item height estimate for the flip-above/below decision —
  // ListTile's default dense-false height is 56, plus a little breathing
  // room. Doesn't need to be exact: worst case the menu slightly overlaps
  // the safe area edge on an unusually tall action list, which is far
  // better than rendering fully off-screen.
  static const double _estimatedItemHeight = 56;
  static const double _gap = 4;

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
      (widget.quickReactions.length + 1) * _reactionItemWidth +
      _reactionRowPadding;

  // One compact motion rhythm drives the menu, row, emoji, and action items.
  // The short overlap is deliberate: modern iMessage feels like one surface
  // unfolding, not several cards waiting for each other to finish.
  static const Duration _entranceDuration = Duration(milliseconds: 560);
  static const Duration _dismissDuration = Duration(milliseconds: 360);
  static const double _staggerDelay = 0.1;
  static const int _menuStaggerIndex = 0;
  static const int _reactionRowStaggerIndex = 1;

  // Each emoji's own index starts right after the row's, so the ripple
  // continues the same stagger sequence rather than restarting at 0.
  int _emojiStaggerIndex(int emojiPosition) =>
      _reactionRowStaggerIndex + 1 + emojiPosition;

  Duration _emojiDuration(int emojiPosition) =>
      Duration(milliseconds: 360 + emojiPosition.clamp(0, 6) * 28);

  static const double _emojiStaggerDelay = 0.08;

  int _actionStaggerIndex(int actionPosition) => 1 + actionPosition;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    final estimatedMenuHeight =
        widget.actions.length * _estimatedItemHeight +
        _reactionRowHeight +
        _gap;

    final fitsBelow =
        widget.anchorRect.bottom + _gap + estimatedMenuHeight <=
        screenSize.height - safeAreaBottom;

    final menuWidth = 208.0;
    // The reaction row is a SEPARATE card from the action list and is
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
    final widestCardWidth =
        _estimatedReactionRowWidth > menuWidth
            ? (_estimatedReactionRowWidth < maxCardWidth
                ? _estimatedReactionRowWidth
                : maxCardWidth)
            : menuWidth;
    final maxLeft = (screenSize.width - widestCardWidth - 8.0).clamp(
      8.0,
      double.infinity,
    );
    final clampedLeft = widget.anchorRect.left.clamp(8.0, maxLeft);

    // Every staged AnimatedScaleFade below reads this so a single flag
    // flip (via PopScope's onPopInvokedWithResult, see _handlePop) sends
    // the whole entrance sequence into reverse together.
    final reversing = _dismissing;
    final surfaceMotionDuration =
        reversing ? _dismissDuration : _entranceDuration;

    final reactionRow = Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(28),
      elevation: 12,
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
                for (var i = 0; i < widget.quickReactions.length; i++)
                  _FocusedAttachMenuMotion(
                    key: ValueKey('focused-reaction-$i'),
                    duration: reversing ? _dismissDuration : _emojiDuration(i),
                    beginScale: 0.55,
                    beginOffset: const Offset(12, 10),
                    alignment: Alignment.center,
                    staggerIndex: _emojiStaggerIndex(i),
                    staggerDelay: _emojiStaggerDelay,
                    reverse: reversing,
                    child: _PressScale(
                      pressedScale: 0.84,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final emoji = widget.quickReactions[i].emoji;
                          Navigator.of(context).maybePop().then((_) {
                            widget.onReact(emoji);
                          });
                        },
                        borderRadius: BorderRadius.circular(22),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Text(
                              widget.quickReactions[i].emoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                _FocusedAttachMenuMotion(
                  key: const ValueKey('focused-reaction-more'),
                  duration:
                      reversing
                          ? _dismissDuration
                          : _emojiDuration(widget.quickReactions.length),
                  beginScale: 0.55,
                  beginOffset: const Offset(12, 10),
                  alignment: Alignment.center,
                  staggerIndex: _emojiStaggerIndex(
                    widget.quickReactions.length,
                  ),
                  staggerDelay: _emojiStaggerDelay,
                  reverse: reversing,
                  child: _PressScale(
                    pressedScale: 0.84,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).maybePop().then((_) {
                          widget.onOpenFullPicker();
                        });
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(child: Icon(Icons.add, size: 22)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return PopScope(
      canPop: _dismissing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handlePop().then((_) {
          final route = _ownRoute;
          if (route != null && route.isActive) {
            route.navigator?.removeRoute(route);
          }
        });
      },
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, child) {
            final focusProgress = Curves.easeOutCubic.transform(
              widget.animation.value,
            );
            return Stack(
              children: [
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: 0.3 * widget.animation.value,
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: widget.anchorRect,
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(0, -5 * focusProgress),
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
                      child: Transform.scale(
                        scale: 1.0 + 0.035 * focusProgress,
                        child: Material(
                          type: MaterialType.transparency,
                          child: widget.anchorSnapshot,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: clampedLeft,
                  top: fitsBelow ? widget.anchorRect.bottom + _gap : null,
                  bottom:
                      fitsBelow
                          ? null
                          : screenSize.height - widget.anchorRect.top + _gap,
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
                        // sequence: the menu begins, then this row joins 18ms
                        // later, followed by its emoji ripple. On dismiss
                        // this same index makes the row exit before the menu.
                        _FocusedAttachMenuMotion(
                          key: const ValueKey('focused-reaction-row'),
                          duration: surfaceMotionDuration,
                          beginScale: 0.78,
                          beginOffset: const Offset(34, 26),
                          alignment: Alignment.centerLeft,
                          staggerIndex: _reactionRowStaggerIndex,
                          staggerDelay: _staggerDelay,
                          reverse: reversing,
                          child: reactionRow,
                        ),
                        const SizedBox(height: _gap),
                        // The action-menu surface starts first. Its rows and
                        // the reaction surface then overlap in a compact
                        // cascade. On dismiss, index 0 makes it exit last.
                        _FocusedAttachMenuMotion(
                          key: const ValueKey('focused-action-menu'),
                          duration: surfaceMotionDuration,
                          beginScale: 0.78,
                          beginOffset: const Offset(34, 26),
                          alignment: Alignment.topLeft,
                          staggerIndex: _menuStaggerIndex,
                          staggerDelay: _staggerDelay,
                          reverse: reversing,
                          child: Material(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.97),
                            surfaceTintColor: Colors.transparent,
                            shadowColor: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(24),
                            elevation: 12,
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: menuWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (
                                    var i = 0;
                                    i < widget.actions.length;
                                    i++
                                  )
                                    _FocusedAttachMenuMotion(
                                      key: ValueKey('focused-action-$i'),
                                      duration: surfaceMotionDuration,
                                      curve: Curves.easeOutBack,
                                      beginScale: 0.86,
                                      beginOffset: const Offset(24, 18),
                                      alignment: Alignment.centerLeft,
                                      staggerIndex: _actionStaggerIndex(i),
                                      staggerDelay: _staggerDelay,
                                      reverse: reversing,
                                      child: _PressScale(
                                        pressedScale: 0.975,
                                        child: widget.actions[i],
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FocusedAttachMenuMotion extends StatefulWidget {
  const _FocusedAttachMenuMotion({
    super.key,
    required this.child,
    required this.duration,
    required this.staggerIndex,
    required this.staggerDelay,
    required this.reverse,
    this.curve = Curves.easeOutBack,
    this.beginScale = 0.78,
    this.beginOffset = const Offset(34, 26),
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final int staggerIndex;
  final double staggerDelay;
  final bool reverse;
  final Curve curve;
  final double beginScale;
  final Offset beginOffset;
  final Alignment alignment;

  @override
  State<_FocusedAttachMenuMotion> createState() =>
      _FocusedAttachMenuMotionState();
}

class _FocusedAttachMenuMotionState extends State<_FocusedAttachMenuMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _motionProgress;
  late Animation<double> _opacityProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _buildAnimation();
    widget.reverse ? _controller.reverse(from: 1) : _controller.forward();
  }

  @override
  void didUpdateWidget(_FocusedAttachMenuMotion oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }

    if (widget.curve != oldWidget.curve ||
        widget.staggerIndex != oldWidget.staggerIndex ||
        widget.staggerDelay != oldWidget.staggerDelay) {
      _buildAnimation();
    }

    if (widget.reverse != oldWidget.reverse) {
      widget.reverse ? _controller.reverse() : _controller.forward();
    }
  }

  void _buildAnimation() {
    final start = (widget.staggerIndex * widget.staggerDelay).clamp(0.0, 0.82);
    final end = (start + 0.72).clamp(0.0, 1.0).toDouble();
    final intervalStart = start.toDouble();
    _motionProgress = CurvedAnimation(
      parent: _controller,
      curve: Interval(intervalStart, end, curve: widget.curve),
    );
    _opacityProgress = CurvedAnimation(
      parent: _controller,
      curve: Interval(intervalStart, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final motion = _motionProgress.value;
        final opacity = _opacityProgress.value;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(
            alignment: widget.alignment,
            scale: widget.beginScale + ((1 - widget.beginScale) * motion),
            child: Transform.translate(
              offset: Offset(
                widget.beginOffset.dx * (1 - motion),
                widget.beginOffset.dy * (1 - motion),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Adds the small compress-and-release response that makes a held control
/// feel physical while leaving the child's own InkWell/tap semantics intact.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.pressedScale});

  final Widget child;
  final double pressedScale;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration:
            _pressed
                ? const Duration(milliseconds: 90)
                : const Duration(milliseconds: 210),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
