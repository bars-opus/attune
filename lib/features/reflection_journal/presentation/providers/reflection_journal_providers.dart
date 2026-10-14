import 'dart:async';

import 'package:attune/features/healing/presentation/providers/healing_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/reflection_journal/data/cache/reflection_journal_cache.dart';
import 'package:attune/features/reflection_journal/data/journal_media.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/models/journal_note.dart';
import 'package:attune/features/reflection_journal/data/repositories/reflection_journal_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

final journalPatternsProvider =
    FutureProvider<({String status, String? summary, int entryCount})>((
      ref,
    ) async {
      return ref.read(reflectionJournalRepositoryProvider).getPatterns();
    });

final journalMediaGatewayProvider = Provider<JournalMediaGateway>(
  (ref) => SupabaseJournalMediaGateway(ref.read(supabaseClientProvider)),
);

/// A stored photo's short-lived link (10 minutes), fetched while the photo
/// is on screen; the image itself is cached by its path.
final journalPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(journalMediaGatewayProvider).signedUrl(path),
);

class JournalListState {
  const JournalListState({required this.pinned, required this.entries, required this.hasMore});
  final List<JournalEntrySummary> pinned;
  final List<JournalEntrySummary> entries;
  final bool hasMore;

  JournalListState copyWith({List<JournalEntrySummary>? pinned, List<JournalEntrySummary>? entries, bool? hasMore}) =>
      JournalListState(pinned: pinned ?? this.pinned, entries: entries ?? this.entries, hasMore: hasMore ?? this.hasMore);
}

/// The Entries tab: pinned first, then pages by the day written. Opening
/// it sweeps deletions left past their Undo window (the app closed mid-Undo).
class JournalListNotifier extends AsyncNotifier<JournalListState> {
  final Set<String> _discarded = {};
  bool _swept = false;

  ReflectionJournalRepository get _repo => ref.read(reflectionJournalRepositoryProvider);

  @override
  Future<JournalListState> build() async {
    if (!_swept) {
      _swept = true;
      unawaited(_repo.purgeMyDeleted().then((_) {}, onError: (Object _) {}));
    }
    final page = await _repo.listEntries();
    return JournalListState(pinned: _keep(page.pinned), entries: _keep(page.entries), hasMore: page.hasMore);
  }

  List<JournalEntrySummary> _keep(List<JournalEntrySummary> rows) =>
      [for (final r in rows) if (!_discarded.contains(r.id)) r];

  Future<void> refresh() async {
    // The Conversations "latest reflection" line reads the other list.
    ref.invalidate(journalEntriesProvider);
    try {
      final page = await _repo.listEntries();
      state = AsyncData(JournalListState(pinned: _keep(page.pinned), entries: _keep(page.entries), hasMore: page.hasMore));
    } catch (_) {} // keep what's on screen; the next visit retries
  }

  bool _loadingMore = false;

