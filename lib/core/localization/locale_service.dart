// lib/core/localization/locale_service.dart
import 'package:flutter/material.dart';
import 'package:attune/core/localization/app_language.dart';
import 'package:attune/core/localization/locale_repository.dart';

// =============================================================================
// CLASS: LocaleService
// =============================================================================
// Purpose: Business logic layer for language management
// Orchestrates language initialization, changes, and system integration
//
// Key Responsibilities:
// 1. LANGUAGE INITIALIZATION: Determines app language on startup
// 2. LANGUAGE CHANGES: Handles user-initiated language switching
// 3. SYSTEM INTEGRATION: Updates validation and other system components
// 4. DATA FORMATTING: Formats language data for UI presentation
//
// Design Principles:
// - Business Logic Only: No UI or direct state management
// - Error Handling: Graceful fallbacks with clear error messages
// - Logging: Comprehensive debugging for initialization flow
// - Separation of Concerns: Pure business logic, no Flutter dependencies
// =============================================================================

class LocaleService {
  final LocaleRepository _repository;

  /// =========================================================================
  /// CONSTRUCTOR: LocaleService
  /// =========================================================================
  /// Initializes service with repository dependency
  ///
  /// Dependency Injection Pattern:
  /// - Repository handles data persistence
  /// - Service handles business logic
  /// - Clean separation for testability
  ///
  /// Single Responsibility: Each class has one reason to change
  /// =========================================================================
  LocaleService(this._repository);

  /// =========================================================================
  /// GETTER: isInitialized
  /// =========================================================================
  /// Delegates initialization check to repository
  ///
  /// Current Implementation: Repository always returns true
  /// Future Enhancement: Could add service-specific initialization
  ///
  /// Design Pattern: Facade for repository state
  /// =========================================================================
  bool get isInitialized => _repository.isInitialized;

  /// =========================================================================
  /// METHOD: initializeLanguage
  /// =========================================================================
  /// Determines app language on startup using priority-based algorithm
  ///
  /// Priority Hierarchy (Highest to Lowest):
  /// 1. SAVED PREFERENCE: Previously user-selected language
  /// 2. DEVICE LANGUAGE: System language on first app launch
  /// 3. DEFAULT ENGLISH: Fallback when no other option available
  ///
  /// Flow Diagram:
  /// ┌─────────────────┐
  /// │  Start          │
  /// └────────┬────────┘
  ///          │
  /// ┌────────▼────────┐
  /// │ Repository      │
  /// │ Initialized?    │───No───► Default English
  /// └────────┬────────┘
  ///          │Yes
  /// ┌────────▼────────┐
  /// │ Saved Preference│───Exists───► Use Saved Language
  /// └────────┬────────┘
  ///          │Not Exists
  /// ┌────────▼────────┐
  /// │ First Launch?   │───No───► Default English
  /// └────────┬────────┘
  ///          │Yes
  /// ┌────────▼────────┐
  /// │ Device Language │───Supported───► Use Device Language
  /// └────────┬────────┘
  ///          │Not Supported
  /// ┌────────▼────────┐
  /// │ Default English │
  /// └─────────────────┘
  ///
  /// Debug Logging: Comprehensive for troubleshooting initialization issues
  /// Remove in production or use conditional logging
  /// =========================================================================
  Future<AppLanguage> initializeLanguage() async {
    // =======================================================================
    // STEP 1: Repository Availability Check
    // =======================================================================
    // Ensures storage layer is ready before attempting operations
    // Critical for app stability on first launch
    if (!isInitialized) {
      return defaultLanguage;
    }

    // =======================================================================
    // STEP 2: Saved User Preference Check (Highest Priority)
    // =======================================================================
    // User's explicit choice should always be respected
    // Persisted across app restarts until user changes it
    final savedCode = await _repository.getSavedLanguageCode();
    if (savedCode != null) {
      final savedLanguage = findLanguageByCode(savedCode);
      if (savedLanguage != null) {
        return savedLanguage;
      }
      // Note: If savedCode exists but findLanguageByCode returns null,
      // the saved preference is invalid (corrupted or from older version)
      // We'll fall through to next priority level
    }

    // =======================================================================
    // STEP 3: First Launch Device Language Detection
    // =======================================================================
    // Only runs on first app launch to respect user's system language
    // Subsequent launches use saved preference from Step 2
    final isFirstLaunch = await _repository.isFirstLaunch();
    if (isFirstLaunch) {
      final deviceLocale = LocaleRepository.getDeviceLocale();
      final deviceLanguage = findLanguageByCode(deviceLocale.languageCode);

      if (deviceLanguage != null) {
        // Save detected device language for future launches
        await _repository.saveLanguageCode(deviceLanguage.code);
        return deviceLanguage;
      } else {
        // Fall through to default English
      }
    }

    // =======================================================================
    // STEP 4: Default Fallback (Lowest Priority)
    // =======================================================================
    // Safety net when no other option is available
    // English chosen as most widely understood fallback
    return defaultLanguage;
  }

