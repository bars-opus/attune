// lib/core/localization/locale_repository.dart
import 'dart:ui';
import 'package:flutter/cupertino.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/providers/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 💾 Handles persistent storage of language preferences
///
/// This repository abstracts the storage layer, allowing easy
/// switching between different storage methods (SharedPreferences, Hive, etc.)

// =============================================================================
// CLASS: LocaleRepository
// =============================================================================
// Purpose: Data persistence layer for language preferences
// Handles storage, retrieval, and device locale detection
//
// Key Responsibilities:
// 1. PERSISTENCE: Saves/loads language preferences using SharedPreferences
// 2. FIRST LAUNCH DETECTION: Identifies app's initial startup
// 3. DEVICE LOCALE: Retrieves system language configuration
// 4. STATE INTEGRATION: Provides locale for Riverpod providers
//
// Design Philosophy:
// - Simple data access layer (DAL) pattern
// - Synchronous where possible, async only for I/O operations
// - Immutable keys with clear naming conventions
// - Static methods for pure utility functions
// =============================================================================

class LocaleRepository {
  // ===========================================================================
  // CONSTANTS: Storage Keys
  // ===========================================================================
  /// Storage key for user's selected language preference
  /// Value: ISO 639-1 language code (e.g., 'en', 'es', 'fr')
  static const String _languageKey = 'app_selected_language';

  /// Storage key for first launch detection flag
  /// Value: Boolean indicating if app has been launched before
  static const String _firstLaunchKey = 'app_first_launch';

  final SharedPreferences _prefs;

  /// =========================================================================
  /// CONSTRUCTOR: LocaleRepository
  /// =========================================================================
  /// Initializes repository with SharedPreferences instance
  ///
  /// Precondition: _prefs must be non-null
  /// This is guaranteed by initializedSharedPreferencesProvider
  ///
  /// Design Decision: Direct dependency injection
  /// - Enables testing with mock SharedPreferences
  /// - Clear separation of concerns
  /// - Follows dependency inversion principle
  /// =========================================================================
  LocaleRepository(this._prefs);

  /// =========================================================================
  /// GETTER: isInitialized
  /// =========================================================================
  /// Indicates repository is ready for operations
  ///
  /// Current Implementation: Always returns true
  /// Reason: _prefs is guaranteed non-null by provider chain
  ///
  /// Future Use: Could validate _prefs connectivity
  /// Example: _prefs != null && await _prefs.reload()
  /// =========================================================================
  bool get isInitialized => true; // Always initialized since _prefs is non-null

  /// =========================================================================
  /// METHOD: getSavedLanguageCode
  /// =========================================================================
  /// Loads saved language code from persistent storage
  ///
  /// Return Value:
  /// - String: Saved language code if exists
  /// - null: No language preference saved (first launch or cleared)
  ///
  /// Storage Mechanism: SharedPreferences
  /// Key: _languageKey ('app_selected_language')
  /// Data Type: String (ISO 639-1 language code)
  ///
  /// Performance: Async I/O operation
  /// Average execution: < 5ms on modern devices
  /// =========================================================================
  Future<String?> getSavedLanguageCode() async {
    return _prefs.getString(_languageKey); // No null check needed
  }

  /// =========================================================================
  /// METHOD: saveLanguageCode
  /// =========================================================================
  /// Saves language preference to persistent storage
  ///
  /// Parameters:
  /// - languageCode: ISO 639-1 language code to save
  ///
  /// Storage Operation: Async write to SharedPreferences
  /// Key: _languageKey ('app_selected_language')
  /// Value: Provided languageCode parameter
  ///
  /// Error Handling: Let exceptions propagate
  /// Caller responsibility: Handle storage failures
  ///
  /// Use Case: Called when user selects new language
  /// =========================================================================
  Future<void> saveLanguageCode(String languageCode) async {
    await _prefs.setString(_languageKey, languageCode);
  }

  /// =========================================================================
  /// METHOD: clearSavedLanguage
  /// =========================================================================
  /// Removes saved language preference from storage
  ///
  /// Effect: Next app launch will detect as "first launch"
  /// - Device language detection will trigger
  /// - Default English will be used as fallback
  ///
  /// Use Cases:
  /// 1. Debugging: Reset to initial state
  /// 2. User preference: "Reset to device language" feature
  /// 3. Data cleanup: Remove potentially corrupted preferences
  ///
  /// Storage Operation: Async key removal
  /// =========================================================================
  Future<void> clearSavedLanguage() async {
    await _prefs.remove(_languageKey);
  }

  /// =========================================================================
  /// METHOD: isFirstLaunch
  /// =========================================================================
  /// Determines if this is the application's first launch
  ///
  /// Detection Logic:
  /// 1. Check if _firstLaunchKey exists in SharedPreferences
  /// 2. If not exists: This is first launch
  ///    - Set _firstLaunchKey to true for future launches
  /// 3. If exists: Not first launch
  ///
  /// Storage Behavior:
  /// - First launch: Creates _firstLaunchKey with value true
  /// - Subsequent launches: Key already exists, returns false
  ///
  /// Why track first launch?
  /// - Auto-select device language on initial use
  /// - Skip device detection on subsequent launches
  /// - Maintain user preference across sessions
  /// =========================================================================
  Future<bool> isFirstLaunch() async {
    final isFirst = !_prefs.containsKey(_firstLaunchKey);
    if (isFirst) {
      await _prefs.setBool(_firstLaunchKey, true);
    }
    return isFirst;
  }

