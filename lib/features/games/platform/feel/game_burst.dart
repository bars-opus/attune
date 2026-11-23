import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:flutter/material.dart';

/// Where one ray of a burst is, [progress] of the way through.
///
/// Pure, so the shape of the burst is checked without a canvas. A ray starts
/// short and close in, shoots outward, and its tail catches up as it fades:
/// it is brightest early and gone by the end.
({double inner, double outer, double alpha}) burstRay(
  double progress,
  double radius,
) {
  // A NaN compares false with everything, so it is caught rather than
  // clamped, and read as "finished".
  final t = progress.isNaN ? 1.0 : progress.clamp(0.0, 1.0);
  final eased = 1 - math.pow(1 - t, 3).toDouble();

  final outer = radius * (0.35 + 0.65 * eased);
  final inner = radius * (0.2 + 0.7 * eased * eased);
  final alpha = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;

  return (inner: inner, outer: outer, alpha: alpha.clamp(0.0, 1.0));
}

/// Draws the rays. Public fields, so a test reads them directly.
class GameBurstPainter extends CustomPainter {
  GameBurstPainter({
    required this.progress,
    required this.color,
    this.rays = 9,
    this.strokeWidth = 2.5,
  });

  final double progress;
  final Color color;
  final int rays;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || rays <= 0) return;

    final ray = burstRay(progress, size.shortestSide / 2);
    if (ray.alpha <= 0.01) return;

    final paint =
        Paint()
          ..color = color.withValues(alpha: ray.alpha)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    final centre = size.center(Offset.zero);

    for (var i = 0; i < rays; i++) {
      final angle = 2 * math.pi * i / rays - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + direction * ray.inner,
        centre + direction * ray.outer,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GameBurstPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.rays != rays ||
      old.strokeWidth != strokeWidth;
}

/// A short spark burst that plays once each time [count] goes up.
///
/// It is an event, not a state: it runs, stops, and schedules nothing more.
/// Under the OS reduce-motion setting it does not run at all.
class GameBurst extends StatefulWidget {
  const GameBurst({
    super.key,
    required this.count,
    required this.color,
    this.size = 72,
    this.rays = 9,
  });

  /// Raise this to play the burst.
  final int count;

  final Color color;
  final double size;
  final int rays;

  @override
  State<GameBurst> createState() => _GameBurstState();
}

class _GameBurstState extends State<GameBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GameMotion.burst,
  );

  @override
  void didUpdateWidget(GameBurst old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count && !reduceMotionOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder:
              (context, _) => CustomPaint(
                painter: GameBurstPainter(
                  progress: _controller.value,
                  color: widget.color,
                  rays: widget.rays,
                ),
              ),
        ),
      ),
    );
  }
}
