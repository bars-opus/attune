// lib/features/reflection_journal/data/cache/reflection_journal_cache.dart

import 'package:attune/core/cache/feed_cache_store.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reflectionJournalCacheProvider = Provider<ReflectionJournalCache>((
  ref,
) {
  return ReflectionJournalCache(ref.watch(sharedPreferencesProvider));
});

/// Last-known journal entries, so ConversationsScreen's reflection row
/// paints instantly on relaunch instead of showing its empty-state prompt
/// while the fetch runs.
///
/// Envelope handling (version, TTL, clock skew, corruption, size cap) lives
/// in [FeedCacheStore]; this only supplies the encode/decode and a single
/// fixed feed key — unlike forums there's only one list here, so no feed
/// enum is needed.
class ReflectionJournalCache extends FeedCacheStore<JournalEntry> {
  ReflectionJournalCache(super.prefs);

  static const String _feedKey = 'entries';

  @override
  String get keyPrefix => 'reflection_journal_cache_';

  @override
  int get schemaVersion => 1;

  @override
  Map<String, dynamic> encode(JournalEntry item) => item.toJson();

  @override
  JournalEntry decode(Map<String, dynamic> json) =>
      JournalEntry.fromJson(json);

  List<JournalEntry> readEntries(String userId) => read(_feedKey, userId);

  Future<void> writeEntries(String userId, List<JournalEntry> entries) =>
      write(_feedKey, userId, entries);

  Future<void> clearEntries(String userId) => clear(_feedKey, userId);
}
