import 'package:flutter/material.dart';

// =============================================================================
// CLASS: LightColors
// =============================================================================
class LightColors {
  // ================= PRIMARY COLOR PALETTE =================
  static const Color primary = Color(0xFF4F9F3A);
  static const Color appColor = Color(0xFF4F9F3A);

  static const Color primaryDark = Color(0xFF2F6F22);
  static const Color primaryLight = Color(0xFFB6FD9D);

  // ================= NEUTRAL COLOR PALETTE =================
  static const Color black = Color(0xFF1d1d1f); // Apple near-black ink
  static const Color darkGrey = Color(0xFF3a3a3c);
  static const Color grey = Color(0xFF6e6e73); // Apple secondary text
  static const Color lightGrey = Color(0xFFd2d2d7); // Apple hairline
  static const Color white = Color(0xFFFFFFFF);

  // ================= FOREGROUND COLOR PALETTE =================
  // Used as primaryContainer in ColorScheme — light tint of primary
  static const Color foreground = Color(0xFFECFFE6);
  static const Color foregroundDark = Color(0xFFBDBDBD);
  static const Color foregroundLight = Color(0xFFF5F5F5);

  // ================= SEMANTIC COLOR PALETTE =================
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  static const Color neutral = Color(0xFFF5F5F5);

  // static const Color neutral = Color(0xFFE4F2E4);

  // Forums' AGAINST side — was colorScheme.error (bright red) at every call
  // site, replaced with this warmer burnt-orange because red read as a
  // literal error/danger state rather than "the other debate side". Same
  // value in light and dark (DarkColors.against below): unlike error/success/
  // etc. this isn't tuned per-brightness yet, just centralized from what was
  // already a single hardcoded Color.fromARGB(255, 212, 90, 53) repeated at
  // each AGAINST call site.
  static const Color against = Color.fromARGB(255, 212, 90, 53);

  // Contrast color for content painted on top of `against` — WCAG-checked:
  // black-on-against is 5.3:1 (passes AA), white-on-against is only 3.95:1
  // (fails AA for normal text), unlike error's near-white onError which
  // reads fine against error's darker red. Same value as textPrimary below.
  static const Color onAgainst = Color(0xFF1d1d1f);

  // ================= BACKGROUND COLOR PALETTE =================
  static const Color background = Color(0xFFF5F5F7); // Apple parchment canvas
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(
    0xFFFFFFFF,
  ); // white cards separated by hairline borders
  static const Color canvasParchment = Color(0xFFF5F5F7);

  // ================= TEXT COLOR PALETTE =================
  static const Color textPrimary = Color(0xFF1d1d1f); // Apple near-black
  static const Color textSecondary = Color(0xFF6e6e73); // Apple secondary
  static const Color textDisabled = Color(0xFFc7c7cc); // Apple disabled

  // ================= UTILITY COLOR PALETTE =================
  static const Color divider = Color(0xFFd2d2d7); // Apple hairline
  static const Color shadow = Color(
    0x0D000000,
  ); // Apple near-zero shadow — elevation via color, not shadow

  // ================= LUXURY COLOR PALETTE =================
  static const Color moderate = Color(
    0xFF00897B,
  ); // Teal — distinct from success green
  static const Color luxury = Color(0xFF9C27B0); // Purple
  static const Color ultraLuxury = Color(0xFFFFB74D); // Amber
}

// =============================================================================
// CLASS: DarkColors
// =============================================================================
class DarkColors {
  // ================= PRIMARY COLOR PALETTE =================
  static const Color primary = Color(0xFFB6FD9D);
  static const Color primaryDark = Color(0xFF7BD461);
  static const Color primaryLight = Color(0xFFE2FFD7);
  static const Color appColor = Color(0xFFB6FD9D);

  // ================= NEUTRAL COLOR PALETTE =================
  // Note: black/white are semantically inverted in dark mode by design —
  // black = near-white text, white = near-black base. Use textPrimary/background for clarity.
  static const Color black = Color(0xFFF5F5F5);
  static const Color darkGrey = Color(0xFFB0B0B0);
  static const Color grey = Color(0xFF8D8D9A);
  static const Color lightGrey = Color(0xFF2A2A2A);
  static const Color white = Color(0xFF121212);

