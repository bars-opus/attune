import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central SharedPreferences provider for the entire app.
/// This ensures we have only ONE instance across all features.
/// 1. Base SharedPreferences provider (needs override)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw FlutterError(
    'sharedPreferencesProvider not initialized.\n'
    'Make sure to override this provider in main.dart with:\n'
    'sharedPreferencesProvider.overrideWithValue(prefs)',
  );
});

/// 2. PreferencesService (uses the provider)
final preferencesServiceProvider = Provider<PreferencesService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PreferencesService(prefs);
});

/// 3. First Launch Provider (uses the service)
final isFirstLaunchProvider = Provider<bool>((ref) {
  final prefsService = ref.watch(preferencesServiceProvider);
  return prefsService.isFirstLaunch;
});
