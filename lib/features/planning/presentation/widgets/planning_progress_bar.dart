import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// A goal's progress bar. With [segments] (a goal of a few steps) it's one
/// rounded segment per step, filling left to right in turn; otherwise one
/// smooth bar, with faint quarter marks when [milestones]. It fills in from
/// empty when it first shows and eases to a new value — the budget gauge's
/// timing — and simply shows it with reduce motion.
class PlanningProgressBar extends StatefulWidget {
  const PlanningProgressBar({
    super.key,
    required this.fraction,
    this.segments,
    this.milestones = false,
    this.height = 10,
  });

  /// How full, 0..1 (clamped).
  final double fraction;
  final int? segments;
  final bool milestones;
  final double height;

  @override
  State<PlanningProgressBar> createState() => PlanningProgressBarState();
}

@visibleForTesting
class PlanningProgressBarState extends State<PlanningProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _c,
    curve: const Cubic(0.05, 0.7, 0.1, 1.0),
  );
  double _from = 0;
  late double _to = _clamp(widget.fraction);
  bool _started = false;

  static double _clamp(double f) => f.isNaN ? 0 : f.clamp(0.0, 1.0).toDouble();

  /// How full it is on screen right now.
  double get shown => _from + (_to - _from) * _eased.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotionOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(PlanningProgressBar old) {
    super.didUpdateWidget(old);
    final next = _clamp(widget.fraction);
    if (next == _to) return;
    _from = shown;
    _to = next;
    if (reduceMotionOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.primary;
    final track = scheme.primary.withValues(alpha: 0.18);
    final radius = BorderRadius.circular(widget.height / 2);
    Widget part(double amount) => ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: amount.clamp(0.0, 1.0),
              child: ColoredBox(color: fill),
            ),
          ],
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = shown;
        final n = widget.segments;
        if (n != null && n > 1) {
          // Each segment takes its share of the sweep, so they fill in turn.
          return Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(child: part(v * n - i)),
              ],
            ],
          );
        }
        return Stack(
          children: [
            part(v),
            if (widget.milestones)
              Positioned.fill(
                child: Row(
                  children: [
                    for (var q = 1; q <= 4; q++)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child:
                              q == 4
                                  ? const SizedBox.shrink()
                                  : Container(
                                    width: 2,
                                    color: scheme.surface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