  // ================= FOREGROUND COLOR PALETTE =================
  // Used as primaryContainer in ColorScheme — dark tint of primary
  static const Color foreground = Color(0xFF244D1A);
  static const Color foregroundDark = Color(0xFF212121); // darkest surface gray
  static const Color foregroundLight = Color(
    0xFF606060,
  ); // lighter surface gray

  // ================= SEMANTIC COLOR PALETTE =================
  static const Color success = Color(0xFF66BB6A);
  static const Color warning = Color(0xFFFFB74D);
  static const Color error = Color(0xFFEF5350);
  static const Color info = Color(0xFF42A5F5);
  static const Color neutral = Color(0xFF121212);

  // See LightColors.against/onAgainst. Same value in both themes — against
  // doesn't change with brightness, so neither does its contrast pairing
  // (dark mode's near-white textPrimary only hits 3.6:1 against it, below
  // AA; light mode's near-black hits 5.3:1 and reads correctly in both).
  static const Color against = Color.fromARGB(255, 212, 90, 53);
  static const Color onAgainst = Color(0xFF1d1d1f);

  // ================= BACKGROUND COLOR PALETTE =================
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color card = Color(
    0xFF252525,
  ); // distinct from background to keep cards visible

  // ================= TEXT COLOR PALETTE =================
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFBDBDBD);
  static const Color textDisabled = Color(0xFF757575);

  // ================= UTILITY COLOR PALETTE =================
  static const Color divider = Color(0xFF424242);
  static const Color shadow = Color(0x33000000);

  // ================= LUXURY COLOR PALETTE =================
  static const Color moderate = Color(0xFF4DB6AC); // Teal for dark mode
  static const Color luxury = Color(0xFFBA68C8); // Lighter purple for dark mode
  static const Color ultraLuxury = Color(
    0xFFFFD54F,
  ); // Lighter amber for dark mode
}

// =============================================================================
// CLASS: AppColors
// =============================================================================
class AppColors {
  final bool isDarkMode;

  AppColors(this.isDarkMode);

  // ================= COLOR GETTERS =================

  // Primary colors
  Color get primary => isDarkMode ? DarkColors.primary : LightColors.primary;
  Color get appColor => isDarkMode ? DarkColors.appColor : LightColors.appColor;
  Color get primaryDark =>
      isDarkMode ? DarkColors.primaryDark : LightColors.primaryDark;
  Color get primaryLight =>
      isDarkMode ? DarkColors.primaryLight : LightColors.primaryLight;

  // Neutral colors
  Color get black => isDarkMode ? DarkColors.black : LightColors.black;
  Color get darkGrey => isDarkMode ? DarkColors.darkGrey : LightColors.darkGrey;
  Color get grey => isDarkMode ? DarkColors.grey : LightColors.grey;
  Color get lightGrey =>
      isDarkMode ? DarkColors.lightGrey : LightColors.lightGrey;
  Color get white => isDarkMode ? DarkColors.white : LightColors.white;

  // Foreground colors
  Color get foreground =>
      isDarkMode ? DarkColors.foreground : LightColors.foreground;
  Color get foregroundDark =>
      isDarkMode ? DarkColors.foregroundDark : LightColors.foregroundDark;
  Color get foregroundLight =>
      isDarkMode ? DarkColors.foregroundLight : LightColors.foregroundLight;

  // Semantic colors
  Color get success => isDarkMode ? DarkColors.success : LightColors.success;
  Color get warning => isDarkMode ? DarkColors.warning : LightColors.warning;
  Color get error => isDarkMode ? DarkColors.error : LightColors.error;
  Color get info => isDarkMode ? DarkColors.info : LightColors.info;
  Color get neutral => isDarkMode ? DarkColors.neutral : LightColors.neutral;
  Color get against => isDarkMode ? DarkColors.against : LightColors.against;
  Color get onAgainst =>
      isDarkMode ? DarkColors.onAgainst : LightColors.onAgainst;

