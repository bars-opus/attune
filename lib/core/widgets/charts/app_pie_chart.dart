import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One slice of an [AppPieChart], in one solid colour.
class PieSlice {
  const PieSlice({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.color,
    required this.textColor,
  });

  final String label;

  /// How the value reads on the slice, e.g. "GHS2.5K".
  final String valueLabel;
  final double value;
  final Color color;

  /// Readable on [color], for the label inside the slice.
  final Color textColor;
}

/// [values] biggest first; past [limit], the smallest are gathered into one
/// [otherLabel] slice so the slices stay wide enough to read.
List<MapEntry<String, double>> topSlices(Map<String, double> values, {int limit = 8, String otherLabel = 'Other'}) {
  final sorted = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.length <= limit) return sorted;
  final kept = sorted.take(limit - 1).toList();
  final rest = sorted.skip(limit - 1).fold<double>(0, (sum, e) => sum + e.value);
  return [...kept, MapEntry(otherLabel, rest)];
}

/// The app's pie chart (fl_chart): each slice its share of the whole, in its
/// own colour, from the top, with thin separators. Slices of [labelShare]
/// or more carry their amount and name; smaller ones stay unlabelled.
/// It sweeps in clockwise from the top when it first shows, as ArcGauge
/// fills; later changes animate in place. With reduce motion both land at
/// once.
class AppPieChart extends StatefulWidget {
  const AppPieChart({
    super.key,
    required this.slices,
    required this.semanticLabel,
    this.size = 260,
    this.labelShare = 0.08,
  });

  final List<PieSlice> slices;

  /// What the chart is, for screen readers ("Spending by expense"); each
  /// slice's label and value follow it.
  final String semanticLabel;
  final double size;
  final double labelShare;

  @override
  State<AppPieChart> createState() => AppPieChartState();
}

@visibleForTesting
class AppPieChartState extends State<AppPieChart> with SingleTickerProviderStateMixin {
  // ArcGauge's timing and curve, so the two read as one family.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final CurvedAnimation _eased = CurvedAnimation(parent: _c, curve: const Cubic(0.05, 0.7, 0.1, 1.0));
  bool _started = false;

  /// How much of the pie is drawn, 0 to 1, clockwise from the top.
  double get revealed => _eased.value;

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
  void dispose() {
    _eased.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slices = widget.slices;
    final size = widget.size;
    final labelShare = widget.labelShare;
    final semanticLabel = widget.semanticLabel;
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (sum, s) => sum + (s.value > 0 ? s.value : 0));
    final described = [for (final s in slices) '${s.label} ${s.valueLabel}'].join(', ');
    return Semantics(
      label: '$semanticLabel: $described',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _c,
          // A widening wedge from the top shows the pie as it sweeps round;
          // once it is all there, no clip at all.
          builder: (context, pie) => revealed >= 1
              ? pie!
              : ClipPath(
                  key: const ValueKey('app-pie-chart-sweep'),
                  clipper: _SweepClipper(revealed),
                  child: pie,
                ),
          child: PieChart(
          PieChartData(
            startDegreeOffset: -90,
            centerSpaceRadius: 0,
            sectionsSpace: 2,
            pieTouchData: PieTouchData(enabled: false),
            sections: [
              for (final s in slices)
                PieChartSectionData(
                  value: s.value,
                  color: s.color,
                  radius: size / 2,
                  showTitle: total > 0 && s.value / total >= labelShare,
                  title: '${s.valueLabel}\n${s.label}',
                  titlePositionPercentageOffset: 0.62,
                  titleStyle: theme.textTheme.labelMedium?.copyWith(
                    color: s.textColor,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
            ],
          ),
          swapAnimationDuration: reduceMotionOf(context) ? Duration.zero : const Duration(milliseconds: 400),
          swapAnimationCurve: Curves.easeOutCubic,
          ),
        ),
      ),
    );
  }
}

/// The part of a circle from twelve o'clock round to [fraction] of a turn.
class _SweepClipper extends CustomClipper<Path> {
  const _SweepClipper(this.fraction);
  final double fraction;

  @override
  Path getClip(Size size) {
    final centre = size.center(Offset.zero);
    // Past the corners, so the slices' edges are never shaved.
    final r = size.longestSide;
    return Path()
      ..moveTo(centre.dx, centre.dy)
      ..arcTo(Rect.fromCircle(center: centre, radius: r), -math.pi / 2, 2 * math.pi * fraction, false)
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper old) => old.fraction != fraction;
}