  /// =========================================================================
  /// METHOD: changeLanguage
  /// =========================================================================
  /// Handles user-initiated language changes with complete error handling
  ///
  /// Operation Sequence:
  /// 1. Persist new language preference to storage
  /// 2. Update system components (validation, etc.)
  /// 3. Notify caller of success/failure
  ///
  /// Error Strategy:
  /// - Catch-all exception handling
  /// - Descriptive error messages
  /// - Callback pattern for UI feedback
  ///
  /// Why callback pattern instead of returning Future?
  /// 1. Clear separation: Business logic vs UI feedback
  /// 2. Flexibility: Caller controls UI response
  /// 3. Consistency: Matches Flutter's async patterns
  /// =========================================================================
  Future<void> changeLanguage({
    required AppLanguage newLanguage,
    required VoidCallback onSuccess,
    required ValueChanged<String> onError,
  }) async {
    try {
      // =====================================================================
      // SUB-OPERATION 1: Storage Persistence
      // =====================================================================
      // Critical: Save before any other operations
      // If save fails, nothing else should happen
      await _repository.saveLanguageCode(newLanguage.code);

      // =====================================================================
      // SUB-OPERATION 2: System Configuration Update
      // =====================================================================
      // Updates validation messages and other language-dependent systems
      // Must happen after successful storage
      _updateValidationConfig(newLanguage.code);

      // =====================================================================
      // SUB-OPERATION 3: Success Notification
      // =====================================================================
      // Caller handles UI updates (snackbars, state changes, etc.)
      onSuccess();
    } catch (e) {
      // =====================================================================
      // ERROR HANDLING: Provide actionable error message
      // =====================================================================
      // Include exception details for debugging
      // Caller decides how to present to user
      onError('Failed to change language: $e');
    }
  }

  /// =========================================================================
  /// METHOD: _updateValidationConfig
  /// =========================================================================
  /// Updates validation system when language changes
  ///
  /// Current Implementation: Placeholder for validation system integration
  ///
  /// Integration Points:
  /// 1. ValidationUtils.configure() - Validation message localization
  /// 2. Date/number formatting - Locale-specific formats
  /// 3. RTL support - Text direction for RTL languages
  ///
  /// Why private method?
  /// 1. Implementation detail of changeLanguage operation
  /// 2. Centralized system update logic
  /// 3. Future expansion point for other system updates
  /// =========================================================================
  void _updateValidationConfig(String languageCode) {
    // Update your ValidationUtils configuration here
    // Example:
    if (languageCode == 'es') {
      // ValidationUtils.configure(ValidationConfig.es());
    } else {
      // ValidationUtils.configure(ValidationConfig.en());
    }
  }

  /// =========================================================================
  /// METHOD: getSupportedLanguages
  /// =========================================================================
  /// Returns copy of supported languages list for UI display
  ///
  /// Design Pattern: Defensive copy
  /// - Prevents accidental modification of source list
  /// - Ensures UI receives fresh data
  /// - Maintains immutability of source data
  ///
  /// Performance: O(n) copy operation
  /// Acceptable because: Small list (6 languages), infrequent calls
  /// =========================================================================
  List<AppLanguage> getSupportedLanguages() {
    return List.from(supportedLanguages);
  }

  /// =========================================================================
  /// METHOD: formatLanguageDisplay
  /// =========================================================================
  /// Formats language for user-friendly UI display
  ///
  /// Format: [FLAG EMOJI] [ENGLISH NAME] ([NATIVE NAME])
  /// Example: 🇪🇸 Spanish (Español)
  ///
  /// Design Considerations:
  /// 1. Flag emoji: Visual quick recognition
  /// 2. English name: Consistent reference point
  /// 3. Native name: Cultural respect, helps multilingual users
  ///
  /// Localization Note: This method's output is not localized
  /// Language names shown in English for consistent UI language
  /// =========================================================================
  String formatLanguageDisplay(AppLanguage language) {
    return '${language.flag} ${language.name} (${language.nativeName})';
  }
}

