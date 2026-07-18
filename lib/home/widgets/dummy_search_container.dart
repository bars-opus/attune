import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DummySearchContainer extends StatelessWidget {
  final String hintText;
  final VoidCallback onTap;
  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final bool showBorder;
  final double? elevation;
  final Color? backgroundColor;

  const DummySearchContainer({
    super.key,
    this.hintText = 'Search...',
    required this.onTap,
    this.enabled = true,
    this.padding,
    this.showBorder = true,
    this.elevation,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: backgroundColor ?? colorScheme.surface,
      elevation: elevation ?? 0,
      borderRadius: BorderRadius.circular(30.r),

      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(30.r),
        child: Container(
          padding:
              padding ??
              EdgeInsets.symmetric(
                horizontal: Spacing.lg.w,
                vertical: Spacing.sm.h,
              ),
          decoration: BoxDecoration(
            border:
                showBorder ? Border.all(color: Colors.grey, width: .2) : null,
            borderRadius: BorderRadius.circular(30.r),
          ),
          child: Row(
            children: [
              // Search icon
              Icon(
                Icons.search,
                size: IconSizes.md.h,
                color:
                    enabled
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              Gap(Spacing.md),

              // Hint text
              Expanded(
                child: Text(
                  hintText,
                  style: textTheme.bodyMedium?.copyWith(
                    color:
                        enabled
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
