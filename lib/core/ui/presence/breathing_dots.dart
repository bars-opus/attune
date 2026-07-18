import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../motion/reduce_motion.dart';

/// A row of dots that pulse in a staggered wave — a generic "someone is doing
/// something" indicator (chat typing is the first consumer). Loops while
/// mounted. Under OS reduce-motion the dots are static.
class BreathingDots extends StatefulWidget {
  const BreathingDots({
    super.key,
    this.count = 3,
    this.size = 7,
    this.color,
    this.period = kBreathingDotsPeriod,
  });

  final int count;
  final double size;
  final Color? color;
  final Duration period;

  @override
  State<BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<BreathingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.period);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotionOf(context)) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _opacityFor(int index) {
    if (reduceMotionOf(context)) return 0.6;
    // Stagger each dot by a fraction of the period.
    final phase = (_ctrl.value + index / widget.count) % 1.0;
    // Triangle wave 0.3 -> 1.0 -> 0.3
    final wave = 1.0 - (phase - 0.5).abs() * 2;
    return 0.3 + 0.7 * wave;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.count, (i) {
            return Padding(
              key: ValueKey('breathing_dot_$i'),
              padding: EdgeInsets.symmetric(horizontal: widget.size * 0.25),
              child: Opacity(
                opacity: _opacityFor(i),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