  /// =========================================================================
  /// STATIC METHOD: getDeviceLocale
  /// =========================================================================
  /// Retrieves device's primary locale from platform
  ///
  /// Data Source: WidgetsBinding.instance.window.locales
  /// - List of locales configured in device settings
  /// - Ordered by user preference (first = primary)
  ///
  /// Return Value: Locale object
  /// - Primary: First locale from device list
  /// - Fallback: Platform locale if list is empty
  ///
  /// Platform Support:
  /// - iOS: Locales from Settings → General → Language & Region
  /// - Android: Locales from Settings → System → Languages
  /// - Web: Browser language preferences
  ///
  /// Static Design: Pure function, no instance dependency
  /// - Can be called without repository instance
  /// - Useful for debugging and testing
  /// =========================================================================
  static Locale getDeviceLocale() {
    final window = WidgetsBinding.instance.window;
    final locales = window.locales;
    return locales.isNotEmpty ? locales.first : window.locale;
  }

  /// =========================================================================
  /// PROVIDER: currentLocaleProvider
  /// =========================================================================
  /// NOTE: This provider appears to be misplaced
  ///
  /// Current Location: LocaleRepository class (incorrect)
  /// Correct Location: locale_provider.dart with other providers
  ///
  /// Current Implementation:
  /// - Watches localeNotifierProvider for current language
  /// - Converts AppLanguage to Locale for MaterialApp
  ///
  /// Action Required: Move to locale_provider.dart
  /// Reason: Providers belong together for dependency management
  /// =========================================================================
  final currentLocaleProvider = Provider<Locale>((ref) {
    final currentLanguage = ref.watch(localeNotifierProvider);
    return currentLanguage.locale;
  });
}

/// =============================================================================
// STORAGE SCHEMA REFERENCE
// =============================================================================
// SharedPreferences Key-Value Pairs:
//
// | Key                     | Type   | Value Example | Purpose                          |
// |-------------------------|--------|---------------|----------------------------------|
// | app_selected_language   | String | "fr"          | User's chosen language           |
// | app_first_launch        | Bool   | true          | Tracks if app launched before    |
//
// =============================================================================
// DATA FLOW: Language Preference Persistence
// =============================================================================
// 1. USER SELECTION: User chooses language in UI
// 2. SAVE: saveLanguageCode('es') called
// 3. STORAGE: SharedPreferences sets 'app_selected_language' = 'es'
// 4. APP RESTART: getSavedLanguageCode() returns 'es'
// 5. INITIALIZATION: App starts with Spanish language
//
// =============================================================================
// FIRST LAUNCH DETECTION ALGORITHM
// =============================================================================
// Launch #1:
//   isFirstLaunch() → true (key doesn't exist)
//   Sets 'app_first_launch' = true
//   Returns true → triggers device language detection
//
// Launch #2+:
//   isFirstLaunch() → false (key exists)
//   Returns false → uses saved language preference
//
// =============================================================================
// DEVICE LOCALE DETECTION DETAILS
// =============================================================================
// Platform: iOS
//   Source: NSLocale.preferredLanguages
//   Format: ["fr-FR", "en-US", "es-ES"]
//   Result: Locale('fr', 'FR')
//
// Platform: Android
//   Source: LocaleList.getDefault()
//   Format: [fr_FR, en_US, es_ES]
//   Result: Locale('fr', 'FR')
//
// Platform: Web
//   Source: window.navigator.languages
//   Format: ["fr-FR", "en-US", "es-ES"]
//   Result: Locale('fr', 'FR')
//
// =============================================================================
// ERROR SCENARIOS AND HANDLING
// =============================================================================
// 1. Corrupted Storage:
//    - SharedPreferences.get() returns null
//    - Handle: Treat as first launch
//    - Recovery: clearSavedLanguage() then restart
//
// 2. Invalid Language Code:
//    - Storage contains non-ISO code
//    - Handle: findLanguageByCode() returns null
//    - Recovery: clearSavedLanguage() then restart
//
// 3. Device Locale Unavailable:
//    - window.locales is empty
//    - Handle: Use window.locale fallback
//    - Recovery: Accept platform default
//
// =============================================================================
// TESTING STRATEGY
// =============================================================================
// Unit Tests:
//   1. Mock SharedPreferences with pre-set values
//   2. Test isFirstLaunch() with/without key
//   3. Test save/retrieve cycle
//   4. Test clearSavedLanguage() behavior
//
// Integration Tests:
//   1. Real SharedPreferences instance
//   2. Verify persistence across app restarts
//   3. Test device locale detection
//   4. Verify first launch flag behavior
//
// =============================================================================
// PERFORMANCE CONSIDERATIONS
// =============================================================================
// 1. SharedPreferences Access: Async but fast (< 5ms)
// 2. Memory Footprint: Small (2 string keys, 1 bool)
// 3. Battery Impact: Negligible (infrequent writes)
// 4. Thread Safety: SharedPreferences handles synchronization
//
// =============================================================================
// SECURITY CONSIDERATIONS
// =============================================================================
// 1. Data Sensitivity: Low (language preference only)
// 2. Storage Location: App sandbox (secure on iOS/Android)
// 3. Encryption: Not needed for public preference data
// 4. Data Validation: Language codes validated before use
//
// =============================================================================
// MIGRATION CONSIDERATIONS
// =============================================================================
// Future Changes:
// 1. Key Renaming: Update constants, provide migration
// 2. Data Format: Add version field for future changes
// 3. Backward Compatibility: Handle old key formats
// 4. Migration Path: clearSavedLanguage() as reset option
// =============================================================================
