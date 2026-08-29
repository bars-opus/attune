// lib/features/pulse/presentation/widgets/trend_chart.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class TrendChart extends StatelessWidget {
  final List<PulseScore> history;

  const TrendChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Ensure we have exactly 4 weeks (pad with nulls if needed)
    final List<PulseScore?> weeks = List.filled(4, null);
    for (int i = 0; i < history.length && i < 4; i++) {
      weeks[3 - i] = history[i];
    }

    final maxScore = weeks
        .where((w) => w != null)
        .map((w) => w!.overallScore)
        .fold(0, (a, b) => a > b ? a : b);
    final chartHeight = 120.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '4-week trend',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),

            GestureDetector(
              onTap: () {},
              child: Row(
                children: [
                  Text(
                    'Learn more',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  Gap(Spacing.md.w),
                  Icon(
                    Icons.chevron_right,
                    size: IconSizes.md.h,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(
          height: chartHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(4, (index) {
              final week = weeks[index];
              final isCurrentWeek = index == 3;
              final barHeight =
                  week != null
                      ? (week.overallScore / maxScore) * chartHeight
                      : 0;
              final barColor =
                  isCurrentWeek
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest;

              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (week != null)
                    Text(
                      '${week.overallScore}',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCurrentWeek ? colorScheme.primary : null,
                      ),
                    ),
                  Gap(Spacing.xs.h),
                  Container(
                    width: 30.w,
                    height: 10.h,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.sm.r,
                      ),
                    ),
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    _getWeekLabel(index, week),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  String _getWeekLabel(int index, PulseScore? week) {
    if (week != null) {
      return '${week.weekEnding.day}/${week.weekEnding.month}';
    }
    switch (index) {
      case 0:
        return 'Week 1';
      case 1:
        return 'Week 2';
      case 2:
        return 'Week 3';
      case 3:
        return 'Current';
      default:
        return '';
    }
  }
}