  /// The next page, once at a time (scrolling asks repeatedly).
  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (_loadingMore || s == null || !s.hasMore || s.entries.isEmpty) return;
    _loadingMore = true;
    try {
      final page = await _repo.listEntries(before: s.entries.last.createdAt);
      final now = state.valueOrNull ?? s;
      state = AsyncData(now.copyWith(entries: [...now.entries, ..._keep(page.entries)], hasMore: page.hasMore));
    } catch (_) {
      // the next scroll retries
    } finally {
      _loadingMore = false;
    }
  }

  /// A new entry left empty: gone from the list now, whatever a refresh says.
  void forget(String entryId) {
    _discarded.add(entryId);
    ref.invalidate(journalEntriesProvider);
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(
      pinned: [for (final r in s.pinned) if (r.id != entryId) r],
      entries: [for (final r in s.entries) if (r.id != entryId) r],
    ));
  }

  Future<void> togglePin(JournalEntrySummary e) async {
    final before = state.valueOrNull;
    if (before == null) return;
    final moved = e.withPinned(!e.pinned);
    state = AsyncData(before.copyWith(
      pinned: e.pinned ? [for (final r in before.pinned) if (r.id != e.id) r] : [moved, ...before.pinned],
      entries: e.pinned
          ? ([...before.entries, moved]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          : [for (final r in before.entries) if (r.id != e.id) r],
    ));
    try {
      await _repo.setPinned(e.id, !e.pinned);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Hidden now (soft delete) so Undo can bring it back.
  Future<void> delete(JournalEntrySummary e) async {
    final before = state.valueOrNull;
    if (before == null) return;
    state = AsyncData(before.copyWith(
      pinned: [for (final r in before.pinned) if (r.id != e.id) r],
      entries: [for (final r in before.entries) if (r.id != e.id) r],
    ));
    try {
      await _repo.deleteEntry(e.id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> restore(String entryId) async {
    await _repo.restoreEntry(entryId);
    _discarded.remove(entryId);
    await refresh();
  }

  /// After the Undo window: for good (best effort; the sweep retries).
  Future<void> purge(String entryId) async {
    try {
      await _repo.purgeEntry(entryId);
    } catch (_) {}
    ref.invalidate(journalEntriesProvider);
  }
}

final journalListProvider = AsyncNotifierProvider<JournalListNotifier, JournalListState>(JournalListNotifier.new);

/// One entry, as a note: its title and blocks.
class JournalEntryController extends AutoDisposeFamilyAsyncNotifier<JournalEntryDetail, String> {
  ReflectionJournalRepository get _repo => ref.read(reflectionJournalRepositoryProvider);
  JournalEntryDetail get _current => state.requireValue;

  @override
  Future<JournalEntryDetail> build(String entryId) => _repo.getEntryDetail(entryId);

  void _put(JournalEntryDetail d) {
    if (state.hasValue) state = AsyncData(d);
  }

  Future<void> _reload() async => _put(await _repo.getEntryDetail(arg));

  Future<NoteSaveResult> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    try {
      final r = await _repo.saveText(blockId, version, ops);
      if (r.status == 'conflict') {
        return NoteConflict(ops: r.block.delta, version: r.block.version, plainText: r.block.plainText ?? '');
      }
      if (state.hasValue) {
        _put(_current.copyWith(blocks: [for (final b in _current.blocks) b.id == blockId ? r.block : b]));
      }
      return NoteSaved(version: r.block.version, plainText: r.block.plainText);
    } on JournalNotFound {
      return const NoteGone();
    }
  }

  Future<void> rename(String? title) async {
    final e = await _repo.rename(arg, title);
    _put(_current.copyWith(entry: e));
  }

  Future<void> setPinned(bool pinned) async {
    await _repo.setPinned(arg, pinned);
    await _reload();
  }

  static const _emptyText = {
    'delta': [
      {'insert': '\n'},
    ],
  };

  Future<JournalBlock> addBlock(String kind, {Map<String, dynamic>? payload, String? afterId}) async {
    final b = await _repo.insertBlock(arg, afterId: afterId, kind: kind, payload: payload ?? _emptyText);
    await _reload();
    return b;
  }

  /// Mid-paragraph, as a word processor does: the text keeps what came
  /// before the cursor, the new block goes next, the rest follows it.
  Future<JournalBlock> insertAtCursor(
    String kind, {
    required String textBlockId,
    required int version,
    required List<Map<String, dynamic>> before,
    required List<Map<String, dynamic>> after,
    Map<String, dynamic>? payload,
  }) async {
    final cut = await saveText(textBlockId, version, before);
    if (cut is! NoteSaved) throw const JournalNotFound();
    final inserted = await _repo.insertBlock(arg, afterId: textBlockId, kind: kind, payload: payload ?? _emptyText);
    await _repo.insertBlock(arg, afterId: inserted.id, kind: 'text', payload: {'delta': after});
    await _reload();
    return inserted;
  }

  Future<void> deleteBlock(String blockId) async {
    await _repo.deleteBlock(blockId);
    await _reload();
  }

  Future<void> moveBlock(String blockId, int to) async {
    final blocks = List.of(_current.blocks);
    final i = blocks.indexWhere((b) => b.id == blockId);
    if (i >= 0) {
      final b = blocks.removeAt(i);
      blocks.insert(to.clamp(0, blocks.length), b);
      _put(_current.copyWith(blocks: blocks));
    }
    try {
      await _repo.moveBlock(blockId, to);
    } finally {
      await _reload();
    }
  }

  /// Where a new photo goes: inside the owner's own entry folder.
  String newPhotoPath() => '${_current.entry.userId}/$arg/${const Uuid().v4()}.jpg';

  Future<JournalBlock> addPhoto(Uint8List jpeg, {String? afterId}) async {
    final path = newPhotoPath();
    await ref.read(journalMediaGatewayProvider).uploadJpeg(path, jpeg); // nothing saved if this fails
    return addBlock('photo', payload: {'path': path}, afterId: afterId);
  }
}

final journalEntryDetailProvider =
    AsyncNotifierProvider.autoDispose.family<JournalEntryController, JournalEntryDetail, String>(
      JournalEntryController.new,
    );
