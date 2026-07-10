import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:attune/core/link/models/link_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Main service for link generation and management
class LinkService {
  final SupabaseClient _supabase;
  final LinkConfig _config;

  LinkService(this._supabase, this._config);

  /// Create a shop link
  Future<LinkCreationResult> createShopLink({
    required String shopId,
    String? customSlug,
    Map<String, dynamic>? metadata,
    Duration? expiresIn,
  }) async {
    return _createLink(
      type: LinkType.shop,
      targetId: shopId,
      customSlug: customSlug,
      metadata: metadata,
      expiresIn: expiresIn,
    );
  }

  /// Create a worker link
  Future<LinkCreationResult> createWorkerLink({
    required String workerId,
    String? customSlug,
    Map<String, dynamic>? metadata,
    Duration? expiresIn,
  }) async {
    return _createLink(
      type: LinkType.worker,
      targetId: workerId,
      customSlug: customSlug,
      metadata: metadata,
      expiresIn: expiresIn,
    );
  }

  /// Create a booking link
  Future<LinkCreationResult> createBookingLink({
    required String bookingId,
    String? customSlug,
    Map<String, dynamic>? metadata,
    Duration? expiresIn,
  }) async {
    return _createLink(
      type: LinkType.booking,
      targetId: bookingId,
      customSlug: customSlug,
      metadata: metadata,
      expiresIn: expiresIn,
    );
  }

  /// Create a campaign link (marketing)
  Future<LinkCreationResult> createCampaignLink({
    required String campaignId,
    String? customSlug,
    Map<String, dynamic>? metadata,
    Duration? expiresIn,
  }) async {
    return _createLink(
      type: LinkType.campaign,
      targetId: campaignId,
      customSlug: customSlug,
      metadata: metadata,
      expiresIn: expiresIn,
    );
  }

  /// Core link creation logic
  Future<LinkCreationResult> _createLink({
    required LinkType type,
    required String targetId,
    String? customSlug,
    Map<String, dynamic>? metadata,
    Duration? expiresIn,
  }) async {
    try {
      // Validate custom slug if provided
      if (customSlug != null && customSlug.isNotEmpty) {
        final validation = _validateSlug(customSlug);
        if (validation != null) {
          return LinkCreationResult.failure(validation);
        }
      }

      // Generate or validate slug
      String slug;
      if (customSlug != null && customSlug.isNotEmpty) {
        slug = customSlug;
      } else {
        // Generate slug from target ID or metadata
        final baseName = metadata?['name']?.toString() ?? targetId;
        slug = await _generateUniqueSlug(baseName);
      }

      // Prepare link data
      final userId = _supabase.auth.currentUser?.id;
      final expiresAt =
          expiresIn != null
              ? DateTime.now().add(expiresIn)
              : _config.defaultLinkExpiration != null
              ? DateTime.now().add(_config.defaultLinkExpiration!)
              : null;

      final linkData = {
        'slug': slug,
        'app_id': _config.appId,
        'link_type': type.name,
        'target_id': targetId,
        'metadata': metadata ?? {},
        'created_by': userId,
        'expires_at': expiresAt?.toIso8601String(),
        'destination_url': null, // Will use default based on type
      };

      // Insert into Supabase
      final response =
          await _supabase
              .from('short_links')
              .insert(linkData)
              .select()
              .single();

      final link = ShortLink.fromJson(response);

      return LinkCreationResult.success(link);
    } catch (e) {
      // Check if it's a unique constraint violation (slug already exists)
      if (e.toString().contains('duplicate key')) {
        return LinkCreationResult.failure(
          'This slug is already taken',
          suggestedSlug: await _generateUniqueSlug(customSlug ?? targetId),
        );
      }

      return LinkCreationResult.failure('Failed to create link: $e');
    }
  }

  /// Get a link by slug
  Future<ShortLink?> getLink(String slug) async {
    try {
      final response =
          await _supabase
              .from('short_links')
              .select()
              .eq('slug', slug)
              .eq('is_active', true)
              .maybeSingle();

      if (response == null) return null;

      // Check expiration
      final link = ShortLink.fromJson(response);
      if (link.isExpired) return null;

      return link;
    } catch (e) {
      throw LinkException('Failed to get link: $e');
    }
  }

