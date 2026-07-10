// lib/features/pulse/presentation/widgets/visualisation_switcher.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VisualisationSwitcher extends ConsumerWidget {
  final String currentVisualisation;
  final Function(String) onChanged;

  const VisualisationSwitcher({
    super.key,
    required this.currentVisualisation,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption('ring', Icons.circle_outlined, 'Ring', context),
          _buildOption('radar', Icons.auto_awesome, 'Radar', context),
          _buildOption('number', Icons.numbers, 'Number', context),
        ],
      ),
    );
  }

  Widget _buildOption(
    String value,
    IconData icon,
    String label,
    BuildContext context,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = currentVisualisation == value;

    return GestureDetector(
      onTap: () {
        onChanged(value);
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.sm.h,
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primary.withOpacity(0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.6),
            ),
            Gap(Spacing.xs.w),
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
