import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/animations/animated_scale_fade.dart';
import 'package:attune/core/widgets/feedback/circular_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// Universal button widget with multiple variants
/// Supports: Primary, Secondary, Outline, Text, Icon, Loading states

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool isLoading;
  final bool isDisabled;
  final Widget? icon;
  final IconData? iconData;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final Color? customColor;
  final TextStyle? customTextStyle;
  final Color? outlineColor;
  final Color? textColor;
  final bool center;
  final IconData? prefixIcon;
  final Color? prefixIconColor;
  final double? elevation;
  final bool animateButton;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.small,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.iconData,
    this.width,
    this.height,
    this.padding,
    this.borderRadius,
    this.customColor,
    this.customTextStyle,
    this.outlineColor,
    this.textColor,
    this.center = true,
    this.animateButton = true,
    this.prefixIcon,
    this.elevation,
    this.prefixIconColor,
  });

  @override
  Widget build(BuildContext context) {
    // Extract theme values from current context
    // These automatically update when theme changes (light/dark mode)
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return animateButton
        ? AnimatedScaleFade(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          child: SizedBox(
            width: width ?? double.infinity,
            height: height ?? _getHeight(size),
            child: _buildButton(context, colorScheme, textTheme),
          ),
        )
        : SizedBox(
          width: width ?? double.infinity,
          height: height ?? _getHeight(size),
          child: _buildButton(context, colorScheme, textTheme),
        );
  }

  Widget _buildButton(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    // Generate button styling based on variant and theme
    final textStyle = _getTextStyle(textTheme, colorScheme);
    final buttonStyle = _getButtonStyle(colorScheme, textStyle);
    final content = _buildContent(context, textStyle);

    // Pattern matching to select correct button type
    // This is more readable than if-else chains
    return switch (variant) {
      // Elevated buttons (primary and secondary variants)
      ButtonVariant.primary || ButtonVariant.secondary => ElevatedButton(
        onPressed: _getOnPressed(),
        style: buttonStyle,
        child: content,
      ),

      // Outlined button (border with transparent fill)
      ButtonVariant.outline => OutlinedButton(
        onPressed: _getOnPressed(),
        style: buttonStyle,
        child: content,
      ),

      // Text button (minimal styling, text only)
      ButtonVariant.text => TextButton(
        onPressed: _getOnPressed(),
        style: buttonStyle,
        child: content,
      ),

      // Custom variant (same as primary but allows color override)
      ButtonVariant.custom => ElevatedButton(
        onPressed: _getOnPressed(),
        style: buttonStyle,
        child: content,
      ),
    };
  }

  Widget _buildContent(BuildContext context, TextStyle textStyle) {
    if (isLoading) {
      return CircularLoadingIndicator();
    }

    return Padding(
      padding: EdgeInsets.only(left: center ? 0 : Spacing.lg),
      child:
          prefixIcon != null
              ? Row(
                children: [
                  Expanded(child: _mainButton(context, textStyle)),
                  Icon(
                    prefixIcon,
                    size: IconSizes.xs.r + 2.r,
                    color:
                        prefixIconColor ??
                        Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              )
              : _mainButton(context, textStyle),
    );
  }

  Widget _mainButton(BuildContext context, TextStyle textStyle) {
    return Row(
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          icon!,
          Gap(Spacing.sm.w),
        ] else if (iconData != null) ...[
          Icon(
            iconData,
            size: _getIconSize(),
            color: textColor ?? _getIconColor(context),
          ),
          Gap(Spacing.sm.w),
        ],
        Flexible(
          child: Text(
            label,
            style: textStyle,
            textScaler: TextScaler.noScaling,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  VoidCallback? _getOnPressed() {
    if (isLoading || isDisabled) return null;
    return onPressed;
  }

  WidgetStateProperty<Color?> _getOverlayColor(ColorScheme colorScheme) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return null;

      if (customColor != null) {
        return _getContrastColor(customColor!).withValues(alpha: 0.20);
      }

      return switch (variant) {
        ButtonVariant.primary => colorScheme.onPrimary.withValues(alpha: 0.20),
        ButtonVariant.secondary => colorScheme.onSecondary.withValues(
          alpha: 0.20,
        ),
        ButtonVariant.outline => colorScheme.primary.withValues(alpha: 0.20),
        ButtonVariant.text => colorScheme.primary.withValues(alpha: 0.20),
        ButtonVariant.custom => colorScheme.primary.withValues(alpha: 0.20),
      };
    });
  }

  Color _getContrastColor(Color baseColor) {
    final brightness = ThemeData.estimateBrightnessForColor(baseColor);
    return brightness == Brightness.dark
        ? Color.lerp(baseColor, Colors.white, 0.3)!
        : Color.lerp(baseColor, Colors.black, 0.3)!;
  }

  ButtonStyle _getButtonStyle(ColorScheme colorScheme, TextStyle textStyle) {
    final backgroundColor = _getBackgroundColor(colorScheme);
    final foregroundColor = _getForegroundColor(colorScheme);
    final side = _getBorderSide(colorScheme);
    final overlayColor = _getOverlayColor(colorScheme);

    final baseStyle = switch (variant) {
      ButtonVariant.outline => OutlinedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: side,
        disabledBackgroundColor: colorScheme.surface.withValues(alpha: 0.12),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        padding: padding ?? _getPadding(size),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadiusTokens.mdAll,
        ),
        elevation: elevation ?? _getElevation(),
        shadowColor: colorScheme.shadow,
        surfaceTintColor: Colors.transparent,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        textStyle: textStyle,
      ),
      _ => ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: colorScheme.surface.withValues(alpha: 0.12),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        padding: padding ?? _getPadding(size),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadiusTokens.mdAll,
          side: side,
        ),
        elevation: elevation ?? _getElevation(),
        shadowColor: colorScheme.shadow,
        surfaceTintColor: Colors.transparent,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        textStyle: textStyle,
      ),
    };

    return baseStyle.copyWith(overlayColor: overlayColor);
  }

  TextStyle _getTextStyle(TextTheme textTheme, ColorScheme colorScheme) {
    final baseStyle = textTheme.labelLarge?.copyWith(
      fontSize: _getFontSize(),
      color: textColor ?? _getTextColor(colorScheme),
    );
    return customTextStyle ?? baseStyle ?? const TextStyle();
  }

  double _getHeight(ButtonSize size) {
    return switch (size) {
      ButtonSize.small => 36,
      ButtonSize.medium => 48,
      ButtonSize.large => 54,
      ButtonSize.xlarge => 60,
    };
  }

  EdgeInsets _getPadding(ButtonSize size) {
    return switch (size) {
      ButtonSize.small => const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      ButtonSize.medium => const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.smMd,
      ),
      ButtonSize.large => const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.md,
      ),
      ButtonSize.xlarge => const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.lg,
      ),
    };
  }

  double _getFontSize() {
    return switch (size) {
      ButtonSize.small => 11,
      ButtonSize.medium => 13,
      ButtonSize.large => 14,
      ButtonSize.xlarge => 15,
    };
  }

  double _getIconSize() {
    return switch (size) {
      ButtonSize.small => 14,
      ButtonSize.medium => 18,
      ButtonSize.large => 20,
      ButtonSize.xlarge => 22,
    };
  }

  double? _getElevation() {
    return switch (variant) {
      ButtonVariant.primary => ElevationTokens.sm,
      ButtonVariant.secondary => ElevationTokens.xs,
      ButtonVariant.outline => ElevationTokens.none,
      ButtonVariant.text => ElevationTokens.none,
      ButtonVariant.custom => ElevationTokens.sm,
    };
  }

  Color _getBackgroundColor(ColorScheme colorScheme) {
    if (customColor != null) return customColor!;

    return switch (variant) {
      ButtonVariant.primary => colorScheme.primary,
      ButtonVariant.secondary => colorScheme.secondary,
      ButtonVariant.outline => Colors.transparent,
      ButtonVariant.text => Colors.transparent,
      ButtonVariant.custom => colorScheme.primary,
    };
  }

  Color _getForegroundColor(ColorScheme colorScheme) {
    if (customColor != null) {
      final brightness = ThemeData.estimateBrightnessForColor(customColor!);
      return brightness == Brightness.dark ? Colors.white : Colors.black;
    }

    return switch (variant) {
      ButtonVariant.primary => colorScheme.onPrimary,
      ButtonVariant.secondary => colorScheme.onSecondary,
      ButtonVariant.outline => colorScheme.primary,
      ButtonVariant.text => colorScheme.primary,
      ButtonVariant.custom => colorScheme.onPrimary,
    };
  }

  Color _getTextColor(ColorScheme colorScheme) {
    if (customColor != null) {
      // Was colorScheme.onBackground — a fixed theme value with no relation
      // to customColor, so text could end up low-contrast (or the wrong way
      // round entirely) depending on theme/customColor combination. Match
      // _getForegroundColor's full black/white contrast estimate instead —
      // this is what the Text widget actually paints with.
      return _getForegroundColor(colorScheme);
    }

    return switch (variant) {
      ButtonVariant.primary => colorScheme.onPrimary,
      ButtonVariant.secondary => colorScheme.onSecondary,
      ButtonVariant.outline => colorScheme.primary,
      ButtonVariant.text => colorScheme.primary,
      ButtonVariant.custom => colorScheme.onPrimary,
    };
  }

  Color _getIconColor(BuildContext context) {
    return _getTextColor(Theme.of(context).colorScheme);
  }

  BorderSide _getBorderSide(ColorScheme colorScheme) {
    return switch (variant) {
      ButtonVariant.primary => BorderSide.none,
      ButtonVariant.secondary => BorderSide.none,
      ButtonVariant.outline => BorderSide(
        color: outlineColor ?? colorScheme.primary,
        width: BorderWidthTokens.thin,
      ),
      ButtonVariant.text => BorderSide.none,
      ButtonVariant.custom => BorderSide.none,
    };
  }
}

enum ButtonVariant { primary, secondary, outline, text, custom }

enum ButtonSize { small, medium, large, xlarge }
