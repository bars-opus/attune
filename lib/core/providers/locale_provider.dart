// lib/core/localization/locale_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/localization/locale_repository.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import '../localization/app_language.dart';
import '../localization/locale_service.dart';

// =============================================================================
// FILE: locale_provider.dart
// =============================================================================
// Purpose: Riverpod state management for application language
// Handles language selection, persistence, and MaterialApp integration
//
// Architecture:
// 1. STATE MANAGEMENT: LocaleNotifier manages current language state
// 2. DEPENDENCY INJECTION: Provider pattern for SharedPreferences, services
// 3. PERSISTENCE: Saves language preference across app sessions
// 4. REACTIVE UPDATES: Automatic UI rebuilds when language changes
//
// Key Features:
// - First-launch detection: Auto-selects device language
// - User preference persistence: Remembers language choice
// - Loading states: Shows progress during language changes
// - Error handling: Graceful fallbacks for initialization failures
// - Theme integration: Provides Locale for MaterialApp
// =============================================================================

// =============================================================================
// PROVIDER DEFINITIONS - ORDER MATTERS FOR DEPENDENCY RESOLUTION
// =============================================================================

/// ============================================================================
/// PROVIDER: sharedPreferencesProvider
/// ============================================================================
/// Provides SharedPreferences instance for persistent storage
///
/// Design Pattern:
/// - Provider returns SharedPreferences? (nullable initially)
/// - Overridden in main.dart with actual instance
/// - Nullable allows for initialization timing flexibility
///
/// Why not FutureProvider?
/// 1. Synchronous access needed for other providers
/// 2. Initialized once in main.dart before any widgets build
/// 3. Eliminates async complexity in dependent providers
/// ============================================================================
/// ============================================================================
/// PROVIDER: initializedSharedPreferencesProvider
/// ============================================================================
/// Non-null wrapper that ensures SharedPreferences is initialized
///
/// Safety Mechanism:
/// - Throws descriptive error if sharedPreferencesProvider is null
/// - Ensures runtime safety for repository initialization
/// - Provides clear error message for debugging
///
/// Why separate provider?
/// 1. Type safety: Returns non-null SharedPreferences
/// 2. Error clarity: Specific error message for missing initialization
/// 3. Dependency clarity: Makes null-handling explicit
/// ============================================================================

/// ============================================================================
/// PROVIDER: localeRepositoryProvider
/// ============================================================================
/// Creates LocaleRepository with guaranteed initialized SharedPreferences
///
/// Dependency Chain:
/// initializedSharedPreferencesProvider → LocaleRepository
///
/// Design Principle:
/// - Single responsibility: Only creates repository
/// - Guaranteed initialization: Uses non-null SharedPreferences
/// - Lazy loading: Created only when first accessed
/// ============================================================================
final localeRepositoryProvider = Provider<LocaleRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider); // Now using central provider
  return LocaleRepository(prefs);
});

/// ============================================================================
/// PROVIDER: localeServiceProvider
/// ============================================================================
/// Creates LocaleService with repository dependency
///
/// Business Logic Layer:
/// - Contains language initialization and change logic
/// - Handles device language detection on first launch
/// - Manages validation configuration updates
///
/// Why separate service layer?
/// 1. Separation of concerns: Business logic vs state management
/// 2. Testability: Can be unit tested without widgets
/// 3. Reusability: Can be used outside Riverpod context
/// ============================================================================
final localeServiceProvider = Provider<LocaleService>((ref) {
  final repository = ref.watch(localeRepositoryProvider);
  return LocaleService(repository);
});

/// ============================================================================
/// CLASS: LocaleNotifier
/// ============================================================================
/// Riverpod StateNotifier for managing application language state
///
/// Responsibilities:
/// 1. Language initialization on app start
/// 2. Language change operations
/// 3. Loading state management
/// 4. Error handling and recovery
///
/// State Management Pattern:
/// - Extends StateNotifier<AppLanguage> for reactive state
/// - State is AppLanguage (current selected language)
/// - Notifier methods mutate state, triggering UI updates
/// ============================================================================
class LocaleNotifier extends StateNotifier<AppLanguage> {
  final LocaleService _service;

