// lib/core/localization/app_language.dart

// =============================================================================
// FILE: app_language.dart
// =============================================================================
// Purpose: Language models and enumerations for the localization system
// Defines supported languages, their metadata, and utility functions
//
// Key Concepts:
// 1. ISO 639-1 STANDARD: Uses two-letter language codes (en, es, fr, etc.)
// 2. LANGUAGE METADATA: Each language has name, native name, flag emoji
// 3. FLUTTER INTEGRATION: Converts to Flutter's Locale objects
// 4. FALLBACK SYSTEM: Defaults to English when language not found
//
// Design Philosophy:
// - Minimal data model: Only essential metadata for language selection
// - Immutable: All properties are final for thread safety
// - Type-safe: Uses enum-like class with factory constructors
// - Extensible: Easy to add new languages by adding to supportedLanguages
// =============================================================================

import 'package:flutter/material.dart';

/// ============================================================================
/// CLASS: AppLanguage
/// ============================================================================
/// Represents a supported application language with complete metadata
///
/// Properties:
/// - code: ISO 639-1 language code (e.g., 'en', 'es', 'fr')
/// - name: English name of the language (e.g., 'English', 'Spanish')
/// - flag: Country flag emoji for visual representation
/// - nativeName: Name of the language in the language itself
///
/// Design Decisions:
/// 1. ISO 639-1 codes: Standardized, widely supported, matches Flutter's Locale
/// 2. Flag emojis: Provide visual cues for language selection
/// 3. Native names: Respect language identity, helpful for multilingual users
/// 4. Immutable: Thread-safe, can be const, works with Riverpod state
/// ============================================================================
class AppLanguage {
  final String code;      // ISO 639-1 language code (en, es, fr, etc.)
  final String name;      // English display name
  final String flag;      // Country flag emoji
  final String nativeName; // Name in the language itself

  const AppLanguage({
    required this.code,
    required this.name,
    required this.flag,
    required this.nativeName,
  });

  /// ==========================================================================
  /// GETTER: locale
  /// ==========================================================================
  /// Converts AppLanguage to Flutter's Locale object
  ///
  /// Usage:
  ///   final locale = french.locale; // Locale('fr')
  ///   MaterialApp(locale: currentLanguage.locale)
  ///
  /// Why this conversion?
  /// 1. Flutter's localization system uses Locale objects
  /// 2. MaterialApp requires Locale for locale property
  /// 3. Clean separation between app model and Flutter types
  /// ==========================================================================
  Locale get locale => Locale(code);

  /// ==========================================================================
  /// FACTORY: fromLocale
  /// ==========================================================================
  /// Creates AppLanguage from Flutter's Locale object
  ///
  /// Usage:
  ///   final language = AppLanguage.fromLocale(Locale('es'));
  ///   // Returns Spanish AppLanguage object
  ///
  /// Fallback Behavior:
  /// - If locale matches supported language: Returns that language
  /// - If locale not supported: Returns defaultLanguage (English)
  ///
  /// Why factory pattern?
  /// 1. Handles unsupported locales gracefully
  /// 2. Centralized locale-to-language conversion
  /// 3. Type-safe with default fallback
  /// ==========================================================================
  factory AppLanguage.fromLocale(Locale locale) {
    final code = locale.languageCode;
    return supportedLanguages.firstWhere(
      (lang) => lang.code == code,
      orElse: () => defaultLanguage, // Safe fallback to English
    );
  }

  /// ==========================================================================
  /// OPERATOR: == (equality)
  /// ==========================================================================
  /// Compares AppLanguage instances by language code only
  ///
  /// Design Decision: Code-based equality
  /// - Two AppLanguage instances with same code are considered equal
  /// - Ignores other properties (name, flag, nativeName)
  ///
  /// Why code-based equality?
  /// 1. Language code is the unique identifier
  /// 2. Consistent with Locale equality semantics
  /// 3. Simplifies state comparison in Riverpod
  /// ==========================================================================
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLanguage &&
          runtimeType == other.runtimeType &&
          code == other.code;

  /// ==========================================================================
  /// METHOD: hashCode
  /// ==========================================================================
  /// Hash code implementation consistent with equality operator
  ///
  /// Rule: Equal objects must have equal hash codes
  /// Implementation: Uses language code hash code
  ///
  /// Why important?
  /// 1. Required for proper Map/Set behavior
  /// 2. Essential for Riverpod state comparison
  /// 3. Performance optimization for collections
  /// ==========================================================================
  @override
  int get hashCode => code.hashCode;

  /// ==========================================================================
  /// METHOD: toString
  /// ==========================================================================
  /// Debug-friendly string representation
  ///
  /// Format: AppLanguage(code: name)
  /// Example: AppLanguage(fr: French)
  ///
  /// Purpose:
  /// 1. Readable debug output
  /// 2. Easy logging during development
  /// 3. Clear error messages
  /// ==========================================================================
  @override
  String toString() => 'AppLanguage($code: $name)';
}

