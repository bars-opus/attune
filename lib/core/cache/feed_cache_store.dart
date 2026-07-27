// lib/core/cache/feed_cache_store.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared envelope logic for "paint the last-known list instantly on launch"
/// feed caches (opinions, forums).
///
/// Deliberately plaintext SharedPreferences rather than the encrypted chat
/// cache: these feeds are public content already visible to any signed-in
/// user, and the payloads are small text lists.
///
/// Keys are scoped per user because every one of these feeds carries
/// viewer-specific fields (an opinion's `is_mine`/`my_reaction`, a topic's
/// `user_vote`/`user_side`) — a shared key would show one account's state to
/// the next account signed in on the same device.
///
/// Subclasses supply only the encode/decode; the version guard, TTL,
/// clock-skew guard, corruption handling and size cap live here so the two
/// caches can't drift apart on their safety rules.
abstract class FeedCacheStore<T> {
  FeedCacheStore(this.prefs);

  @protected
  final SharedPreferences prefs;

  /// Namespace for this cache's keys, e.g. `opinion_feed_cache_`.
  @protected
  String get keyPrefix;

  /// Bump when the persisted shape changes. Payloads written by an older
  /// version read as a miss and refill, instead of throwing through the
  /// decoder on a field that moved or became required.
  @protected
  int get schemaVersion;

  @protected
  Map<String, dynamic> encode(T item);

  @protected
  T decode(Map<String, dynamic> json);

  /// Cap what we persist. Feeds page at 20; roughly a page is enough to fill
  /// the viewport instantly without growing prefs unbounded.
  static const int maxCachedItems = 20;

  /// Beyond this age the cache is treated as a miss. Without a bound, an
  /// offline launch would silently render a week-old feed as if current.
  static const Duration maxAge = Duration(hours: 12);

  String _cacheKey(String feedKey, String userId) =>
      '$keyPrefix${userId}_$feedKey';

  /// Returns the cached rows, or an empty list on a miss — nothing stored,
  /// wrong schema version, past [maxAge], or corrupt.
  List<T> read(String feedKey, String userId) {
    final raw = prefs.getString(_cacheKey(feedKey, userId));
    if (raw == null || raw.isEmpty) return const [];

    try {
      final envelope = Map<String, dynamic>.from(jsonDecode(raw) as Map);

      if (envelope['v'] != schemaVersion) {
        unawaited(clear(feedKey, userId));
        return const [];
      }

      final writtenAtMs = envelope['writtenAt'] as int?;
      if (writtenAtMs == null) {
        unawaited(clear(feedKey, userId));
        return const [];
      }
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(writtenAtMs),
      );
      // Negative age means the device clock moved backwards since the
      // write — treat it as untrustworthy rather than valid-forever.
      if (age.isNegative || age > maxAge) {
        unawaited(clear(feedKey, userId));
        return const [];
      }

      return (envelope['rows'] as List)
          .map((entry) => decode(Map<String, dynamic>.from(entry as Map)))
          .toList();
    } catch (error) {
      // A corrupt or stale-shaped payload should degrade to "no cache", not
      // crash the feed on launch. Drop it so it refills cleanly.
      debugPrint('[cache] $keyPrefix read failed: ${error.runtimeType}');
      unawaited(clear(feedKey, userId));
      return const [];
    }
  }

  Future<void> write(String feedKey, String userId, List<T> items) async {
    final limited =
        items.length > maxCachedItems
            ? items.sublist(0, maxCachedItems)
            : items;
    try {
      await prefs.setString(
        _cacheKey(feedKey, userId),
        jsonEncode({
          'v': schemaVersion,
          'writtenAt': DateTime.now().millisecondsSinceEpoch,
          'rows': limited.map(encode).toList(),
        }),
      );
    } catch (error) {
      // Caching is best-effort — a write failure must never break posting or
      // reading the live feed.
      debugPrint('[cache] $keyPrefix write failed: ${error.runtimeType}');
    }
  }

  Future<void> clear(String feedKey, String userId) async {
    await prefs.remove(_cacheKey(feedKey, userId));
  }
}
