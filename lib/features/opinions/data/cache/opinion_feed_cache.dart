// lib/features/opinions/data/cache/opinion_feed_cache.dart

import 'package:attune/core/cache/feed_cache_store.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final opinionFeedCacheProvider = Provider<OpinionFeedCache>((ref) {
  return OpinionFeedCache(ref.watch(sharedPreferencesProvider));
});

/// Which feed a cached payload belongs to. The key suffix is persisted, so
/// renaming a value orphans that feed's existing cache (harmless — it just
/// reads as a miss and refills on the next fetch).
enum OpinionFeed {
  discover('discover'),
  following('following');

  const OpinionFeed(this.key);
  final String key;
}

/// Last-known opinion feed contents, so a relaunch can paint the previous
/// list immediately instead of an empty screen while the fetch runs.
///
/// Envelope handling (version, TTL, clock skew, corruption, size cap) lives
/// in [FeedCacheStore]; this only supplies the encode/decode and the typed
/// [OpinionFeed] surface.
class OpinionFeedCache extends FeedCacheStore<OpinionModel> {
  OpinionFeedCache(super.prefs);

  /// Kept for callers/tests that referenced these before the shared base
  /// existed.
  static const int maxCachedItems = FeedCacheStore.maxCachedItems;
  static const Duration maxAge = FeedCacheStore.maxAge;
  static const int currentSchemaVersion = 1;

  @override
  String get keyPrefix => 'opinion_feed_cache_';

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  Map<String, dynamic> encode(OpinionModel item) => item.toFeedRow();

  @override
  OpinionModel decode(Map<String, dynamic> json) =>
      OpinionModel.fromFeedRow(json);

  List<OpinionModel> readFeed(OpinionFeed feed, String userId) =>
      read(feed.key, userId);

  Future<void> writeFeed(
    OpinionFeed feed,
    String userId,
    List<OpinionModel> opinions,
  ) => write(feed.key, userId, opinions);

  Future<void> clearFeed(OpinionFeed feed, String userId) =>
      clear(feed.key, userId);
}
