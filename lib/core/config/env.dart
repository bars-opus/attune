import 'dart:io';
import 'package:flutter/foundation.dart';

/// Compile-time environment configuration.
///
/// All sensitive values are read from --dart-define / --dart-define-from-file
/// and have NO hardcoded fallback. The app will fail fast at startup if a
/// required key is missing rather than shipping secrets in the binary.
///
/// Local development: create a `.env.json` file at the project root and run:
///   flutter run --dart-define-from-file=.env.json
///
/// CI/CD: pass the same flags via your pipeline secrets.
class Environment {
  const Environment._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );

  static const String _googleMapsApiKeyIos = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY_IOS',
  );

  static const String _googleMapsApiKeyAndroid = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY_ANDROID',
  );

  static const String _googleMapsApiKeyWeb = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY_WEB',
  );

  /// Returns the platform-appropriate Google Maps API key.
  static String get googleMapsApiKey {
    if (kIsWeb) return _googleMapsApiKeyWeb;
    if (Platform.isIOS) return _googleMapsApiKeyIos;
    return _googleMapsApiKeyAndroid;
  }

  static const String? oneSignalAppId =
      String.fromEnvironment('ONESIGNAL_APP_ID') == ''
          ? null
          : String.fromEnvironment('ONESIGNAL_APP_ID');

  static const String linkBaseDomain = String.fromEnvironment(
    'LINK_BASE_DOMAIN',
    defaultValue: 'aura-in.app',
  );

  static const String linkScheme = String.fromEnvironment(
    'LINK_SCHEME',
    defaultValue: 'aurain',
  );

  static const String appId = String.fromEnvironment(
    'APP_ID',
    defaultValue: 'aurain',
  );

  static const bool isDebug =
      String.fromEnvironment('DEBUG', defaultValue: 'false') == 'true';
}
