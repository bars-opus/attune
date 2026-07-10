// lib/core/extensions/snackbar_extensions.dart
import 'package:flutter/material.dart';
import 'package:attune/core/widgets/feedback/snackbar_widget.dart';

extension LocalizedSnackbar on BuildContext {
  void showSuccessSnackbar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    Snackbar.success(this, message, backgroundColor: backgroundColor);
  }

  void showErrorSnackbar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    Snackbar.error(this, message, actionLabel: actionLabel, onAction: onAction);
  }

  void showWarningSnackbar(String message) {
    if (!mounted) return;
    Snackbar.warning(this, message);
  }

  void showInfoSnackbar(String message) {
    if (!mounted) return;
    Snackbar.info(this, message);
  }

  void showLoadingSnackbar(String message) {
    if (!mounted) return;
    Snackbar.loading(this, message);
  }

  void hideSnackbar() {
    if (!mounted) return;
    Snackbar.hide(this);
  }
}
