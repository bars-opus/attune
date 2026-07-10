// lib/features/quiz/presentation/widgets/spectrum_bar.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';



class SpectrumBar extends StatelessWidget {
  final String label;
  final int percentage;
  final Color color;
  final Animation<double> animation;

  const SpectrumBar({
    super.key,
    required this.label,
    required this.percentage,
    required this.color,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Label column
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Gap(Spacing.sm.w),
        // Bar column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Animated bar
              ClipRRect(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                child: LinearProgressIndicator(
                  value: animation.value,
                  minHeight: 24,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: color,
                ),
              ),
              Gap(Spacing.xs.h),
              // Percentage text
              AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final currentPercentage = (percentage * animation.value).round();
                  return Text(
                    '$currentPercentage%',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
