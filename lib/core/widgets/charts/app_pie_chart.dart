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
/// Changes animate; with reduce motion they land at once.
class AppPieChart extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<double>(0, (sum, s) => sum + (s.value > 0 ? s.value : 0));
    final described = [for (final s in slices) '${s.label} ${s.valueLabel}'].join(', ');
    return Semantics(
      label: '$semanticLabel: $described',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
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
    );
  }
}
