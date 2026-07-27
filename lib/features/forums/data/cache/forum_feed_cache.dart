// lib/features/forums/data/cache/forum_feed_cache.dart

import 'package:attune/core/cache/feed_cache_store.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final forumFeedCacheProvider = Provider<ForumFeedCache>((ref) {
  return ForumFeedCache(ref.watch(sharedPreferencesProvider));
});

/// Which forum list a cached payload belongs to. The key suffix is
/// persisted, so renaming a value orphans that list's existing cache
/// (harmless — it reads as a miss and refills on the next fetch).
enum ForumFeed {
  voting('voting'),
  active('active'),
  quiet('quiet'),
  contributing('contributing');

  const ForumFeed(this.key);
  final String key;
}

/// Last-known forum list contents, so Explore and Contributing paint
/// instantly on relaunch instead of showing empty sections while their
/// fetches run.
///
/// Envelope handling (version, TTL, clock skew, corruption, size cap) lives
/// in [FeedCacheStore]; this only supplies the encode/decode and the typed
/// [ForumFeed] surface.
class ForumFeedCache extends FeedCacheStore<TopicModel> {
  ForumFeedCache(super.prefs);

  static const int maxCachedItems = FeedCacheStore.maxCachedItems;
  static const Duration maxAge = FeedCacheStore.maxAge;
  static const int currentSchemaVersion = 1;

  @override
  String get keyPrefix => 'forum_feed_cache_';

  @override
  int get schemaVersion => currentSchemaVersion;

  /// toCachedJson/fromCachedJson rather than the plain fromJson: a topic's
  /// userVote/userSide arrive as named args on the live path, so only the
  /// cache-specific pair round-trips the viewer's own vote and side.
  @override
  Map<String, dynamic> encode(TopicModel item) => item.toCachedJson();

  @override
  TopicModel decode(Map<String, dynamic> json) =>
      TopicModel.fromCachedJson(json);

  List<TopicModel> readFeed(ForumFeed feed, String userId) =>
      read(feed.key, userId);

  Future<void> writeFeed(
    ForumFeed feed,
    String userId,
    List<TopicModel> topics,
  ) => write(feed.key, userId, topics);

  Future<void> clearFeed(ForumFeed feed, String userId) =>
      clear(feed.key, userId);
}