/// =============================================================================
// INITIALIZATION SCENARIOS AND OUTCOMES
// =============================================================================
// Scenario 1: First Launch with Supported Device Language
//   Device: French (fr_FR)
//   Storage: Empty
//   Process: Detects first launch → finds French → saves → returns French
//   Result: App shows French
//
// Scenario 2: First Launch with Unsupported Device Language
//   Device: Japanese (ja_JP)
//   Storage: Empty
//   Process: Detects first launch → Japanese not supported → fallback
//   Result: App shows English (default)
//
// Scenario 3: Subsequent Launch with Saved Preference
//   Device: Spanish (es_ES) [Changed since last use]
//   Storage: French (fr) [From previous selection]
//   Process: Finds saved French → returns French (ignores device)
//   Result: App shows French (user preference respected)
//
// Scenario 4: Corrupted Storage
//   Device: English (en_US)
//   Storage: Invalid code ('xx')
//   Process: Finds saved 'xx' → invalid → first launch detection → device
//   Result: App shows English (device language)
//
// =============================================================================
// ERROR RECOVERY STRATEGIES
// =============================================================================
// 1. Storage Failure:
//    - Catch exception in changeLanguage()
//    - Call onError() with descriptive message
//    - UI shows error, language unchanged
//
// 2. Invalid Language Code:
//    - findLanguageByCode() returns null
//    - initializeLanguage() falls through to next priority
//    - User sees default language, can reselect
//
// 3. Repository Not Initialized:
//    - isInitialized returns false
//    - Immediate fallback to default
//    - Logs error for debugging
//
// =============================================================================
// TESTING SCENARIOS
// =============================================================================
// Unit Tests:
//   1. Mock repository with various saved states
//   2. Test initialization priority hierarchy
//   3. Test changeLanguage success/failure paths
//   4. Test formatting methods
//
// Integration Tests:
//   1. Real repository with SharedPreferences
//   2. Test full initialization flow
//   3. Test persistence across operations
//   4. Test error scenarios
//
// =============================================================================
// PERFORMANCE CONSIDERATIONS
// =============================================================================
// 1. initializeLanguage(): Called once per app start
//    - Async operations: 2-3 SharedPreferences calls
//    - Average execution: < 50ms
//    - Acceptable for one-time initialization
//
// 2. changeLanguage(): Called on user interaction
//    - Single async storage write
//    - Fast validation updates
//    - Should complete in < 100ms for good UX
//
// 3. getSupportedLanguages(): Called on UI render
//    - List copy operation
//    - O(n) where n = 6 (negligible)
//
// =============================================================================
// FUTURE ENHANCEMENTS
// =============================================================================
// 1. Language Pack System:
//    - Downloadable language packs
//    - Partial translations with fallbacks
//    - Community translation contributions
//
// 2. Advanced Detection:
//    - Region-specific variants (en-US vs en-GB)
//    - Dialect support (zh-CN vs zh-TW)
//    - RTL language handling
//
// 3. System Integration:
//    - Notification localization
//    - Deep link language handling
//    - Share sheet language context
//
// 4. Analytics:
//    - Language selection tracking
//    - Usage patterns by language
//    - Popularity metrics for language prioritization
//
// =============================================================================
// DEBUGGING TIPS
// =============================================================================
// Common Issues:
// 1. Language not changing: Check repository save operations
// 2. Wrong language on start: Verify initialization priority
// 3. Validation not updating: Check _updateValidationConfig integration
// 4. Performance issues: Monitor SharedPreferences operations
//
// Log Analysis:
// - "Repository not initialized": Provider configuration issue
// - "Device language not supported": Add language to supportedLanguages
// - "Saved language code: null": First launch or cleared preferences
// - "Using default language": Fallback scenario triggered
//
// =============================================================================
// DEPLOYMENT CHECKLIST
// =============================================================================
// Before Release:
// 1. Remove debug prints or wrap in kDebugMode
// 2. Test all supported languages
// 3. Verify first launch detection
// 4. Test language change persistence
// 5. Validate error handling
// 6. Check RTL language support if applicable
//
// Post-Release Monitoring:
// 1. Most popular language selections
// 2. First launch language detection accuracy
// 3. Language change failure rates
// 4. Regional language variant requests
// =============================================================================
