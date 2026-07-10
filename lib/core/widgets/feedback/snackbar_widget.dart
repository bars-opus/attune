// lib/core/widgets/snackbar/snackbar_utils.dart
import 'package:attune/core/utils/exports/export_screens.dart';

/// Snackbar types for different use cases
enum SnackbarType { success, error, warning, info, loading }

/// Universal snackbar utility
class Snackbar {
  static const Duration _defaultDuration = Duration(seconds: 4);
  static const Duration _longDuration = Duration(seconds: 6);
  static const Duration _shortDuration = Duration(seconds: 2);

  /// Show a snackbar with optional action button
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show({
    required BuildContext context,
    required String message,
    SnackbarType type = SnackbarType.info,
    String? actionLabel,
    VoidCallback? onActionPressed,
    Duration? duration,
    bool showIcon = true,
    bool dismissible = true,
    EdgeInsetsGeometry? margin,
    double? elevation,
    ShapeBorder? shape,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    SnackBarAction? customAction,
    Color? backgroundColor,
    Color? textColor,
    Color? actionTextColor,
  }) {
    // Close any existing snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Determine colors based on type
    final Color bgColor =
        backgroundColor ?? _getBackgroundColor(type, colorScheme);
    final Color txtColor = textColor ?? _getTextColor(type, colorScheme);
    final Color actColor =
        actionTextColor ?? _getActionColor(type, colorScheme);

    // Determine duration
    final Duration finalDuration = duration ?? _getDuration(type);

    final snackBar = SnackBar(
      content: _buildContent(
        type: type,
        message: message,
        textColor: txtColor,
        showIcon: showIcon,
        context: context,
        textTheme: theme.textTheme,
        duration: finalDuration,
      ),
      backgroundColor: bgColor,
      duration: finalDuration,
      behavior: behavior,
      margin: margin ?? const EdgeInsets.all(8),
      elevation: elevation ?? 0,
      shape:
          shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      action:
          customAction ??
          (actionLabel != null && type != SnackbarType.loading
              ? SnackBarAction(
                label: actionLabel,
                onPressed: onActionPressed ?? () {},
                textColor: actColor,
              )
              : null),
      dismissDirection:
          dismissible ? DismissDirection.horizontal : DismissDirection.none,
      showCloseIcon: dismissible && type != SnackbarType.loading,
      closeIconColor: txtColor.withValues(alpha: 0.7),
    );

    return ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  // ==================== CONTENT BUILDER ====================

  static Widget _buildContent({
    required SnackbarType type,
    required String message,
    required Color textColor,
    required bool showIcon,
    required BuildContext context,
    required TextTheme textTheme,
    required Duration duration,
  }) {
    return type == SnackbarType.loading
        ? _buildLeadingWidget(
          type,
          textColor,
          showIcon,
          context,
          duration,
          message,
        )
        : Row(
          children: [
            // Icon or loading indicator
            _buildLeadingWidget(
              type,
              textColor,
              showIcon,
              context,
              duration,
              message,
            ),

            const Gap(12),

            // Message text
            Expanded(
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  // fontWeight: FontWeight.w600, // Bold for prominence
                ),

                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
  }

  static Widget _buildLeadingWidget(
    SnackbarType type,
    Color textColor,
    bool showIcon,
    BuildContext context,
    Duration duration,
    String message,
  ) {
    if (!showIcon) return const Gap(0);

    switch (type) {
      case SnackbarType.loading:
        return AppleVerificationAnimation(
          size: 20,
          message: message,
          verificationDuration: duration,
        );
      default:
        final icon = _getIcon(type);
        if (icon != null) {
          return Icon(icon, color: textColor, size: IconSizes.lg.r);
        }
        return const Gap(0);
    }
  }

  // ==================== UPDATED GET ICON METHOD ====================

  static IconData? _getIcon(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return Icons.check_circle;
      case SnackbarType.error:
        return Icons.error_outline;
      case SnackbarType.warning:
        return Icons.warning;
      case SnackbarType.info:
        return Icons.info_outline;
      case SnackbarType.loading:
        return null; // We use CircularProgressIndicator instead
    }
  }

  // ==================== QUICK HELPERS ====================

  /// Success snackbar (green)
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    Color? backgroundColor,
  }) {
    show(
      context: context,
      message: message,
      type: SnackbarType.success,
      actionLabel: actionLabel,
      onActionPressed: onAction,
      duration: duration,
      backgroundColor: backgroundColor,
    );
  }

  /// Error snackbar (red)
  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      type: SnackbarType.error,
      actionLabel: actionLabel,
      onActionPressed: onAction,
      duration: duration ?? _longDuration,
    );
  }

  /// Warning snackbar (orange/yellow)
  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      type: SnackbarType.warning,
      actionLabel: actionLabel,
      onActionPressed: onAction,
      duration: duration,
    );
  }

  /// Info snackbar (blue)
  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      type: SnackbarType.info,
      actionLabel: actionLabel,
      onActionPressed: onAction,
      duration: duration,
    );
  }

  /// Loading snackbar (indeterminate)
  static void loading(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      type: SnackbarType.loading,
      actionLabel: actionLabel,
      onActionPressed: onAction,
      duration: duration ?? const Duration(minutes: 1),
      dismissible: false,
    );
  }

  // ==================== PRIVATE HELPERS ====================

  static Color _getBackgroundColor(SnackbarType type, ColorScheme scheme) {
    switch (type) {
      case SnackbarType.success:
        return scheme.primaryContainer;
      case SnackbarType.error:
        return scheme.errorContainer;
      case SnackbarType.warning:
        return Color.lerp(scheme.errorContainer, scheme.primaryContainer, 0.5)!;
      case SnackbarType.info:
        return scheme.primary;
      case SnackbarType.loading:
        return scheme.surfaceContainerHighest;
    }
  }

  static Color _getTextColor(SnackbarType type, ColorScheme scheme) {
    switch (type) {
      case SnackbarType.success:
        return scheme.onPrimaryContainer;
      case SnackbarType.error:
        return scheme.onErrorContainer;
      case SnackbarType.warning:
        return scheme.onErrorContainer;
      case SnackbarType.info:
        return scheme.surface;
      case SnackbarType.loading:
        return scheme.onSurfaceVariant;
    }
  }

  static Color _getActionColor(SnackbarType type, ColorScheme scheme) {
    switch (type) {
      case SnackbarType.success:
        return scheme.primary;
      case SnackbarType.error:
        return scheme.error;
      case SnackbarType.warning:
        return scheme.error;
      case SnackbarType.info:
        return scheme.primary;
      case SnackbarType.loading:
        return scheme.primary;
    }
  }

  static Duration _getDuration(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return _defaultDuration;
      case SnackbarType.error:
        return _longDuration;
      case SnackbarType.warning:
        return _defaultDuration;
      case SnackbarType.info:
        return _shortDuration;
      case SnackbarType.loading:
        return const Duration(minutes: 1); // Override manually
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Hide current snackbar
  static void hide(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// Clear all snackbars
  static void clear(BuildContext context) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  /// Show a snackbar with a custom widget
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> custom({
    required BuildContext context,
    required Widget content,
    SnackBarAction? action,
    Duration duration = _defaultDuration,
    Color? backgroundColor,
    double? elevation,
    ShapeBorder? shape,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: content,
      backgroundColor: backgroundColor,
      duration: duration,
      behavior: behavior,
      elevation: elevation,
      shape: shape,
      action: action,
    );

    return ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