  // Background colors
  Color get background =>
      isDarkMode ? DarkColors.background : LightColors.background;
  Color get surface => isDarkMode ? DarkColors.surface : LightColors.surface;
  Color get card => isDarkMode ? DarkColors.card : LightColors.card;
  Color get canvasParchment =>
      isDarkMode ? DarkColors.surface : LightColors.canvasParchment;

  // Text colors
  Color get textPrimary =>
      isDarkMode ? DarkColors.textPrimary : LightColors.textPrimary;
  Color get textSecondary =>
      isDarkMode ? DarkColors.textSecondary : LightColors.textSecondary;
  Color get textDisabled =>
      isDarkMode ? DarkColors.textDisabled : LightColors.textDisabled;

  // Utility colors
  Color get divider => isDarkMode ? DarkColors.divider : LightColors.divider;
  Color get shadow => isDarkMode ? DarkColors.shadow : LightColors.shadow;

  // Luxury colors
  Color get moderate => isDarkMode ? DarkColors.moderate : LightColors.moderate;
  Color get luxury => isDarkMode ? DarkColors.luxury : LightColors.luxury;
  Color get ultraLuxury =>
      isDarkMode ? DarkColors.ultraLuxury : LightColors.ultraLuxury;

  // ================= COMPLEX COLOR PROPERTIES =================
  LinearGradient get primaryGradient => LinearGradient(
    colors:
        isDarkMode
            ? [DarkColors.primary, DarkColors.primaryLight]
            : [LightColors.primary, LightColors.primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ================= HELPER METHODS =================

  /// Returns color based on appointment status
  Color getStatusColor(StatusColor status) {
    switch (status) {
      case StatusColor.confirmed:
        return success;
      case StatusColor.completed:
        return info;
      case StatusColor.cancelled:
        return error;
      case StatusColor.noShow:
        return neutral;
      case StatusColor.pending:
        return warning;
    }
  }

  /// Returns color based on luxury level
  Color getLuxuryColor(String level) {
    switch (level.toLowerCase()) {
      case 'moderate':
        return moderate;
      case 'luxury':
        return luxury;
      case 'ultraluxury':
      case 'ultra luxury':
        return ultraLuxury;
      default:
        return grey;
    }
  }

  /// Returns the color value as an integer (useful for maps, etc.)
  int getStatusColorValue(StatusColor status) {
    return getStatusColor(status).value;
  }

  /// Returns luxury color value as an integer
  int getLuxuryColorValue(String level) {
    return getLuxuryColor(level).value;
  }
}

// =============================================================================
// APPOINTMENT STATUS ENUM
// =============================================================================
enum StatusColor { confirmed, completed, cancelled, noShow, pending }

// =============================================================================
// EXTENSION FOR EASY ACCESS
// =============================================================================
extension StatusColorExtension on StatusColor {
  Color get color {
    final colors = AppColors(
      false,
    ); // Default to light mode, will be overridden by theme
    switch (this) {
      case StatusColor.confirmed:
        return colors.success;
      case StatusColor.completed:
        return colors.info;
      case StatusColor.cancelled:
        return colors.error;
      case StatusColor.noShow:
        return colors.neutral;
      case StatusColor.pending:
        return colors.warning;
    }
  }

  String get displayName {
    switch (this) {
      case StatusColor.confirmed:
        return 'Confirmed';
      case StatusColor.completed:
        return 'Completed';
      case StatusColor.cancelled:
        return 'Cancelled';
      case StatusColor.noShow:
        return 'No Show';
      case StatusColor.pending:
        return 'Pending';
    }
  }
}

extension LuxuryLevelExtension on String {
  Color get color {
    final colors = AppColors(false);
    switch (this.toLowerCase()) {
      case 'moderate':
        return colors.moderate;
      case 'luxury':
        return colors.luxury;
      case 'ultraluxury':
      case 'ultra luxury':
        return colors.ultraLuxury;
      default:
        return colors.grey;
    }
  }
}

// =============================================================================
// COLOR SYSTEM ARCHITECTURE OVERVIEW
// =============================================================================
// THREE-LAYER ARCHITECTURE:
//
// Layer 1: Raw Color Constants (LightColors, DarkColors)
//   - Static, immutable Color objects
//   - Hex values defined once
//   - No logic, just data
//
// Layer 2: Theme-Aware Selector (AppColors)
//   - Logic layer that selects colors based on theme
//   - Provides unified interface
//   - Handles theme switching
//
// Layer 3: Theme Extension (AppThemeExtension in app_theme.dart)
//   - Integrates with Flutter's Theme system
//   - Provides easy access: Theme.of(context).appColors
//   - Automatically detects theme mode
//
// DATA FLOW:
//   Widget → Theme.of(context).appColors → AppColors(isDarkMode) →
//     DarkColors.X or LightColors.X
//
// =============================================================================
// COLOR SELECTION PRINCIPLES
// =============================================================================
// LIGHT THEME COLORS:
// - Backgrounds: Light (F8F9FA, FFFFFF)
// - Text: Dark (1A1A2E, 393E46)
// - Primary: Vibrant (6C63FF)
// - Shadows: Subtle (1A000000 = 10% opacity)
// - Dividers: Light (E0E0E0)
//
// DARK THEME COLORS:
// - Backgrounds: Dark (121212, 1E1E1E)
// - Text: Light (F5F5F5, BDBDBD)
// - Primary: Slightly lighter (7C73FF)
// - Shadows: Stronger (33000000 = 20% opacity)
// - Dividers: Dark (424242)
//
// =============================================================================
// ACCESSIBILITY CONSIDERATIONS
// =============================================================================
// All colors chosen to meet WCAG (Web Content Accessibility Guidelines):
//
// 1. CONTRAST RATIOS:
//    - Text vs Background: Minimum 4.5:1 (AA), 7:1 (AAA)
//    - Example: Light theme textPrimary (#1A1A2E) on background (#F8F9FA) = 15:1 ✓
//    - Example: Dark theme textPrimary (#F5F5F5) on background (#121212) = 16:1 ✓
//
// 2. COLOR BLINDNESS:
//    - Not relying solely on color to convey information
//    - Semantic colors have distinct brightness levels
//    - Success (brightness 50%), Error (brightness 40%), etc.
//
// 3. DARK THEME SPECIFIC:
//    - Avoiding pure black (#000000) which causes halation
//    - Using dark grays (#121212) for better depth perception
//    - Desaturated colors to reduce eye strain
//
// =============================================================================
// USAGE EXAMPLES
// =============================================================================
// Example 1: Basic usage in widget
//   Container(
//     color: Theme.of(context).appColors.background,
//     child: Text(
//       'Hello',
//       style: TextStyle(color: Theme.of(context).appColors.textPrimary),
//     ),
//   )
//
// Example 2: Conditional styling
//   Container(
//     color: isError
//         ? Theme.of(context).appColors.error
//         : Theme.of(context).appColors.success,
//   )
//
// Example 3: Gradient usage
//   Container(
//     decoration: BoxDecoration(
//       gradient: Theme.of(context).appColors.primaryGradient,
//     ),
//   )
//
// Example 4: Direct access (without Theme extension)
//   final colors = AppColors(Theme.of(context).brightness == Brightness.dark);
//   Color myColor = colors.primary;
//
// =============================================================================
// MAINTENANCE AND EXTENSION
// =============================================================================
// Adding a new color:
// 1. Add to both LightColors and DarkColors classes
// 2. Add corresponding getter to AppColors class
// 3. Use in widgets via Theme.of(context).appColors.newColor
//
// Modifying existing colors:
// 1. Change hex value in LightColors/DarkColors
// 2. All usages automatically update (hot reload)
//
// Adding a new theme variant (e.g., high contrast):
// 1. Create HighContrastColors class
// 2. Extend AppColors to handle three modes
// 3. Update AppThemeExtension to detect three modes
//
// =============================================================================
// PERFORMANCE CONSIDERATIONS
// =============================================================================
// - Static constants: Zero runtime cost for color definitions
// - Getters: Minimal overhead (ternary operator)
// - No unnecessary object creation: Colors are compile-time constants
// - Theme extension: Efficient, only creates AppColors when accessed
// - Hot reload friendly: Color changes update instantly
// =============================================================================
