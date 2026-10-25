import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The sign-in screens' accent (Spec 1 §2.3: text contrast at least 4.5:1).
/// The light theme's primary green (#4F9F3A) reads at only 3.3:1 against
/// white, so light mode uses the palette's own darker green
/// (`primaryDark`, #2F6F22, 6.1:1); dark mode keeps the theme's primary.
Color flowAccent(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.light
      ? theme.appColors.primaryDark
      : theme.colorScheme.primary;
}
