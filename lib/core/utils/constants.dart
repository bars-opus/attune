// =============================================================================
// CLASS: AppConstants
// =============================================================================
// Purpose: Centralized repository for all application-wide constant values
// Contains static, immutable constants used throughout the entire application
//
// Design Philosophy:
// 1. SINGLE SOURCE OF TRUTH: All constants defined in one place
// 2. NO MAGIC VALUES: Replace hardcoded strings/numbers with named constants
// 3. TYPE SAFETY: Compile-time checking of constant values
// 4. EASY MAINTENANCE: Change values in one place, affect everywhere
// 5. DISCOVERABILITY: Developers can find all constants in one file
//
// Why use AppConstants instead of hardcoding?
// - Prevents typos and inconsistencies
// - Enables easy refactoring and updates
// - Improves code readability and self-documentation
// - Facilitates internationalization and configuration changes
// =============================================================================
class AppConstants {
  // ================= APPLICATION METADATA CONSTANTS =================
  // Basic information about the application
  // Used for display purposes, version tracking, and app identification

  // The display name of the application
  // Used in: App title, about screens, store listings, user-facing messages
  // Example: Shown in app drawer, AppBar titles, settings screens
  static const String appName = 'Attune';

  // Current version of the application
  // Format: MAJOR.MINOR.PATCH (Semantic Versioning)
  // - MAJOR: Breaking changes
  // - MINOR: New features, backwards compatible
  // - PATCH: Bug fixes, backwards compatible
  // Used in: About screens, update checks, analytics, crash reporting
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';
  static const String appSize = '20mb';
  static const String appReleaseDate = '2024-01-19';
  static const String appCopyright = '© 2024 Bars Opus, Ltd.';
  static const String appDeveloper = 'Bars Opus, Ltd.';
  static const String appPackageName = 'com.attune.attune';
  static const String appBundleId = 'com.attune.attune';

  // App URLs
  static const String websiteUrl = 'https://barsopus.com';
  static const String privacyPolicyUrl = 'https://yourapp.com/privacy';
  static const String dataSharingPolicyUrl = 'https://yourapp.com/privacy';
  static const String termsOfServiceUrl = 'https://yourapp.com/terms';
  static const String supportEmail = 'support@yourapp.com';
  static const String whatAppCustomerSupportLink = 'support@yourapp.com';

  // App Store Links
  static const String appStoreLink = 'https://apps.apple.com/app/id';
  static const String playStoreLink =
      'https://play.google.com/store/apps/details?id=';

  // ================= ASSET PATH CONSTANTS =================
  // File paths for static assets (images, fonts, etc.)
  // Prevents hardcoded strings scattered throughout the codebase

  // Path to the main application logo image
  // Used in: Splash screens, login screens, about dialogs, app icons
  // File should exist at: project_root/assets/images/logo.png
  static const String logoPath = 'assets/images/logo.png';

  // Note: Additional asset paths can be added here as needed:
  // static const String onboardingImage1 = 'assets/images/onboarding_1.png';
  // static const String appFont = 'assets/fonts/Inter-Regular.ttf';
  // static const String placeholderAvatar = 'assets/images/avatar_placeholder.png';

  // ================= STORAGE KEY CONSTANTS =================
  // Keys used for persistent storage (SharedPreferences, Hive, etc.)
  // Ensures consistent key naming across the entire application

  // Key for storing whether the user has completed the intro/onboarding flow
  // Used by: Intro screens, app routing logic, first-launch detection
  // Storage type: Boolean (true = completed, false/false = not completed)
  static const String introCompletedKey = 'intro_completed';
  static const int shopsPerPage = 20;

  // Example additional storage keys (uncomment as needed):
  // static const String authTokenKey = 'auth_token';           // JWT or session token
  // static const String userIdKey = 'user_id';                 // Logged in user ID
  // static const String themeModeKey = 'theme_mode';           // light/dark/system
  // static const String languageKey = 'app_language';          // en, fr, es, etc.
  // static const String lastLoginKey = 'last_login_timestamp'; // DateTime as string
  // static const String notificationsEnabledKey = 'notifications_enabled';

  // ================= API AND NETWORK CONSTANTS =================
  // Configuration values for backend API communication
  // Placeholder values - should be replaced with actual environment-specific values

  // Base URL for all API endpoints
  // Format: Protocol + Domain + Optional base path
  // Used by: Dio/Http clients, Retrofit services, API repositories
  // IMPORTANT: This is a PLACEHOLDER - replace with actual API URL
  // For production apps, use environment-specific configuration files
  static const String baseUrl = 'https://api.example.com';

