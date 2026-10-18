import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/charts/app_pie_chart.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../domain/expense_view.dart';
import '../../domain/planning_money.dart';

/// What the money went on at a glance: one solid colour per wedge — paid,
/// not yet paid, counted, and what's left of the budget — with its key
/// centred underneath. Built by [planningBudgetChart].
class PlanningSpendChart extends StatelessWidget {
  const PlanningSpendChart({super.key, required this.chart});
  final PlanningChart chart;

  static int _wholeUnit(String currency) {
    var n = 1;
    for (var d = planningCurrencyDigits(currency); d > 0; d--) {
      n *= 10;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color fill(PlanningChartSlice k) => switch (k) {
      PlanningChartSlice.paid || PlanningChartSlice.counted => scheme.primary,
      PlanningChartSlice.unpaid => scheme.primary.withValues(alpha: 0.18),
      PlanningChartSlice.left => scheme.outlineVariant, // visible on the card
    };
    Color ink(PlanningChartSlice k) => switch (k) {
      PlanningChartSlice.paid || PlanningChartSlice.counted => scheme.onPrimary,
      PlanningChartSlice.unpaid => scheme.primary,
      PlanningChartSlice.left => scheme.onSurface,
    };
    final kinds = {for (final s in chart.slices) s.kind};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: LayoutBuilder(
            builder:
                (context, c) => AppPieChart(
                  size: c.maxWidth.clamp(0, 260).toDouble(),
                  semanticLabel: 'Spending breakdown in ${chart.currency}',
                  slices: [
                    for (final s in chart.slices)
                      PieSlice(
                        label: s.label,
                        value: s.value,
                        valueLabel: formatPlanningMoneyCompact(
                          (s.value * _wholeUnit(chart.currency)).round(),
                          chart.currency,
                        ),
                        color: fill(s.kind),
                        textColor: ink(s.kind),
                      ),
                  ],
                ),
          ),
        ),
        const Gap(Spacing.lg),
        // Full width, so the key centres under the chart; only the kinds the
        // chart has.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Spacing.md,
          runSpacing: Spacing.xs,
          children: [
            if (kinds.contains(PlanningChartSlice.paid))
              _LegendDot(color: fill(PlanningChartSlice.paid), label: 'Paid'),
            if (kinds.contains(PlanningChartSlice.unpaid))
              _LegendDot(
                color: fill(PlanningChartSlice.unpaid),
                label: 'Not yet paid',
              ),
            if (kinds.contains(PlanningChartSlice.counted))
              _LegendDot(
                color: fill(PlanningChartSlice.counted),
                label: 'Counted',
              ),
            if (kinds.contains(PlanningChartSlice.left))
              _LegendDot(
                color: fill(PlanningChartSlice.left),
                label: 'Left in budget',
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const Gap(Spacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
