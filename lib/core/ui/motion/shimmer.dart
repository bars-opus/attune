import 'package:flutter/material.dart';

import 'reduce_motion.dart';

/// A one-directional highlight sweep across [child] while [active]. Generic
/// "this is special right now" sheen — chat's first-message-of-the-day and
/// streak celebration are consumers. Static under reduce-motion / inactive.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.active = true,
    this.period = const Duration(milliseconds: 1600),
    this.highlightColor,
  });

  final Widget child;
  final bool active;
  final Duration period;
  final Color? highlightColor;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.period);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant Shimmer old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && !reduceMotionOf(context)) {
      _ctrl.repeat();
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
    if (!widget.active || reduceMotionOf(context)) return widget.child;
    final highlight = widget.highlightColor ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 - 2 * (1 - t), 0),
              end: Alignment(1.0 - 2 * (1 - t), 0),
              colors: [
                Colors.transparent,
                highlight,
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
