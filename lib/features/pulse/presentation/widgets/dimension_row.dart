// lib/features/pulse/presentation/widgets/dimension_row.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class DimensionRow extends StatelessWidget {
  final String label;
  final int score;
  final int? delta;
  final String confidence;
  final VoidCallback? onTap;

  const DimensionRow({
    super.key,
    required this.label,
    required this.score,
    this.delta,
    required this.confidence,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Row(
            children: [
              // Label and confidence dot
              Row(
                children: [
                  Text(label, style: textTheme.bodyMedium),
                  Gap(Spacing.xs.w),
                  _buildConfidenceDot(context),
                ],
              ),
              const Spacer(),
              // Score and delta
              Row(
                children: [
                  Text(
                    score.toString(),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Gap(Spacing.sm.w),
                  _buildDeltaWidget(context),
                ],
              ),
            ],
          ),
          Gap(Spacing.xs.h),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: _getBarColor(score, colorScheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceDot(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color dotColor;
    if (confidence == 'high' || confidence == 'medium') {
      dotColor = colorScheme.primary;
    } else if (confidence == 'low') {
      dotColor = Colors.orange;
    } else {
      dotColor = colorScheme.onSurface.withOpacity(0.3);
    }

    return GestureDetector(
      onTap: () {
        if (onTap != null) onTap!();
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
      ),
    );
  }

  Widget _buildDeltaWidget(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (delta == null) {
      return Text('—', style: textTheme.bodySmall);
    }

    if (delta! > 0) {
      return Row(
        children: [
          Icon(Icons.arrow_upward, size: 12, color: Colors.green),
          Text(
            ' +${delta!.abs()}',
            style: const TextStyle(color: Colors.green),
          ),
        ],
      );
    } else if (delta! < 0) {
      return Row(
        children: [
          Icon(Icons.arrow_downward, size: 12, color: Colors.red),
          Text(' ${delta}', style: const TextStyle(color: Colors.red)),
        ],
      );
    } else {
      return Text('—', style: textTheme.bodySmall);
    }
  }

  Color _getBarColor(int score, ColorScheme colorScheme) {
    if (score >= 70) return Colors.green;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }
}
