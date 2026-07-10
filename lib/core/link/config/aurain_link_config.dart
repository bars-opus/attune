// lib/core/link/config/aurain_link_config.dart
import 'package:flutter/foundation.dart';
import '../models/link_models.dart';

/// Aura-In specific link configuration
class AuraInLinkConfig {
  /// Production configuration for Aura-In app
  static const LinkConfig production = LinkConfig(
    appId: 'aurain',
    appName: 'Aura-In',
    baseDomain: 'aurain.barsopus.com',
    deepLinkScheme: 'aurain://',
    enableAnalytics: true,
    maxSlugLength: 50,
    reservedSlugs: [
      'admin',
      'api',
      'settings',
      'help',
      'support',
      'privacy',
      'terms',
      'login',
      'signup',
      'auth',
      'callback',
      'webhook',
      'health',
      'metrics',
      'debug',
      'test',
    ],
    defaultLinkExpiration: null, // Permanent links for now
    fallbackWebUrl: 'https://aura-in.app',
  );

  /// Development configuration (for local testing)
  static const LinkConfig development = LinkConfig(
    appId: 'aurain_dev',
    appName: 'Aura-In Dev',
    baseDomain: 'aura-in-dev.app',
    deepLinkScheme: 'auraindev://',
    enableAnalytics: false, // Don't track in dev
    maxSlugLength: 50,
    reservedSlugs: ['admin', 'api', 'test'],
    defaultLinkExpiration: Duration(days: 30), // Expire after 30 days
    fallbackWebUrl: 'http://localhost:3000',
  );

  /// Staging configuration (for testing before production)
  static const LinkConfig staging = LinkConfig(
    appId: 'aurain_staging',
    appName: 'Aura-In Staging',
    baseDomain: 'staging.aura-in.app',
    deepLinkScheme: 'aurainstage://',
    enableAnalytics: true,
    maxSlugLength: 50,
    reservedSlugs: ['admin', 'api', 'test'],
    defaultLinkExpiration: Duration(days: 60),
    fallbackWebUrl: 'https://staging.aura-in.app',
  );

  /// Get the appropriate config based on environment
  static LinkConfig getConfig() {
    // When building for production: flutter build apk --release
    // When building for dev: flutter run (automatically kDebugMode = true)
    if (kDebugMode) {
      return development;
    }

    // Check for staging flag (you can implement this based on your needs)
    // For now, return production
    return production;
  }
}
