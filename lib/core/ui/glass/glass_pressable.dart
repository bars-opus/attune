// The liquid press: a touch squashes the control a little (wider than it is
// tall, like a drop pressed flat) and a spring lets it go with a small
// overshoot. With the system's reduce-motion setting it only dims.
import 'package:flutter/physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
    this.pressedScale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;

  /// How small the control gets at the bottom of a press.
  final double pressedScale;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> with SingleTickerProviderStateMixin {
  // 0 = at rest, 1 = fully pressed; a spring may overshoot either way.
  late final AnimationController _press = AnimationController.unbounded(vsync: this);

  static const _down = SpringDescription(mass: 1, stiffness: 900, damping: 38);
  static const _up = SpringDescription(mass: 1, stiffness: 420, damping: 16);

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _to(double target, SpringDescription spring) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.value = target;
      return;
    }
    _press.animateWith(SpringSimulation(spring, _press.value, target, _press.velocity));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled ? (_) => _to(1, _down) : null,
      onTapUp: _enabled ? (_) => _to(0, _up) : null,
      onTapCancel: _enabled ? () => _to(0, _up) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _to(0, _up);
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _press,
        child: widget.child,
        builder: (context, child) {
          final p = _press.value;
          if (reduceMotion) {
            return Opacity(opacity: 1 - 0.25 * p.clamp(0.0, 1.0), child: child);
          }
          final shrink = 1 - (1 - widget.pressedScale) * p;
          // Squash: a pressed drop spreads sideways a touch.
          final sx = shrink + 0.025 * p;
          final sy = shrink - 0.015 * p;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(sx, sy, 1),
            child: child,
          );
        },
      ),
    );
  }
}