/// ============================================================================
/// CONSTANT: supportedLanguages
/// ============================================================================
/// Complete list of all languages supported by the application
///
/// Design Considerations:
/// 1. ORDER: Alphabetical by English name for consistency
/// 2. FLAGS: Use standard emojis, consider cultural sensitivity
/// 3. NATIVE NAMES: Accurate native spelling (including accents)
/// 4. EXTENSIBILITY: Add new languages by inserting in alphabetical order
///
/// ISO 639-1 Code Reference:
/// - en: English
/// - es: Spanish (Español)
/// - fr: French (Français)
/// - de: German (Deutsch)
/// - it: Italian (Italiano)
/// - pt: Portuguese (Português)
/// ============================================================================
const List<AppLanguage> supportedLanguages = [
  AppLanguage(
    code: 'en',
    name: 'English',
    flag: '🇺🇸',
    nativeName: 'English',
  ),
  AppLanguage(
    code: 'es',
    name: 'Spanish',
    flag: '🇪🇸',
    nativeName: 'Español',
  ),
  AppLanguage(
    code: 'fr',
    name: 'French',
    flag: '🇫🇷',
    nativeName: 'Français',
  ),
  AppLanguage(
    code: 'de',
    name: 'German',
    flag: '🇩🇪',
    nativeName: 'Deutsch',
  ),
  AppLanguage(
    code: 'it',
    name: 'Italian',
    flag: '🇮🇹',
    nativeName: 'Italiano',
  ),
  AppLanguage(
    code: 'pt',
    name: 'Portuguese',
    flag: '🇵🇹',
    nativeName: 'Português',
  ),
];

/// ============================================================================
/// CONSTANT: defaultLanguage
/// ============================================================================
/// Fallback language when no other language can be determined
///
/// Why English as default?
/// 1. Widest developer understanding for debugging
/// 2. Most complete translation coverage typically
/// 3. Fallback for unsupported device languages
/// 4. Consistent with many international apps
///
/// Technical Note:
/// Uses first element of supportedLanguages (must be English)
/// Changing order of supportedLanguages will change default language
/// ============================================================================
 AppLanguage defaultLanguage = supportedLanguages.first;

/// ============================================================================
/// FUNCTION: findLanguageByCode
/// ============================================================================
/// Utility function to find language by ISO code with null safety
///
/// Usage:
///   final spanish = findLanguageByCode('es'); // Returns Spanish
///   final unknown = findLanguageByCode('xx'); // Returns null
///
/// Search Strategy:
/// 1. Exact match: Try full code (e.g., 'es-ES' -> 'es-ES')
/// 2. Base match: Try language family (e.g., 'es-ES' -> 'es')
/// 3. Fallback: Return null if no match found
///
/// Design Pattern:
/// - Returns null instead of throwing for better error handling
/// - Uses try-catch for clean error suppression
/// - Case-sensitive matching (ISO codes are lowercase)
///
/// Why not extension method?
/// 1. Clear separation of concerns
/// 2. Works with nullable strings
/// 3. Centralized error handling
/// ============================================================================
AppLanguage? findLanguageByCode(String code) {
  try {
    // Try exact match first
    var language = supportedLanguages.firstWhere(
      (lang) => lang.code == code,
    );
    return language;
  } catch (e) {
    // Try matching language family (e.g., 'es-ES' -> 'es')
    final baseCode = code.split('-').first;
    try {
      return supportedLanguages.firstWhere(
        (lang) => lang.code == baseCode,
      );
    } catch (e) {
      return null; // Graceful null return for invalid codes
    }
  }
}

/// ============================================================================
/// LANGUAGE SUPPORT CONSIDERATIONS
/// ============================================================================
/// Adding New Languages:
/// 1. Add to supportedLanguages list in alphabetical order
/// 2. Create corresponding .arb file (app_[code].arb)
/// 3. Add to supportedLocales in MaterialApp
/// 4. Add to validation configuration if needed
///
/// Regional Variants:
/// - Currently supports base language codes only (en, es, fr)
/// - Regional variants (en-US, es-ES) fall back to base language
/// - To add regional support, add entries like 'en_US', 'es_ES'
///
/// RTL Languages:
/// - Current implementation supports LTR languages only
/// - For RTL (Arabic, Hebrew), additional textDirection handling needed
///
/// ============================================================================
/// PERFORMANCE NOTES
/// ============================================================================
/// - Const constructors: All AppLanguage instances are compile-time constants
/// - Small memory footprint: Only 4 string references per language
/// - Fast lookups: Linear search O(n) but n is small (6 languages)
/// - Caching: Consider Map for O(1) lookups if adding many languages
///
/// ============================================================================
/// DEBUGGING TIPS
/// ============================================================================
/// Common Issues:
/// 1. Missing language: Check if code exists in supportedLanguages
/// 2. Case sensitivity: Language codes must be lowercase
/// 3. Emoji display: Ensure device supports flag emojis
/// 4. Locale mismatch: Device locale may include region (fr_FR vs fr)
///
/// Testing:
/// - Use findLanguageByCode('es') to test Spanish detection
/// - Use AppLanguage.fromLocale(Locale('fr')) to test locale conversion
/// - Check defaultLanguage assignment on app startup
/// ============================================================================