  // Example additional API constants (uncomment as needed):
  // static const String apiVersion = 'v1';                      // API version prefix
  // static const int apiTimeoutSeconds = 30;                    // Request timeout
  // static const int maxRetryAttempts = 3;                      // Failed request retries
  // static const String apiKey = 'your-api-key-here';          // For authenticated APIs
  // static const String contentTypeJson = 'application/json';   // Content-Type header

  // ================= UI AND LAYOUT CONSTANTS =================
  // Design system values for consistent UI across the application
  // Note: These are examples - uncomment and customize as needed

  // Example UI constants:
  // static const double defaultPadding = 16.0;                  // Standard spacing
  // static const double cardBorderRadius = 12.0;                // Rounded corners
  // static const double buttonHeight = 48.0;                    // Button dimensions
  // static const double appBarElevation = 0.0;                  // Flat design
  // static const Duration animationDuration = Duration(milliseconds: 300);

  // ================= FEATURE FLAG CONSTANTS =================
  // Boolean flags to enable/disable features without code changes
  // Useful for A/B testing, gradual rollouts, and maintenance

  // Example feature flags:
  // static const bool enableNewOnboarding = true;              // Toggle new UX
  // static const bool enableDarkMode = true;                   // Dark theme availability
  // static const bool enableAnalytics = false;                 // During development
  // static const bool enableBetaFeatures = false;              // For beta testers

  // ================= VALIDATION AND FORMAT CONSTANTS =================
  // Patterns and limits for input validation and data formatting

  // Example validation constants:
  // static const String emailRegex = r'^[^@]+@[^@]+\.[^@]+';   // Basic email pattern
  // static const String passwordMinLength = 8;                 // Minimum password length
  // static const int maxUsernameLength = 30;                   // Username character limit
  // static const String dateFormat = 'yyyy-MM-dd';             // Standard date format

  // ================= BUSINESS LOGIC CONSTANTS =================
  // Application-specific rules and limits

  // Example business constants:
  // static const int maxUploadSizeMB = 10;                     // File upload limit
  // static const int itemsPerPage = 20;                        // Pagination limit
  // static const double taxRate = 0.08;                        // Sales tax percentage
  // static const int sessionTimeoutMinutes = 30;               // Auto-logout timer

  static const List<String> shopCategories = [
    'salon',
    'barbershop',
    'spa',
    'nail_salon',
    'lash_studio',
    'waxing',
    'massage',
  ];

  static const List<String> luxuryLevels = [
    'Moderate',
    'Luxury',
    'UltraLuxury',
  ];
}

// =============================================================================
// CONSTANTS ORGANIZATION STRATEGY
// =============================================================================
// GROUPING APPROACH:
//
// 1. Application Metadata: appName, appVersion, buildNumber
// 2. Asset Paths: images, fonts, animations, sounds
// 3. Storage Keys: SharedPreferences, Hive, secure storage
// 4. API Configuration: URLs, timeouts, headers, versions
// 5. UI/Design System: Padding, radii, durations, elevations
// 6. Feature Flags: Toggleable features for rollout control
// 7. Validation Rules: Regex patterns, length limits, formats
// 8. Business Rules: Application-specific constants
//
// For larger applications, consider splitting into multiple files:
// - api_constants.dart
// - storage_constants.dart
// - ui_constants.dart
// - validation_constants.dart
// =============================================================================

// =============================================================================
// ADVANCED PATTERNS AND ALTERNATIVES
// =============================================================================
// PATTERN 1: Environment-Specific Constants
// For different build flavors (dev, staging, production)
/*
class EnvironmentConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dev.api.example.com',
  );
}
// Build with: flutter run --dart-define=API_BASE_URL=https://prod.api.example.com
*/

// PATTERN 2: Nested Constants for Better Organization
/*
class AppConstants {
  static class Api {
    static const String baseUrl = 'https://api.example.com';
    static const int timeout = 30;
  }
  
  static class Storage {
    static const String authToken = 'auth_token';
    static const String userId = 'user_id';
  }
}
// Usage: AppConstants.Api.baseUrl
*/

// PATTERN 3: Generated Constants
// Use build_runner to generate constants from JSON/YAML configuration
/*
// config.yaml
// app_name: "NanoEmbryo"
// api_url: "https://api.example.com"
// Then generate AppConstants from YAML
*/

// PATTERN 4: Internationalization Constants
/*
class AppConstants {
  static class Strings {
    static const String welcomeMessage = 'welcome_message';
    static const String errorGeneric = 'error_generic';
  }
}
// Use with Flutter's intl package for localization
*/
// =============================================================================

