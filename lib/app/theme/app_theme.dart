import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/app/theme/app_text_theme.dart';
import 'package:flutter/material.dart';
// =============================================================================
// EXTENSION: AppThemeExtension
// =============================================================================
// Purpose: Provides easy access to theme-aware colors from any ThemeData context
//
// How it works:
// - This extension adds a new property `appColors` to all ThemeData objects
// - It detects if the current theme is dark or light via `this.brightness`
// - Creates and returns an AppColors instance configured for the current theme
//
// Usage Example:
//   Theme.of(context).appColors.primary       // Gets primary color for current theme
//   Theme.of(context).appColors.textPrimary   // Gets text color for current theme
//
// Why use an extension?
// - Clean syntax: No need to check theme mode manually
// - Type-safe: Compile-time checking
// - Reusable: Works anywhere you have a ThemeData context
// =============================================================================

extension AppThemeExtension on ThemeData {
  AppColors get appColors {
    final brightness = this.brightness; // Get current theme brightness
    return AppColors(
      brightness == Brightness.dark,
    ); // Create theme-aware colors
  }
}

// =============================================================================
// CLASS: AppTheme
// =============================================================================
// Purpose: Central theme configuration for the entire application
// Contains both light and dark theme configurations that can be switched
// =============================================================================
class AppTheme {
  // ===========================================================================
  // STATIC PROPERTY: lightTheme
  // ===========================================================================
  // The complete light theme configuration for the application
  // Built using Flutter's ThemeData class with Material Design 3 enabled
  //
  // Key Components:
  // 1. COLOR SYSTEM: Uses LightColors from app_colors.dart
  //    - ColorScheme defines the core color palette
  //    - Each color role (primary, background, surface) mapped to LightColors
  //
  // 2. COMPONENT THEMES: Custom styling for specific widgets
  //    - AppBarTheme: Styling for app bars
  //    - CardTheme: Styling for cards
  //    - ButtonThemes: Styling for elevated and text buttons
  //    - InputDecorationTheme: Styling for text fields
  //    - DividerTheme: Styling for dividers
  //
  // 3. TEXT THEME: Applied via .copyWith() at the end
  //    - Uses AppTextTheme.lightTextTheme for consistent typography
  //    - Applied separately to avoid overriding other theme properties
  //
  // Theme Structure:
  //   ThemeData(...all component themes...).copyWith(textTheme: ...)
  //   ^ Base theme with colors/component styling    ^ Adds text styles
  //
  // Color References:
  //   LightColors.primary      -> Primary brand color (e.g., #6C63FF)
  //   LightColors.background   -> Main background color
  //   LightColors.surface      -> Surface/card backgrounds
  //   LightColors.textPrimary  -> Primary text color
  //   LightColors.error        -> Error state color
  //
  // Usage in MaterialApp:
  //   MaterialApp(theme: AppTheme.lightTheme, ...)
  // ===========================================================================
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: LightColors.primary,
      secondary: LightColors.primaryLight,
      surface: LightColors.surface,
      onPrimary: LightColors.textPrimary,
      onSecondary: LightColors.textPrimary,
      onSurface: LightColors.textPrimary,
      error: LightColors.error,
      primaryContainer: LightColors.foreground,
      surfaceDim: LightColors.background,
    ),

    scaffoldBackgroundColor: LightColors.background,

    // Flat app bar — no scroll shadow (Apple never shows elevation on scroll)
    appBarTheme: AppBarTheme(
      backgroundColor: LightColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: LightColors.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: LightColors.textPrimary,
      ),
    ),

    // Cards — white background, hairline border, zero elevation
    cardTheme: CardTheme(
      color: LightColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: LightColors.divider),
      ),
    ),

    // Primary button — pill shape, flat (Apple signature CTA)
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: LightColors.primary,
        foregroundColor: LightColors.textPrimary,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
    ),

    // Ghost pill — secondary action (transparent + primary border)
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: LightColors.primary,
        side: BorderSide(color: LightColors.primary),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: LightColors.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // Inputs — clean rounded, no fill, hairline border
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LightColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: LightColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: LightColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: LightColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: LightColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: LightColors.error, width: 1.5),
      ),
    ),

    // Hairline dividers — Apple uses 0.5px, not 1px
    dividerTheme: DividerThemeData(
      color: LightColors.divider,
      thickness: 0.5,
      space: 0,
    ),
  ).copyWith(textTheme: AppTextTheme.lightTextTheme);

  // ===========================================================================
  // STATIC PROPERTY: darkTheme
  // ===========================================================================
  // The complete dark theme configuration
  // Mirrors lightTheme structure but uses DarkColors for all color values
  //
  // Important Differences from lightTheme:
  // 1. brightness: Brightness.dark (tells Flutter this is a dark theme)
  // 2. All color references use DarkColors instead of LightColors
  // 3. Same component structure ensures consistent design system
  //
  // Design Philosophy:
  // - Dark theme isn't just inverted colors
  // - Uses different color values optimized for dark backgrounds
  // - Maintains same contrast ratios and accessibility standards
  //
  // Example Color Differences:
  //   Light: background = #F8F9FA (light gray)
  //   Dark:  background = #121212 (dark gray)
  //
  //   Light: textPrimary = #1A1A2E (dark blue/black)
  //   Dark:  textPrimary = #F5F5F5 (light gray/white)
  //
  // Usage in MaterialApp:
  //   MaterialApp(darkTheme: AppTheme.darkTheme, themeMode: ThemeMode.dark, ...)
  //   OR MaterialApp(darkTheme: AppTheme.darkTheme, themeMode: ThemeMode.system)
  // ===========================================================================
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: DarkColors.primary,
      secondary: DarkColors.primaryLight,
      surface: DarkColors.surface,
      onPrimary: DarkColors.white,
      onSecondary: DarkColors.white,
      onSurface: DarkColors.textPrimary,
      error: DarkColors.error,
      primaryContainer: DarkColors.foreground,
      surfaceDim: DarkColors.background,
    ),

    scaffoldBackgroundColor: DarkColors.background,

    appBarTheme: AppBarTheme(
      backgroundColor: DarkColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: DarkColors.textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: DarkColors.textPrimary,
      ),
    ),

    // Cards — Apple dark surface 2, no elevation
    cardTheme: CardTheme(
      color: DarkColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: DarkColors.divider),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DarkColors.primary,
        foregroundColor: DarkColors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DarkColors.primary,
        side: BorderSide(color: DarkColors.primary),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DarkColors.primary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DarkColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DarkColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DarkColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DarkColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DarkColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: DarkColors.error, width: 1.5),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: DarkColors.divider,
      thickness: 0.5,
      space: 0,
    ),
  ).copyWith(textTheme: AppTextTheme.darkTextTheme);
}

