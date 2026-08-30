import 'package:flutter/widgets.dart';

import 'reduce_motion.dart';

/// Quick scale down-and-back "pop" when [trigger] changes. Universal press/
/// confirm feedback for any button or icon.
class ScalePop extends StatefulWidget {
  const ScalePop({
    super.key,
    required this.child,
    required this.trigger,
    this.magnitude = 0.12,
    this.duration = const Duration(milliseconds: 180),
  });

  final Widget child;
  final Object trigger;
  final double magnitude;
  final Duration duration;

  @override
  State<ScalePop> createState() => _ScalePopState();
}

class _ScalePopState extends State<ScalePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1.0,
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.0 - widget.magnitude),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0 - widget.magnitude, end: 1.0),
      weight: 1,
    ),
  ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant ScalePop old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !reduceMotionOf(context)) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