  /// Resolve a slug to a ShortLink row scoped to this app.
  ///
  /// Used by the mobile deep link handler (Universal Link `/book/<slug>`).
  /// Unlike [getLink], this filters by [LinkConfig.appId] so cross-app
  /// slug collisions cannot leak — and returns null on any error instead
  /// of throwing, so the router can fall back gracefully to home.
  Future<ShortLink?> resolveSlug(String slug) async {
    if (slug.isEmpty) return null;
    try {
      final response =
          await _supabase
              .from('short_links')
              .select()
              .eq('slug', slug)
              .eq('app_id', _config.appId)
              .eq('is_active', true)
              .maybeSingle();

      if (response == null) return null;

      final link = ShortLink.fromJson(response);
      if (link.isExpired) return null;
      return link;
    } catch (e) {
      debugPrint('resolveSlug failed for "$slug": $e');
      return null;
    }
  }

  /// Track a click on a link
  Future<void> trackClick({
    required String slug,
    String? platform,
    String? userId,
    String? ipAddress,
    String? userAgent,
    String? referrer,
    String? sessionId,
  }) async {
    if (!_config.enableAnalytics) return;

    try {
      await _supabase.rpc(
        'increment_link_clicks',
        params: {
          'link_slug': slug,
          'click_data': {
            'platform': platform ?? 'unknown',
            'user_id': userId,
            'ip_address': ipAddress,
            'user_agent': userAgent,
            'referrer': referrer,
            'session_id': sessionId,
          },
        },
      );
    } catch (e) {
      // Don't throw - analytics failure shouldn't break the user experience
      debugPrint('Failed to track click: $e');
    }
  }

  /// Update a link's destination
  Future<bool> updateLinkDestination(
    String linkId,
    String newDestination,
  ) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw LinkException('User must be logged in to update links');
      }

      await _supabase
          .from('short_links')
          .update({'destination_url': newDestination})
          .eq('id', linkId)
          .eq('created_by', currentUser.id);

      return true;
    } catch (e) {
      throw LinkException('Failed to update link: $e');
    }
  }

  /// Delete (deactivate) a link
  Future<bool> deleteLink(String linkId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw LinkException('User must be logged in to delete links');
      }

      await _supabase
          .from('short_links')
          .update({'is_active': false})
          .eq('id', linkId)
          .eq('created_by', currentUser.id);

      return true;
    } catch (e) {
      throw LinkException('Failed to delete link: $e');
    }
  }

  /// Get analytics for a link
  Future<Map<String, dynamic>> getLinkAnalytics(String linkId) async {
    try {
      final response =
          await _supabase
              .from('link_analytics')
              .select()
              .eq('id', linkId)
              .maybeSingle();

      return response ?? {};
    } catch (e) {
      throw LinkException('Failed to get analytics: $e');
    }
  }

  /// Get all links created by the current user
  Future<List<ShortLink>> getUserLinks() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('short_links')
          .select()
          .eq('created_by', userId)
          .order('created_at', ascending: false);

      return response
          .map<ShortLink>((json) => ShortLink.fromJson(json))
          .toList();
    } catch (e) {
      throw LinkException('Failed to get user links: $e');
    }
  }

  /// Validate slug format
  String? _validateSlug(String slug) {
    if (slug.isEmpty) {
      return 'Slug cannot be empty';
    }

    if (slug.length > _config.maxSlugLength) {
      return 'Slug must be less than ${_config.maxSlugLength} characters';
    }

    // Check for valid characters (lowercase, numbers, hyphens only)
    if (!RegExp(r'^[a-z0-9\-]+$').hasMatch(slug)) {
      return 'Slug can only contain lowercase letters, numbers, and hyphens';
    }

    // Check reserved slugs
    if (_config.reservedSlugs.contains(slug)) {
      return 'This slug is reserved';
    }

    // Check global reserved slugs (from database)
    // This will be checked again in the database
    if (slug == 'admin' || slug == 'api' || slug == 'settings') {
      return 'This slug is reserved';
    }

    return null;
  }

  /// Generate a unique slug using Supabase function
  Future<String> _generateUniqueSlug(String baseText) async {
    try {
      // Call the Supabase function we created
      final result = await _supabase.rpc(
        'generate_unique_slug',
        params: {'base_slug': baseText},
      );

      return result.toString();
    } catch (e) {
      // Fallback: generate manually
      String cleanSlug = baseText
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');

      if (cleanSlug.isEmpty) cleanSlug = 'link';
      if (cleanSlug.length > _config.maxSlugLength) {
        cleanSlug = cleanSlug.substring(0, _config.maxSlugLength);
      }

      // Add random suffix for uniqueness
      final randomSuffix = DateTime.now().millisecondsSinceEpoch
          .toString()
          .substring(8);
      return '$cleanSlug-$randomSuffix';
    }
  }
}
