import 'package:flutter/material.dart';

class ShakeTransition extends StatelessWidget {
  const ShakeTransition({
    required this.child,
    this.axis = Axis.horizontal,
    this.offset = 140.0,
    this.curve = Curves.elasticOut,
    this.duration = const Duration(milliseconds: 900),
  });
  final Widget child;
  final Duration duration;
  final double offset;
  final Curve curve;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: curve,
      child: child,
      tween: Tween(begin: 1.0, end: 0.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: axis == Axis.horizontal
              ? Offset(
                  value * offset,
                  0.0,
                )
              : Offset(
                  0.0,
                  value * offset,
                ),
          child: child,
        );
      },
    );
  }
}
