import 'package:flutter/material.dart';

/// How a block enters and leaves the plan's page: it grows in, fades in and
/// rises slightly when inserted — with the page following it, so a block
/// added at the bottom is seen arriving rather than appearing off screen —
/// and collapses and fades out before it is deleted, so the blocks around
/// it slide into place instead of jumping. With Reduce motion on, both are
/// instant.
class PlanningBlockMotion extends StatefulWidget {
  const PlanningBlockMotion({
    super.key,
    required this.child,
    this.enter = false,
    this.leaving = false,
    this.onLeft,
  });

  static const duration = Duration(milliseconds: 300);

  final Widget child;

  /// Animate in when first shown (a block just inserted).
  final bool enter;

  /// Animate out; [onLeft] runs when it is fully gone.
  final bool leaving;
  final VoidCallback? onLeft;

  @override
  State<PlanningBlockMotion> createState() => _PlanningBlockMotionState();
}

class _PlanningBlockMotionState extends State<PlanningBlockMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PlanningBlockMotion.duration,
    value: widget.enter ? 0 : 1,
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _rise =
      Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(_curve);

  bool get _instant => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.enter && _c.value == 0 && !_c.isAnimating) {
      if (_instant) {
        _c.value = 1;
      } else {
        _c.addListener(_follow);
        _c.forward().whenCompleteOrCancel(() => _c.removeListener(_follow));
      }
    }
  }

  /// While entering, keep the growing block's bottom on screen (a no-op
  /// when it already is, e.g. inserted mid-page).
  void _follow() {
    if (!mounted || _c.status != AnimationStatus.forward) return;
    Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
  }

  @override
  void didUpdateWidget(PlanningBlockMotion old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      if (_instant) {
        _c.value = 0;
        widget.onLeft?.call();
      } else {
        _c.reverse().whenCompleteOrCancel(() => widget.onLeft?.call());
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _curve,
        axisAlignment: -1,
        child: FadeTransition(
          opacity: _curve,
          child: SlideTransition(position: _rise, child: widget.child),
        ),
      );
}
