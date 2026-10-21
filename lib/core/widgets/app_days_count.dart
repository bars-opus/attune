import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

/// A count of days the couple's way: a big bold number in primary, with two
/// small words stacked tight beside it — "232 days together", "12 days to
/// go". With [roll] the number rolls up from 0 when it first shows (the
/// budget gauge's timing). Screen readers hear it as one phrase.
class AppDaysCount extends StatelessWidget {
  const AppDaysCount({
    super.key,
    required this.count,
    required this.top,
    required this.bottom,
    this.roll = false,
  });

  final int count;
  final String top;
  final String bottom;
  final bool roll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final big = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: primary,
      height: 1.1,
    );
    final small = theme.textTheme.labelMedium?.copyWith(
      color: primary,
      height: 1.0,
    );
    return Semantics(
      label: '$count $top $bottom',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          roll
              ? AnimatedRollingCounter(
                count: count,
                style: big,
                fromZero: true,
                settleAsText: true,
                duration: const Duration(milliseconds: 700),
                curve: const Cubic(0.05, 0.7, 0.1, 1.0),
              )
              : Text('$count', style: big),
          const Gap(Spacing.sm),
          // The two words, small and tight, left-aligned against the number.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [Text(top, style: small), Text(bottom, style: small)],
          ),
        ],
      ),
    );
  }
}