  /// ========================================================================
  /// STATE FLAGS: _isLoading, _lastError
  /// ========================================================================
  /// Internal state for operation tracking
  ///
  /// _isLoading: Tracks async operations (initialization, language changes)
  /// _lastError: Stores last error message for debugging/recovery
  ///
  /// Why private with public getters?
  /// 1. Encapsulation: Internal state management
  /// 2. Immutability: External access via getters only
  /// 3. Consistency: Controlled state updates
  /// ========================================================================
  bool _isLoading = false;
  String? _lastError;

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  /// ========================================================================
  /// CONSTRUCTOR: LocaleNotifier
  /// ========================================================================
  /// Initializes notifier with default language
  ///
  /// Parameters:
  /// - _service: LocaleService for business logic
  ///
  /// Initial State: defaultLanguage (English)
  /// This ensures app has valid language even before initialization
  /// ========================================================================
  LocaleNotifier(this._service) : super(defaultLanguage);

  /// ========================================================================
  /// METHOD: initialize
  /// ========================================================================
  /// Initializes language on app startup
  ///
  /// Operation Flow:
  /// 1. Sets loading state
  /// 2. Calls service to determine language
  /// 3. Updates state with determined language
  /// 4. Handles errors with fallback to default
  ///
  /// Error Handling:
  /// - Catches exceptions during initialization
  /// - Stores error message for debugging
  /// - Falls back to default language
  /// - Always clears loading state
  /// ========================================================================
  Future<void> initialize() async {
    try {
      _isLoading = true;
      _lastError = null;

      final language = await _service.initializeLanguage();
      state = language;
    } catch (e) {
      _lastError = 'Failed to initialize language: $e';
      state = defaultLanguage; // Fallback
    } finally {
      _isLoading = false;
    }
  }

  /// ========================================================================
  /// METHOD: changeLanguage
  /// ========================================================================
  /// Changes application language with full state management
  ///
  /// Pre-check: Returns early if already using requested language
  /// Operation Flow:
  /// 1. Sets loading state
  /// 2. Calls service to save language preference
  /// 3. Updates state on success
  /// 4. Shows user feedback
  /// 5. Handles errors gracefully
  ///
  /// User Feedback:
  /// - Shows success snackbar on completion
  /// - Shows error snackbar on failure
  /// - Maintains loading state during operation
  /// ========================================================================
  Future<void> changeLanguage(AppLanguage newLanguage) async {
    if (state == newLanguage) return; // No change needed

    try {
      _isLoading = true;
      _lastError = null;

      await _service.changeLanguage(
        newLanguage: newLanguage,
        onSuccess: () {
          state = newLanguage;
          _showSnackbar('Language changed to ${newLanguage.name}');
        },
        onError: (error) {
          _lastError = error;
          _showSnackbar('Failed to change language');
        },
      );
    } catch (e) {
      _lastError = 'Unexpected error: $e';
      _showSnackbar('An unexpected error occurred');
    } finally {
      _isLoading = false;
    }
  }

  /// ========================================================================
  /// METHOD: changeLanguageByCode
  /// ========================================================================
  /// Convenience method to change language by ISO code
  ///
  /// Usage:
  ///   changeLanguageByCode('es') // Changes to Spanish
  ///
  /// Validation:
  /// - Verifies code is supported via findLanguageByCode
  /// - Shows error if code not supported
  /// - Delegates to changeLanguage if valid
  ///
  /// Why separate method?
  /// 1. Simpler API for common use case
  /// 2. Centralized code validation
  /// 3. Consistent error handling
  /// ========================================================================
  Future<void> changeLanguageByCode(String languageCode) async {
    final language = findLanguageByCode(languageCode);
    if (language != null) {
      await changeLanguage(language);
    } else {
      _lastError = 'Unsupported language code: $languageCode';
      _showSnackbar('Language not supported');
    }
  }

