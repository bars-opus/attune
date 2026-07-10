import 'package:flutter/material.dart';

import 'reduce_motion.dart';

/// Slow breathing glow around a child while [active]. Universal "someone/
/// something is live" indicator — used for a partner-present avatar, but usable
/// anywhere. Calm by design (Spec §3.3): long period, small spread.
class GlowPulse extends StatefulWidget {
  const GlowPulse({
    super.key,
    required this.child,
    required this.active,
    this.color,
    this.maxSpread = 8.0,
  });

  final Widget child;
  final bool active;
  final Color? color;
  final double maxSpread;

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant GlowPulse old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && !reduceMotionOf(context)) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.primary;
    final reduceMotion = reduceMotionOf(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final spread =
            widget.active ? widget.maxSpread * _ctrl.value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.active && !reduceMotion
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45 * _ctrl.value),
                      blurRadius: spread * 1.5,
                      spreadRadius: spread,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
