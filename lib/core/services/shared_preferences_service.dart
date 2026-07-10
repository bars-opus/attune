import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static const String _firstLaunchKey =
      'is_first_launch_${AppConstants.appName}';

  // ============ FIRST LAUNCH ============
  Future<void> setFirstLaunchCompleted() async {
    await _prefs.setBool(_firstLaunchKey, false);
  }

  bool get isFirstLaunch {
    return _prefs.getBool(_firstLaunchKey) ?? true;
  }

  // ============ CLEAR ALL PREFS ============
  /// Clears ALL SharedPreferences data
  Future<void> clearAllPreferences() async {
    await _prefs.clear();
  }

  /// Clears only user-specific data, keeps app settings
  Future<void> clearUserData() async {
    // Get all keys
    final keys = _prefs.getKeys();

    // Define which keys to keep
    final keepKeys = {
      _firstLaunchKey, // Keep first launch flag
      'app_theme', // Keep theme preference
      'app_selected_language', // Keep language preference
      // Add any other app settings you want to preserve
    };

    // Remove all keys except those in keepKeys
    for (final key in keys) {
      if (!keepKeys.contains(key)) {
        await _prefs.remove(key);
      }
    }
  }

  // ============ THEME ============
  Future<void> setTheme(String themeName) async {
    await _prefs.setString('app_theme', themeName);
  }

  String? getTheme() => _prefs.getString('app_theme');

  // ============ LANGUAGE ============
  Future<void> setLanguage(String languageCode) async {
    await _prefs.setString('app_selected_language', languageCode);
  }

  String? getLanguage() => _prefs.getString('app_selected_language');

  // ============ FOR TESTING ONLY ============
  Future<void> forceResetFirstLaunch() async {
    await _prefs.remove(_firstLaunchKey);
  }
}

// Provider for PreferencesService
final preferencesServiceProvider = Provider<PreferencesService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PreferencesService(prefs);
});
