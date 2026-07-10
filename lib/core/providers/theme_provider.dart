import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Theme modes available to the user
enum AppThemeMode {
  system('System', Icons.brightness_auto),
  light('Light', Icons.light_mode),
  dark('Dark', Icons.dark_mode);

  final String displayName;
  final IconData icon;

  const AppThemeMode(this.displayName, this.icon);
}

// Convert to Flutter's ThemeMode
ThemeMode toThemeMode(AppThemeMode appThemeMode) {
  switch (appThemeMode) {
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.system:
      return ThemeMode.system;
  }
}

// ✅ Your ThemeNotifier will now use the central provider
final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeMode>(
  (ref) => ThemeNotifier(
    ref.watch(sharedPreferencesProvider),
  ), // Uses central provider
);

// Theme notifier (State management)
class ThemeNotifier extends StateNotifier<AppThemeMode> {
  final SharedPreferences _prefs;
  static const String _themeKey = 'app_theme';

  ThemeNotifier(this._prefs) : super(_loadTheme(_prefs));

  static AppThemeMode _loadTheme(SharedPreferences prefs) {
    final themeString = prefs.getString(_themeKey);
    if (themeString == null) return AppThemeMode.system;

    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == themeString,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setTheme(AppThemeMode theme) async {
    state = theme;
    await _prefs.setString(_themeKey, theme.name);
  }

  // Check if dark mode is active (considering system preference)
  bool isDarkMode(BuildContext context) {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);

    switch (state) {
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.system:
        return platformBrightness == Brightness.dark;
    }
  }
}

// Convenience provider for ThemeMode (used in MaterialApp)
final themeModeProvider = Provider<ThemeMode>((ref) {
  final appThemeMode = ref.watch(themeProvider);
  return toThemeMode(appThemeMode);
});

// Convenience provider for checking dark mode
final isDarkModeProvider = Provider<bool>((ref) {
  // This needs BuildContext, so we'll create a separate widget for it
  throw UnimplementedError('Use ThemeConsumer or BuildContext');
});
