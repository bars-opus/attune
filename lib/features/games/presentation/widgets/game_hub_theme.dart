import 'package:attune/core/ui/neon/neon_quality.dart';
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
  /// How much light the games may spend here.
  ///
  /// ATTUNE_THESIS §6.10 makes performance budgets on representative
  /// Ghanaian hardware a LAUNCH GATE, and NeonQuality exists to honour
  /// it. The final review found the mechanism was complete, tested, and
  /// obeyed by every consumer -- and installed nowhere, so every device
  /// silently took neonQualityOf's fallback. A guard nothing declares is
  /// a facility, not a guard.
  ///
  /// Hardcoded to [NeonQuality.glow] deliberately: picking a tier from
  /// the device is a measurement task that the spec defers until there
  /// is a real device to measure on (§5.1). What this does is make the
  /// SEAM real, so that change is one line here rather than a hunt for
  /// where it should have gone.
  static const NeonQuality quality = NeonQuality.glow;

  static Widget wrap({required Widget child}) => NeonQualityScope(
    quality: quality,
    child: Theme(
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
    ),
  );
}
