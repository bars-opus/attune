// lib/features/games/this_or_that/presentation/widgets/match_indicator.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class MatchIndicator extends StatelessWidget {
  final bool isMatch;
  final Animation<double>? animation;

  const MatchIndicator({
    super.key,
    required this.isMatch,
    this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isMatch) {
      return AnimatedBuilder(
        animation: animation ?? const AlwaysStoppedAnimation(1.0),
        builder: (context, child) {
          final opacity = (animation?.value ?? 1.0).clamp(0.0, 1.0);
          final flashOpacity = opacity < 0.5 ? opacity * 2 : (1.0 - opacity) * 2;
          
          return Container(
            padding: EdgeInsets.all(Spacing.md.w),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1 * flashOpacity),
              borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: colorScheme.primary),
                Gap(Spacing.sm.w),
                Text(
                  'You both picked the same! 🎉',
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.compare_arrows, color: colorScheme.onSurface.withOpacity(0.6)),
          Gap(Spacing.sm.w),
          Text(
            'Different picks this time 😄',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