// =============================================================================
// EXTENSION: ColorSchemeExtension
// =============================================================================
// Adds semantic color access to ColorScheme
// This allows us to use colorScheme.success, colorScheme.warning, etc.
// =============================================================================
extension ColorSchemeExtension on ColorScheme {
  Color get success =>
      brightness == Brightness.light ? LightColors.success : DarkColors.success;

  Color get warning =>
      brightness == Brightness.light ? LightColors.warning : DarkColors.warning;

  Color get info =>
      brightness == Brightness.light ? LightColors.info : DarkColors.info;

  Color get neutral =>
      brightness == Brightness.light ? LightColors.neutral : DarkColors.neutral;
}

// =============================================================================
// HOW THE THREE FILES WORK TOGETHER:
// =============================================================================
// 1. app_colors.dart → Defines LightColors and DarkColors classes
//    - Contains static color constants for both themes
//    - Example: LightColors.primary = Color(0xFF6C63FF)
//    - Used directly in AppTheme for color references
//
// 2. app_text_theme.dart → Defines AppTextTheme class
//    - Contains static TextTheme objects for both themes
//    - Defines font sizes, weights, heights for all text styles
//    - Applied via .copyWith() in AppTheme
//
// 3. app_theme.dart (THIS FILE) → Defines AppTheme class
//    - Uses colors from app_colors.dart
//    - Uses text themes from app_text_theme.dart
//    - Combines them into complete ThemeData objects
//    - Provides AppThemeExtension for easy color access
//
// DATA FLOW:
//   Widget → Theme.of(context) → ThemeData →
//     [Colors from app_colors.dart] + [Text from app_text_theme.dart]
//
// =============================================================================
// USAGE EXAMPLES IN WIDGETS:
// =============================================================================
// 1. Accessing theme colors (using extension):
//    Container(color: Theme.of(context).appColors.primary)
//
// 2. Accessing text styles (from text theme):
//    Text('Hello', style: Theme.of(context).textTheme.titleLarge)
//
// 3. Using Material Design colors (from colorScheme):
//    Container(color: Theme.of(context).colorScheme.background)
//
// 4. Complete example widget:
//    class MyWidget extends StatelessWidget {
//      @override
//      Widget build(BuildContext context) {
//        return Container(
//          color: Theme.of(context).appColors.background,
//          child: Text(
//            'Title',
//            style: Theme.of(context).textTheme.titleLarge?.copyWith(
//              color: Theme.of(context).appColors.textPrimary,
//            ),
//          ),
//        );
//      }
//    }
//
// =============================================================================
// THEME SWITCHING IN MAIN APP:
// =============================================================================
// In main.dart:
//   MaterialApp(
//     theme: AppTheme.lightTheme,      // Light theme
//     darkTheme: AppTheme.darkTheme,    // Dark theme
//     themeMode: ThemeMode.system,      // Auto-switch based on system
//     // OR
//     themeMode: ThemeMode.light,       // Force light
//     // OR
//     themeMode: ThemeMode.dark,        // Force dark
//   )
//
// Programmatic switching (using provider/riverpod):
//   context.read(themeProvider).state = ThemeMode.dark
// =============================================================================
