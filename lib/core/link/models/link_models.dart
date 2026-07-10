import 'package:flutter/foundation.dart';

/// Types of links supported by the system
enum LinkType {
  shop, // Link to a shop profile
  worker, // Link to a worker/stylist profile
  booking, // Link to a specific booking
  campaign, // Marketing campaign link
  custom; // Custom destination

  String get value => name;

  static LinkType fromString(String value) {
    return values.firstWhere((e) => e.name == value, orElse: () => custom);
  }
}

/// Configuration for link behavior
class LinkConfig {
  final String appId; // Unique identifier for this app
  final String appName; // App name for display
  final String baseDomain; // e.g., 'luxebeauty.com'
  final String deepLinkScheme; // e.g., 'luxebeauty://'
  final bool enableAnalytics; // Track clicks?
  final int maxSlugLength; // Max characters for custom slug
  final List<String> reservedSlugs; // Blocked slugs
  final Duration? defaultLinkExpiration; // When links expire (null = never)
  final String? fallbackWebUrl; // Web URL when app not installed

  const LinkConfig({
    required this.appId,
    required this.appName,
    required this.baseDomain,
    required this.deepLinkScheme,
    this.enableAnalytics = true,
    this.maxSlugLength = 50,
    this.reservedSlugs = const [],
    this.defaultLinkExpiration,
    this.fallbackWebUrl,
  });

  /// Create config from environment variables
  factory LinkConfig.fromEnv() {
    return LinkConfig(
      appId: const String.fromEnvironment(
        'APP_ID',
        defaultValue: 'default_app',
      ),
      appName: const String.fromEnvironment('APP_NAME', defaultValue: 'My App'),
      baseDomain: const String.fromEnvironment(
        'BASE_DOMAIN',
        defaultValue: 'myapp.com',
      ),
      deepLinkScheme: const String.fromEnvironment(
        'DEEP_LINK_SCHEME',
        defaultValue: 'myapp://',
      ),
      enableAnalytics: const bool.fromEnvironment(
        'ENABLE_ANALYTICS',
        defaultValue: true,
      ),
      maxSlugLength: const int.fromEnvironment(
        'MAX_SLUG_LENGTH',
        defaultValue: 50,
      ),
      reservedSlugs:
          const String.fromEnvironment(
            'RESERVED_SLUGS',
            defaultValue: '',
          ).split(',').where((s) => s.isNotEmpty).toList(),
    );
  }
}

/// Represents a short link
/// Represents a short link
class ShortLink {
  final String id;
  final String slug;
  final String appId;
  final LinkType type;
  final String targetId;
  final String? destinationUrl;
  final Map<String, dynamic> metadata;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int clicks;
  final int uniqueClicks;
  final bool isActive;
  final DateTime? lastClickedAt;

  ShortLink({
    required this.id,
    required this.slug,
    required this.appId,
    required this.type,
    required this.targetId,
    this.destinationUrl,
    this.metadata = const {},
    this.createdBy,
    required this.createdAt,
    this.expiresAt,
    this.clicks = 0,
    this.uniqueClicks = 0,
    this.isActive = true,
    this.lastClickedAt,
  });

  /// Check if link has expired
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory ShortLink.fromJson(Map<String, dynamic> json) {
    return ShortLink(
      id: json['id'].toString(),
      slug: json['slug'].toString(),
      appId: json['app_id'].toString(),
      type: LinkType.fromString(json['link_type'].toString()),
      targetId: json['target_id'].toString(),
      destinationUrl: json['destination_url']?.toString(),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdBy: json['created_by']?.toString(),
      createdAt: DateTime.parse(json['created_at'].toString()),
      expiresAt:
          json['expires_at'] != null
              ? DateTime.parse(json['expires_at'].toString())
              : null,
      clicks: json['clicks'] as int? ?? 0,
      uniqueClicks: json['unique_clicks'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      lastClickedAt:
          json['last_clicked_at'] != null
              ? DateTime.parse(json['last_clicked_at'].toString())
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'app_id': appId,
      'link_type': type.name,
      'target_id': targetId,
      'destination_url': destinationUrl,
      'metadata': metadata,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'clicks': clicks,
      'unique_clicks': uniqueClicks,
      'is_active': isActive,
      'last_clicked_at': lastClickedAt?.toIso8601String(),
    };
  }
}

/// Result when creating a link
class LinkCreationResult {
  final bool success;
  final ShortLink? link;
  final String? error;
  final String? suggestedSlug;

  const LinkCreationResult({
    required this.success,
    this.link,
    this.error,
    this.suggestedSlug,
  });

  factory LinkCreationResult.success(ShortLink link) =>
      LinkCreationResult(success: true, link: link);

  factory LinkCreationResult.failure(String error, {String? suggestedSlug}) =>
      LinkCreationResult(
        success: false,
        error: error,
        suggestedSlug: suggestedSlug,
      );
}

/// Exception for link operations
class LinkException implements Exception {
  final String message;
  final StackTrace? stackTrace;

  LinkException(this.message, [this.stackTrace]);

  @override
  String toString() => 'LinkException: $message';
}
