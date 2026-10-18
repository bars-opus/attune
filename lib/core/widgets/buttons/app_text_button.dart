import 'package:attune/core/utils/exports/export_screens.dart';

class AppTextButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? textColor;
  final FontWeight fontWeight;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;
  final TextStyle? textStyle;

  /// Shrink-wrapped by default; a caller that needs a 44 dp target passes
  /// one (Spec 5: BottomSheetHeader).
  final Size minimumSize;

  const AppTextButton({
    super.key,
    this.text = 'Done',
    this.onPressed,
    this.textColor,
    this.fontWeight = FontWeight.bold,
    this.padding,
    this.alignment = Alignment.topRight,
    this.textStyle,
    this.fontSize,
    this.minimumSize = Size.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final effectiveStyle =
        textStyle ??
        textTheme.titleMedium?.copyWith(
          color: textColor ?? colorScheme.primary,
          fontWeight: fontWeight,
          fontSize: fontSize,
        );

    return Align(
      alignment: alignment,
      child: TextButton(
        onPressed:
            onPressed ??
            () {
              Navigator.pop(context);
            },
        style: TextButton.styleFrom(
          padding: padding ?? Spacing.horizontalMd,
          minimumSize: minimumSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(text, style: effectiveStyle),
      ),
    );
  }
}
