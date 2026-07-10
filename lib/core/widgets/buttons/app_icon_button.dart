import 'package:attune/core/utils/exports/export_screens.dart';

class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final bool isLoading;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  final String? tooltip;
  final double? tooltipVerticalOffset;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.size = 44.0,
    this.iconSize = 24.0,
    this.isLoading = false,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 1.0,
    this.tooltip,
    this.tooltipVerticalOffset,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasSolidBackground =
        backgroundColor != null && backgroundColor!.a > 0;

    final button = Opacity(
      opacity: onPressed != null ? 1.0 : 0.38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: size.r,
            height: size.r,
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.transparent,
              shape: BoxShape.circle,
              border: showBorder
                  ? Border.all(
                      color: borderColor ??
                          colorScheme.outline.withValues(alpha: 0.3),
                      width: borderWidth,
                    )
                  : null,
              boxShadow: [
                if (hasSolidBackground)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4.0,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? CircularLoadingIndicator()
                  : Icon(
                      icon,
                      size: iconSize.r,
                      color: iconColor ?? colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(
        message: tooltip!,
        verticalOffset: tooltipVerticalOffset ?? 24.0,
        waitDuration: const Duration(milliseconds: 500),
        showDuration: const Duration(seconds: 2),
        preferBelow: true,
        child: button,
      );
    }

    return button;
  }
}