  /// ========================================================================
  /// METHOD: resetToDeviceLanguage
  /// ========================================================================
  /// Resets language preference to match device system language
  ///
  /// Operation:
  /// 1. Gets device locale from system
  /// 2. Finds matching AppLanguage
  /// 3. Changes to device language or default
  ///
  /// Use Cases:
  /// - "Reset to default" functionality
  /// - Testing device language detection
  /// - User preference reset
  /// ========================================================================
  Future<void> resetToDeviceLanguage() async {
    final deviceLocale = LocaleRepository.getDeviceLocale();
    final deviceLanguage = findLanguageByCode(deviceLocale.languageCode);

    if (deviceLanguage != null) {
      await changeLanguage(deviceLanguage);
    } else {
      await changeLanguage(defaultLanguage);
    }
  }

  /// ========================================================================
  /// METHOD: getSupportedLanguages
  /// ========================================================================
  /// Returns list of all supported languages for UI display
  ///
  /// Delegation Pattern:
  /// - Service provides business logic
  /// - Notifier exposes to UI layer
  /// - Consistent data source
  /// ========================================================================
  List<AppLanguage> getSupportedLanguages() {
    return _service.getSupportedLanguages();
  }

  /// ========================================================================
  /// METHOD: isLanguageSelected
  /// ========================================================================
  /// Checks if a specific language is currently selected
  ///
  /// Usage:
  ///   if (notifier.isLanguageSelected(spanish)) { ... }
  ///
  /// Why method instead of computed property?
  /// 1. Clear intent: Language comparison operation
  /// 2. Parameterized: Works with any AppLanguage
  /// 3. Consistent naming: Follows Flutter conventions
  /// ========================================================================
  bool isLanguageSelected(AppLanguage language) {
    return state == language;
  }

  /// ========================================================================
  /// GETTER: currentLocale
  /// ========================================================================
  /// Gets current locale for MaterialApp configuration
  ///
  /// Usage:
  ///   MaterialApp(locale: notifier.currentLocale)
  ///
  /// Conversion: AppLanguage → Locale
  /// Maintains separation between app model and Flutter types
  /// ========================================================================
  Locale get currentLocale => state.locale;

  /// ========================================================================
  /// METHOD: _showSnackbar
  /// ========================================================================
  /// Private helper for user feedback during language operations
  ///
  /// Current Implementation: Console logging
  /// Future Enhancement: Integrate with SnackbarUtils
  ///
  /// Why private?
  /// 1. Internal implementation detail
  /// 2. Consistent feedback mechanism
  /// 3. Centralized message handling
  /// ========================================================================
  void _showSnackbar(String message) {
    // You can use your SnackbarUtils here
    print('LocaleNotifier: $message');
  }
}

/// ============================================================================
/// PROVIDER: localeNotifierProvider
/// ============================================================================
/// Main state notifier provider for language management
///
/// Type: StateNotifierProvider<LocaleNotifier, AppLanguage>
/// - Notifier: LocaleNotifier (state management logic)
/// - State: AppLanguage (current selected language)
///
/// Dependency Chain:
/// localeServiceProvider → LocaleNotifier
///
/// Design Pattern:
/// - Single source of truth for language state
/// - Automatic state persistence via Riverpod
/// - Reactive updates across entire app
/// ============================================================================
final localeNotifierProvider =
    StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) {
      final service = ref.watch(localeServiceProvider);
      return LocaleNotifier(service);
    });

/// ============================================================================
/// PROVIDER: currentLocaleProvider
/// ============================================================================
/// Convenience provider for MaterialApp locale configuration
///
/// Usage:
///   MaterialApp(locale: ref.watch(currentLocaleProvider))
///
/// Why separate provider?
/// 1. Type conversion: AppLanguage → Locale
/// 2. MaterialApp specific: Direct integration point
/// 3. Separation of concerns: State vs configuration
/// ============================================================================
final currentLocaleProvider = Provider<Locale>((ref) {
  return ref.watch(localeNotifierProvider).locale;
});

