import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// A rounded three-quarter arc filling toward a target, with a headline and
/// a caption in the middle ("GHS 70.00 left" / "of GHS 100.00"). The track
/// is a light shade of the fill, like the app's progress bars; [over] turns
/// the fill to the error colour. Eases to new values; with reduce motion it
/// simply shows them.
class ArcGauge extends StatefulWidget {
  const ArcGauge({
    super.key,
    required this.fraction,
    required this.headline,
    required this.caption,
    required this.semanticLabel,
    this.over = false,
    this.size = 200,
    this.headlineBuilder,
  });

  /// How full, 0..1 (clamped).
  final double fraction;
  final String headline;

  /// Draws the headline in the gauge's headline style (a rolling amount);
  /// [headline] is still what screen readers hear. Plain text when null.
  final Widget Function(TextStyle? style)? headlineBuilder;
  final String caption;
  final String semanticLabel;
  final bool over;
  final double size;

  static double clampFraction(double f) => f.isNaN ? 0 : f.clamp(0.0, 1.0).toDouble();

  @override
  State<ArcGauge> createState() => ArcGaugeState();
}

@visibleForTesting
class ArcGaugeState extends State<ArcGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final CurvedAnimation _eased = CurvedAnimation(parent: _c, curve: const Cubic(0.05, 0.7, 0.1, 1.0));
  double _from = 0;
  double _to = 0;
  bool _started = false;

  /// The fraction on screen right now.
  double get shown => _from + (_to - _from) * _eased.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _to = ArcGauge.clampFraction(widget.fraction);
    if (reduceMotionOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(ArcGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = ArcGauge.clampFraction(widget.fraction);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = widget.over ? scheme.error : scheme.primary;
    return Semantics(
      label: '${widget.semanticLabel}: ${widget.headline}, ${widget.caption}',
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size * 0.86, // the arc's open bottom needs no room
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => CustomPaint(
            painter: ArcGaugePainter(value: shown, fill: fill, track: fill.withValues(alpha: 0.18)),
            child: child,
          ),
          child: Padding(
            padding: EdgeInsets.only(top: widget.size * 0.06),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                () {
                  final style = theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: widget.over ? scheme.error : null,
                  );
                  return widget.headlineBuilder?.call(style) ??
                      Text(widget.headline, textAlign: TextAlign.center, style: style);
                }(),
                Text(widget.caption,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints an [ArcGauge]: a 270° track opening at the bottom, and the fill.
class ArcGaugePainter extends CustomPainter {
  ArcGaugePainter({required this.value, required this.fill, required this.track});

  final double value;
  final Color fill;
  final Color track;

  static const _start = 0.75 * math.pi; // bottom-left
  static const _sweep = 1.5 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.width / 2), radius: size.width / 2 - stroke / 2);
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, paint(track));
    if (value > 0) canvas.drawArc(rect, _start, _sweep * value, false, paint(fill));
  }

  @override
  bool shouldRepaint(ArcGaugePainter old) => old.value != value || old.fill != fill || old.track != track;
}
