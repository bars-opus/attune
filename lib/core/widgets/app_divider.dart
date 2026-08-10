// lib/core/widgets/app_divider.dart
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// Universal divider widget with consistent styling
///
/// Features:
/// - Responsive sizing with design tokens
/// - Theme-aware colors
/// - Multiple variants (full, inset, middle)
/// - Customizable thickness and spacing
/// - Consistent across the entire app
class AppDivider extends StatelessWidget {
  final DividerVariant variant;
  final Color? color;
  final double? thickness;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double? indent;
  final double? endIndent;
  final Axis? direction;

  const AppDivider({
    super.key,
    this.variant = DividerVariant.full,
    this.color,
    this.thickness,
    this.height,
    this.padding,
    this.indent,
    this.endIndent,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dividerColor = color ?? colorScheme.outline;
    final dividerThickness = thickness ?? 0.5;
    final dividerHeight = height ?? (direction == Axis.horizontal ? 1.h : 1.w);

    Widget divider =
        direction == Axis.horizontal
            ? Divider(
              color: dividerColor,
              thickness: dividerThickness,
              height: dividerHeight,
              indent: _getIndent(variant, indent),
              endIndent: _getEndIndent(variant, endIndent),
            )
            : VerticalDivider(
              color: dividerColor,
              thickness: dividerThickness,
              width: dividerHeight,
              indent: _getIndent(variant, indent),
              endIndent: _getEndIndent(variant, endIndent),
            );

    // Add padding if specified

    return Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(vertical: Spacing.sm, horizontal: Spacing.sm),
      child: divider,
    );
  }

  double? _getIndent(DividerVariant variant, double? customIndent) {
    if (customIndent != null) return customIndent;

    return switch (variant) {
      DividerVariant.full => null,
      DividerVariant.inset => Spacing.lg.w,
      DividerVariant.middle => Spacing.xl.w,
      DividerVariant.none => 0.0,
    };
  }

  double? _getEndIndent(DividerVariant variant, double? customEndIndent) {
    if (customEndIndent != null) return customEndIndent;

    return switch (variant) {
      DividerVariant.full => null,
      DividerVariant.inset => Spacing.lg.w,
      DividerVariant.middle => Spacing.xl.w,
      DividerVariant.none => 0.0,
    };
  }
}

/// Divider style variants
enum DividerVariant {
  full, // Full width/height
  inset, // Inset on both sides (common for lists)
  middle, // More inset (for centered content)
  none, // No inset (0 on both sides)
}
