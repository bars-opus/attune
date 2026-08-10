// lib/core/widgets/app_filter_chip.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_packages.dart';

class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;

  /// Nullable like ChoiceChip's own onSelected: passing null (e.g. a
  /// TagPicker chip once the selection cap is reached) disables the chip —
  /// greyed out, not tappable — rather than requiring the parent to no-op.
  final ValueChanged<bool>? onSelected;
  final Color? selectedColor;
  final Color? backgroundColor;

  final Color? labelColor;
  final Color? selectedLabelColor;
  final double? fontSize;
  final double? borderWidth;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final IconData? avatarIcon;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.selectedColor,
    this.backgroundColor,
    this.labelColor,
    this.selectedLabelColor,
    this.fontSize,
    this.borderWidth,
    this.padding,
    this.borderRadius,
    this.avatarIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final effectiveSelectedColor = selectedColor ?? colorScheme.primary;
    final effectiveBackgroundColor =
        backgroundColor ?? colorScheme.outline.withOpacity(.3);
    return ChoiceChip(
      avatar:
          avatarIcon == null
              ? null
              : Icon(
                avatarIcon,
                size: 16.r,
                color:
                    selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface.withValues(alpha: 0.5),
              ),
      label: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color:
              selected
                  ? (selectedLabelColor ?? colorScheme.onPrimary)
                  : (labelColor ?? colorScheme.onSurface),
          fontSize: fontSize ?? FontSizeTokens.xs,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      selected: selected,
      showCheckmark: avatarIcon == null,
      checkmarkColor: selectedLabelColor ?? colorScheme.onPrimary,
      onSelected: onSelected,
      // ChoiceChip reserves Material's ~48dp minimum tap-target height by
      // default regardless of `padding` above — shrinkWrap removes that
      // floor so wrapped rows of chips (TagPickerRow) sit as close as the
      // padding/runSpacing actually specify, instead of extra invisible
      // vertical space between rows.
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: Spacing.sm.w,
            vertical: Spacing.xs.h,
          ),
      labelPadding: EdgeInsets.symmetric(horizontal: Spacing.xs.w),
      backgroundColor: effectiveBackgroundColor,
      selectedColor: effectiveSelectedColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          // onSurface is a content/text color, not a border one — in dark
          // mode it's near-white (DarkColors.textPrimary), so an unselected
          // chip got a near-white border. outline is the token every other
          // bordered surface in this app already uses (app_theme.dart's
          // dividerTheme/inputDecorationTheme) and is tuned per-brightness.
          color: selected ? colorScheme.primary : colorScheme.outline,
          width: borderWidth?.w ?? .1,
        ),
        borderRadius:
            borderRadius ?? BorderRadius.circular(BorderRadiusTokens.full.r),
      ),
      elevation: 0,
      pressElevation: 0,
    );
  }
}
