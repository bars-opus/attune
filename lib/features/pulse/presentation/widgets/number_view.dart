// lib/features/pulse/presentation/widgets/number_view.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class NumberView extends StatelessWidget {
  final int overallScore;
  final Map<String, int> dimensions;
  final Map<String, int?> deltas;

  const NumberView({
    super.key,
    required this.overallScore,
    required this.dimensions,
    required this.deltas,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // Large score
        Text(
          '$overallScore',
          style: textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
            fontSize: 72,
          ),
        ),
        Gap(Spacing.sm.h),
        Text('Your relationship pulse this week', style: textTheme.titleMedium),
        Gap(Spacing.xl.h),
        // Dimensions list
        ..._buildDimensionRows(context),
      ],
    );
  }

  List<Widget> _buildDimensionRows(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final dimOrder = [
      ('Communication', dimensions['Communication'] ?? 50),
      ('Connection', dimensions['Connection'] ?? 50),
      ('Conflict Health', dimensions['Conflict Health'] ?? 50),
      ('Alignment', dimensions['Alignment'] ?? 50),
      ('Emotional Safety', dimensions['Emotional Safety'] ?? 50),
    ];

    return dimOrder.map((dim) {
      final label = dim.$1;
      final score = dim.$2;
      final delta = deltas[label];

      Widget deltaWidget;
      if (delta == null) {
        deltaWidget = Text('—', style: textTheme.bodyMedium);
      } else if (delta > 0) {
        deltaWidget = Row(
          children: [
            Icon(Icons.arrow_upward, size: 14, color: Colors.green),
            Text(' +$delta', style: const TextStyle(color: Colors.green)),
          ],
        );
      } else if (delta < 0) {
        deltaWidget = Row(
          children: [
            Icon(Icons.arrow_downward, size: 14, color: Colors.red),
            Text(' $delta', style: const TextStyle(color: Colors.red)),
          ],
        );
      } else {
        deltaWidget = Text('—', style: textTheme.bodyMedium);
      }

      return Padding(
        padding: EdgeInsets.only(bottom: Spacing.md.h),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(label, style: textTheme.bodyMedium),
            ),
            Expanded(
              child: Text(
                score.toString(),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(width: 60, child: deltaWidget),
          ],
        ),
      );
    }).toList();
  }
}
