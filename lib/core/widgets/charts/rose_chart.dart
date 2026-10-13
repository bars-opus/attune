import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// One wedge of a [RoseChart], in one solid colour.
class RoseSlice {
  const RoseSlice({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.color,
    required this.textColor,
  });

  final String label;

  /// How the value reads on the wedge, e.g. "GHS 2K".
  final String valueLabel;
  final double value;
  final Color color;

  /// Readable on [color], for the label inside the wedge.
  final Color textColor;
}

/// [values] biggest first; past [limit], the smallest are gathered into one
/// [otherLabel] slice so the wedges stay wide enough to read.
List<MapEntry<String, double>> topSlices(Map<String, double> values, {int limit = 8, String otherLabel = 'Other'}) {
  final sorted = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length <= limit) return sorted;
  final kept = sorted.take(limit - 1).toList();
  final rest = sorted.skip(limit - 1).fold<double>(0, (sum, e) => sum + e.value);
  return [...kept, MapEntry(otherLabel, rest)];
}

/// A round chart of equal wedges, all the same height, with rounded
/// corners and small gaps around a little hole: a complete circle. Each
/// wedge is one solid colour (what it means is the caller's: paid, not yet
/// paid, ...), with its amount and name inside. Grows in; with reduce
/// motion it simply shows.
class RoseChart extends StatefulWidget {
  const RoseChart({super.key, required this.slices, required this.semanticLabel, this.size = 280});

  final List<RoseSlice> slices;

  /// What the chart is, for screen readers ("Spending by expense"); each
  /// slice's label and value follow it.
  final String semanticLabel;
  final double size;

  @override
  State<RoseChart> createState() => RoseChartState();
}

@visibleForTesting
class RoseChartState extends State<RoseChart> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final CurvedAnimation _eased = CurvedAnimation(parent: _c, curve: const Cubic(0.05, 0.7, 0.1, 1.0));
  List<double> _from = const [];
  List<double> _to = const [];
  bool _started = false;

  /// How far through its current change the chart is, 0..1.
  double get progress => _c.value;

  /// Every wedge is full height; only an empty one is left out.
  List<double> get _reach => [for (final s in widget.slices) s.value > 0 ? 1.0 : 0.0];

  List<double> get _now => [
        for (var i = 0; i < _to.length; i++)
          (i < _from.length ? _from[i] : 0) + (_to[i] - (i < _from.length ? _from[i] : 0)) * _eased.value,
      ];

  void _go() => reduceMotionOf(context) ? _c.value = 1 : _c.forward(from: 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _to = _reach;
    _from = [for (final _ in _to) 0];
    _go();
  }

  @override
  void didUpdateWidget(RoseChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _reach;
    if (next.length == _to.length && [for (var i = 0; i < next.length; i++) next[i] == _to[i]].every((same) => same)) {
      return;
    }
    _from = next.length == _to.length ? _now : [for (final _ in next) 0];
    _to = next;
    _go();
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
    final described = [for (final s in widget.slices) '${s.label} ${s.valueLabel}'].join(', ');
    return Semantics(
      label: '${widget.semanticLabel}: $described',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: RosePainter(
              slices: widget.slices,
              reach: _now,
              valueStyle: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
              labelStyle: theme.textTheme.labelSmall!,
              textDirection: Directionality.of(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a [RoseChart]: equal wedges from the top, clockwise, each grown
/// out to [reach] of the radius (all 1 once in).
class RosePainter extends CustomPainter {
  RosePainter({
    required this.slices,
    required this.reach,
    required this.valueStyle,
    required this.labelStyle,
    required this.textDirection,
  });

  final List<RoseSlice> slices;
  final List<double> reach;
  final TextStyle valueStyle;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const _gap = 4.0;
  static const _corner = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = slices.length;
    if (n == 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final hole = r * 0.12;
    final sweep = 2 * math.pi / n;
    final labelRadius = r * 0.62;
    for (var i = 0; i < n; i++) {
      final k = i < reach.length ? reach[i] : 0.0;
      if (k <= 0) continue;
      final start = -math.pi / 2 + i * sweep;
      _wedge(canvas, c, hole, hole + (r - hole) * k, start, sweep, slices[i].color);
      if (k < 0.75) continue; // labels appear as the wedge grows in
      final mid = start + sweep / 2;
      final maxWidth = math.min(2 * labelRadius * math.sin(math.min(sweep, math.pi) / 2) * 0.9, r * 0.7);
      _layout(slices[i], maxWidth).paint(canvas, c + Offset(math.cos(mid), math.sin(mid)) * labelRadius);
    }
  }

  /// A wedge from [r0] to [r1] with rounded corners: the shape is drawn a
  /// corner's width smaller (less on a short wedge, so rounding never
  /// inflates its size), then filled and stroked with round joins, inside a
  /// layer so a translucent colour is not doubled where fill and stroke meet.
  void _wedge(Canvas canvas, Offset c, double r0, double r1, double start, double sweep, Color color) {
    final corner = math.max(1.0, math.min(_corner, (r1 - r0) / 4));
    final inner = r0 + corner;
    final outer = r1 - corner;
    if (outer <= inner) return;
    final pad = _gap / 2 + corner;
    final padIn = math.min(pad / inner, sweep / 2);
    final padOut = math.min(pad / outer, sweep / 2);
    Offset at(double radius, double angle) => c + Offset(math.cos(angle), math.sin(angle)) * radius;
    final a = at(inner, start + padIn);
    final b = at(outer, start + padOut);
    final d = at(inner, start + sweep - padIn);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: outer), start + padOut, sweep - 2 * padOut, false)
      ..lineTo(d.dx, d.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: inner), start + sweep - padIn, -(sweep - 2 * padIn), false)
      ..close();
    final opaque = color.withValues(alpha: 1);
    canvas.saveLayer(path.getBounds().inflate(corner + 1), Paint()..color = Color.fromRGBO(0, 0, 0, color.a));
    canvas.drawPath(path, Paint()..color = opaque);
    canvas.drawPath(
      path,
      Paint()
        ..color = opaque
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * corner
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  _RoseLabel _layout(RoseSlice s, double maxWidth) {
    TextPainter text(String t, TextStyle style) => TextPainter(
          text: TextSpan(text: t, style: style.copyWith(color: s.textColor)),
          textAlign: TextAlign.center,
          textDirection: textDirection,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth);
    return _RoseLabel(text(s.valueLabel, valueStyle), text(s.label, labelStyle));
  }

  @override
  bool shouldRepaint(RosePainter old) => old.slices != slices || old.reach != reach;
}

/// A wedge's amount over its name, centred on a point.
class _RoseLabel {
  _RoseLabel(this.value, this.name);
  final TextPainter value;
  final TextPainter name;

  double get width => math.max(value.width, name.width);
  double get height => value.height + name.height;

  void paint(Canvas canvas, Offset center) {
    value.paint(canvas, Offset(center.dx - value.width / 2, center.dy - height / 2));
    name.paint(canvas, Offset(center.dx - name.width / 2, center.dy - height / 2 + value.height));
  }
}