// =============================================================================
// BEST PRACTICES FOR USING AppConstants
// =============================================================================
// DO:
// 1. Use AppConstants for ALL string/number literals used in multiple places
// 2. Give constants descriptive, self-explanatory names
// 3. Group related constants together with comments
// 4. Keep constants truly constant (final, immutable values)
// 5. Use proper Dart types (String, int, double, bool, etc.)
//
// DON'T:
// 1. Don't store sensitive data (API keys, secrets) here - use .env files
// 2. Don't use for mutable state - use state management instead
// 3. Don't create constants for values used only once (unless for clarity)
// 4. Don't mix constants with functions or business logic
//
// SECURITY NOTE:
// Constants are compiled into the app binary and can be extracted
// NEVER store secrets, API keys, or sensitive configuration here
// Use flutter_dotenv or similar for environment-specific secrets
// =============================================================================

// =============================================================================
// MIGRATION STRATEGY FROM HARDCODED VALUES
// =============================================================================
// Step 1: Identify hardcoded values used in multiple places
//   Search for: "http://", "/assets/", "key_", magic numbers
//
// Step 2: Add to AppConstants with descriptive name
//   From: Container(padding: EdgeInsets.all(16))
//   To:   Container(padding: EdgeInsets.all(AppConstants.defaultPadding))
//
// Step 3: Update all usages
//   Use IDE "Find and Replace" with exact match
//
// Step 4: Verify no regressions
//   Run tests, check UI, ensure functionality unchanged
//
// Step 5: Document the constant
//   Add comment explaining purpose and usage
// =============================================================================

// =============================================================================
// TESTING WITH AppConstants
// =============================================================================
// Constants are easy to test because they're static and immutable
//
// Example test:
/*
test('AppConstants has valid values', () {
  expect(AppConstants.appName, isNotEmpty);
  expect(AppConstants.appVersion, matches(r'^\d+\.\d+\.\d+$'));
  expect(AppConstants.baseUrl, startsWith('http'));
  expect(AppConstants.logoPath, endsWith('.png'));
});
*/

// For testing with different constant values:
/*
// Create a test-specific constants class
class TestConstants {
  static const String baseUrl = 'http://localhost:8080';
}

// Or use dependency injection for services that need constants
class ApiService {
  final String baseUrl;
  
  ApiService({String? baseUrl}) 
    : baseUrl = baseUrl ?? AppConstants.baseUrl;
}
*/
// =============================================================================

// =============================================================================
// VERSIONING AND DEPRECATION STRATEGY
// =============================================================================
// When constants become obsolete:
//
// 1. Mark as deprecated
//   @Deprecated('Use newConstant instead')
//   static const String oldConstant = 'value';
//
// 2. Provide migration path
//   static const String newConstant = 'new_value';
//   // Keep old constant for backward compatibility during transition
//
// 3. Update documentation
//   // DEPRECATED: Will be removed in v2.0.0
//   // Use AppConstants.newConstant instead
//
// 4. Remove in major version update
//   // Delete in v2.0.0 after sufficient migration period
// =============================================================================

// =============================================================================
// REAL-WORLD USAGE EXAMPLES
// =============================================================================
// Example 1: Using in API service
/*
class ApiClient {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: Duration(seconds: 30),
  ));
}
*/

// Example 2: Using in UI widgets
/*
class WelcomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppConstants.appName)),
      body: Center(
        child: Image.asset(AppConstants.logoPath),
      ),
    );
  }
}
*/

// Example 3: Using in storage
/*
class StorageService {
  Future<void> markIntroCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.introCompletedKey, true);
  }
}
*/

// Example 4: Using in routing
/*
class AppRouter {
  static Route? generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/intro':
        return MaterialPageRoute(builder: (_) => IntroScreen());
      case '/home':
        // Check if intro completed
        final introCompleted = prefs.getBool(AppConstants.introCompletedKey) ?? false;
        return introCompleted 
            ? MaterialPageRoute(builder: (_) => HomeScreen())
            : MaterialPageRoute(builder: (_) => IntroScreen());
    }
  }
}
*/
// =============================================================================

// =============================================================================
// PERFORMANCE CONSIDERATIONS
// =============================================================================
// - Static constants: Zero runtime overhead
// - Compile-time: Values baked into binary, no runtime lookup
// - Memory: Single instance shared across entire application
// - Hot reload: Changes to constants update instantly
// - Tree shaking: Unused constants removed from production builds
// =============================================================================
