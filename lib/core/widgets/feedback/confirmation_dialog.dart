import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/circular_documentation_container.dart';

/// Confirmation dialog types for different risk levels
enum ConfirmationType {
  warning, // High risk (delete, sign out)
  info, // Neutral confirmation
  success, // Positive action confirmation
  destructive, // Irreversible action (delete account)
}

class ConfirmationDialog extends StatelessWidget {
  final ConfirmationType type;
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final bool showCancel;
  final bool dismissible;
  final bool noIcon;

  final IconData? icon;

  const ConfirmationDialog({
    super.key,
    required this.type,
    required this.title,
    required this.message,
    required this.confirmText,
    this.cancelText = 'Cancel',
    required this.onConfirm,
    this.onCancel,
    this.showCancel = true,
    this.dismissible = true,
    this.icon,
    this.noIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: 350.h, // Limit maximum height
        minHeight: 150.h, // Set minimum height
      ),
      child: CircularDocumentationContainer(
        // Custom padding or default from container
        padding: 10.h,
        child: Column(
          // mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header with icon
            if (!noIcon) _buildHeader(context),
            Gap(Spacing.md.h),

            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),

            // Message
            if (message.isNotEmpty)
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            Gap(Spacing.xl.h),

            // Action buttons
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color getIconColor() {
      switch (type) {
        case ConfirmationType.warning:
          return colorScheme.error;
        case ConfirmationType.destructive:
          return colorScheme.error;
        case ConfirmationType.info:
          return colorScheme.primary;
        case ConfirmationType.success:
          return colorScheme.primary;
      }
    }

    IconData getIcon() {
      switch (type) {
        case ConfirmationType.warning:
          return Icons.warning_amber_rounded;
        case ConfirmationType.destructive:
          return Icons.delete_forever_rounded;
        case ConfirmationType.info:
          return Icons.info_outline_rounded;
        case ConfirmationType.success:
          return Icons.check_circle_outline_rounded;
      }
    }

    return Center(
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: getIconColor().withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon ?? getIcon(),
          size: IconSizes.lg.h,
          color: getIconColor(),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Cancel button
        AppButton(
          label: confirmText,
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          elevation: 1,
          size: ButtonSize.small,
          width: double.infinity,
          padding: Spacing.horizontalMd,
          height: 40.h,
          textColor: _getConfirmButtonTextColor(colorScheme),
          customColor: _getConfirmButtonColor(colorScheme),
        ),
        Gap(Spacing.md.h),
        
        if (showCancel) ...[
          AppButton(
            elevation: 0,
            height: 40.h,
            label: cancelText,
            onPressed: () {
              Navigator.of(context).pop();
              onCancel?.call();
            },
            textColor: colorScheme.onBackground,
            padding: Spacing.horizontalMd,
            // variant: ButtonVariant.outline,
            size: ButtonSize.small,
            width: double.infinity,
            // textColor: colorScheme.onSurface,
            customColor: colorScheme.onBackground.withOpacity(.1),
          ),
        ],

        // Confirm button
      ],
    );
  }

  Color _getConfirmButtonColor(ColorScheme colorScheme) {
    switch (type) {
      case ConfirmationType.destructive:
        return colorScheme.error;
      case ConfirmationType.warning:
        return colorScheme.primary;
      case ConfirmationType.info:
        return colorScheme.primary;
      case ConfirmationType.success:
        return colorScheme.primary;
    }
  }

  Color _getConfirmButtonTextColor(ColorScheme colorScheme) {
    switch (type) {
      case ConfirmationType.destructive:
        return colorScheme.onError;
      case ConfirmationType.warning:
        return colorScheme.onErrorContainer;
      case ConfirmationType.info:
        return colorScheme.onPrimary;
      case ConfirmationType.success:
        return colorScheme.onPrimary;
    }
  }

  /// Helper method to show the dialog
  static Future<bool?> show({
    required BuildContext context,
    required ConfirmationType type,
    required String title,
    required String message,
    required String confirmText,
    String cancelText = 'Cancel',
    bool showCancel = true,
    bool dismissible = true,
  }) async {
    final completer = Completer<bool?>();

    await showDialog(
      context: context,
      barrierDismissible: dismissible,
      builder: (context) {
        return ConfirmationDialog(
          type: type,
          title: title,
          message: message,
          confirmText: confirmText,
          cancelText: cancelText,
          showCancel: showCancel,
          dismissible: dismissible,
          onConfirm: () => completer.complete(true),
          onCancel: () => completer.complete(false),
        );
      },
    );

    return completer.future;
  }
}
