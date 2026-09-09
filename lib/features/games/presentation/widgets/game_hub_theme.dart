import 'package:flutter/material.dart';

/// The games hub is dark, whatever the app theme is doing.
///
/// A storefront is its own room. Every tile in here carries a saturated
/// gradient (see GamePalette), and those were chosen against near-black —
/// on a white sheet the same colours read as highlighter rather than as
/// lit. Rather than maintain two palettes, the hub declares one surface
/// and paints itself.
///
/// This is the same decision the Arcade games already made for their
/// boards. It is not "dark mode support"; it is a surface that has one
/// appearance.
class GameHubTheme {
  const GameHubTheme._();

  /// The sheet's ground. Not pure black: a hair of blue keeps the
  /// coloured tiles from vibrating against it the way they do on #000.
  static const surface = Color(0xFF0B0B0F);

  /// Cards and rows that sit ON the ground.
  static const raised = Color(0xFF16161C);

  /// A hairline between sections. Barely there on purpose.
  static const hairline = Color(0xFF24242C);

  static const primaryText = Color(0xFFF4F4F7);
  static const secondaryText = Color(0xFF9A9AA8);
  static const mutedText = Color(0xFF6A6A78);

  /// Wraps a subtree so Material widgets inside pick up dark defaults
  /// rather than inheriting the app's light theme and rendering black
  /// text on a black sheet.
  static Widget wrap({required Widget child}) => Theme(
    data: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        onSurface: primaryText,
        primary: Color(0xFF5EEAD4),
        onPrimary: Color(0xFF032220),
      ),
      dividerColor: hairline,
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: primaryText),
      child: ColoredBox(color: surface, child: child),
    ),
  );
}