/// ============================================================================
/// PROVIDER: localeLoadingProvider
/// ============================================================================
/// Convenience provider for language operation loading states
///
/// Monitors: Initialization and language change operations
/// Usage: Show loading indicators during language transitions
///
/// Why separate provider?
/// 1. Focused concern: Only loading state
/// 2. Performance: Watches only loading flag
/// 3. UI convenience: Direct access without notifier
/// ============================================================================
final localeLoadingProvider = Provider<bool>((ref) {
  return ref.watch(localeNotifierProvider.notifier).isLoading;
});

// =============================================================================
// OPTIONAL: HELPER PROVIDERS FOR COMMON USE CASES
// =============================================================================

/// ============================================================================
/// PROVIDER: currentAppLanguageProvider
/// ============================================================================
/// Direct access to current AppLanguage (alternative to localeNotifierProvider)
///
/// Usage:
///   final language = ref.watch(currentAppLanguageProvider);
///
/// Why optional?
/// - Redundant with localeNotifierProvider
/// - Provided for API preference consistency
/// ============================================================================
final currentAppLanguageProvider = Provider<AppLanguage>((ref) {
  return ref.watch(localeNotifierProvider);
});

/// ============================================================================
/// PROVIDER: supportedLanguagesProvider
/// ============================================================================
/// Convenience provider for language selection UI
///
/// Usage:
///   final languages = ref.watch(supportedLanguagesProvider);
///   // Display in ListView.builder
///
/// Why optional?
/// - Convenience for language selection screens
/// - Cached list access without notifier method calls
/// ============================================================================
final supportedLanguagesProvider = Provider<List<AppLanguage>>((ref) {
  return ref.watch(localeNotifierProvider.notifier).getSupportedLanguages();
});

/// ============================================================================
/// PROVIDER: isLanguageChangingProvider
/// ============================================================================
/// Alternative name for localeLoadingProvider (semantic preference)
///
/// Usage:
///   final isChanging = ref.watch(isLanguageChangingProvider);
///
/// Why optional?
/// - Semantic naming preference
/// - API compatibility if switching from other state management
/// ============================================================================
final isLanguageChangingProvider = Provider<bool>((ref) {
  return ref.watch(localeNotifierProvider.notifier).isLoading;
});

/// ============================================================================
/// PROVIDER DEPENDENCY GRAPH
/// ============================================================================
/// sharedPreferencesProvider (nullable)
///     ↓
/// initializedSharedPreferencesProvider (non-null)
///     ↓
/// localeRepositoryProvider (uses non-null SharedPreferences)
///     ↓
/// localeServiceProvider (uses repository)
///     ↓
/// localeNotifierProvider (uses service, manages state)
///     ↓
/// currentLocaleProvider, localeLoadingProvider (derived states)
///
/// ============================================================================
/// PERFORMANCE CONSIDERATIONS
/// ============================================================================
/// 1. Provider Order: Dependencies must be defined before dependents
/// 2. Lazy Loading: Providers instantiate only when first accessed
/// 3. Smart Rebuilding: Riverpod only rebuilds dependent widgets
/// 4. State Isolation: Language changes don't rebuild unrelated widgets
///
/// ============================================================================
/// TESTING STRATEGY
/// ============================================================================
/// Unit Tests:
/// 1. Mock SharedPreferences for repository tests
/// 2. Mock LocaleService for notifier tests
/// 3. Test initialization flow with various device locales
/// 4. Test error handling scenarios
///
/// Widget Tests:
/// 1. ProviderScope with overrides
/// 2. Mock language state changes
/// 3. Verify UI updates on language change
/// 4. Test loading states
///
/// Integration Tests:
/// 1. Full language selection flow
/// 2. Persistence across app restarts
/// 3. Device language detection
/// ============================================================================
