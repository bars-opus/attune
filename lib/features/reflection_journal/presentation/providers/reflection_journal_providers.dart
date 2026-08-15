import 'dart:async';

import 'package:attune/features/healing/presentation/providers/healing_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/reflection_journal/data/cache/reflection_journal_cache.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/repositories/reflection_journal_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reflectionJournalRepositoryProvider =
    Provider<ReflectionJournalRepository>((ref) {
      return ReflectionJournalRepository(ref.read(supabaseClientProvider));
    });

final journalEntriesProvider =
    AsyncNotifierProvider<JournalEntriesNotifier, List<JournalEntry>>(
      JournalEntriesNotifier.new,
    );

/// Cache-then-refresh: paints the last-known entries immediately on a cold
/// start so ConversationsScreen's reflection row isn't showing its empty
/// prompt while the fetch runs, then swaps in fresh data when it lands.
/// Mirrors forums' _CachedTopicsNotifier (forum_providers.dart).
///
/// _servedCache is static so it survives this notifier being recreated by
/// invalidate() — after creating/editing/deleting an entry, serving cache
/// first would briefly re-show the pre-change list, which is exactly what
/// those callers just changed.
class JournalEntriesNotifier extends AsyncNotifier<List<JournalEntry>> {
  static bool _servedCache = false;

  @override
  Future<List<JournalEntry>> build() async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final cache = ref.read(reflectionJournalCacheProvider);

    if (!_servedCache && userId != null) {
      _servedCache = true;
      final cached = cache.readEntries(userId);
      if (cached.isNotEmpty) {
        _refreshInBackground(cache, userId);
        return cached;
      }
    }

    final entries = await _fetch();
    if (userId != null) {
      unawaited(cache.writeEntries(userId, entries));
    }
    return entries;
  }

  Future<List<JournalEntry>> _fetch() {
    return ref.read(reflectionJournalRepositoryProvider).getEntries();
  }

  /// Fetches behind an already-painted cached list. Never surfaces an
  /// AsyncLoading (that would flash the cache away) and swallows failure —
  /// the user keeps reading the cached list until a later refresh succeeds.
  Future<void> _refreshInBackground(
    ReflectionJournalCache cache,
    String userId,
  ) async {
    try {
      final entries = await _fetch();
      state = AsyncData(entries);
      unawaited(cache.writeEntries(userId, entries));
    } catch (error) {
      debugPrint(
        '[reflection_journal] background refresh failed: ${error.runtimeType}',
      );
    }
  }
}

final journalEntryProvider = FutureProvider.family<JournalEntry, String>((
  ref,
  entryId,
) async {
  return ref.read(reflectionJournalRepositoryProvider).getEntry(entryId);
});

final journalPatternsProvider =
    FutureProvider<({String status, String? summary, int entryCount})>((
      ref,
    ) async {
      return ref.read(reflectionJournalRepositoryProvider).getPatterns();
    });

final createJournalEntryProvider = FutureProvider.family<
  String,
  ({String content, String? promptUsed})
>((ref, params) async {
  final entryId = await ref
      .read(reflectionJournalRepositoryProvider)
      .createEntry(content: params.content, promptUsed: params.promptUsed);
  ref.invalidate(journalEntriesProvider);
  return entryId;
});

final updateJournalEntryProvider =
    FutureProvider.family<void, ({String entryId, String content})>((
      ref,
      params,
    ) async {
      await ref
          .read(reflectionJournalRepositoryProvider)
          .updateEntry(entryId: params.entryId, content: params.content);
      ref.invalidate(journalEntriesProvider);
      ref.invalidate(journalEntryProvider(params.entryId));
      ref.invalidate(analyseJournalEntryProvider(params.entryId));
    });

final deleteJournalEntryProvider = FutureProvider.family<void, String>((
  ref,
  entryId,
) async {
  await ref.read(reflectionJournalRepositoryProvider).deleteEntry(entryId);
  ref.invalidate(journalEntriesProvider);
});

final analyseJournalEntryProvider =
    FutureProvider.family<JournalAnalysis, String>((ref, entryId) async {
      final analysis = await ref
          .read(reflectionJournalRepositoryProvider)
          .analyseEntry(entryId);
      ref.invalidate(journalEntryProvider(entryId));
      return analysis;
    });
