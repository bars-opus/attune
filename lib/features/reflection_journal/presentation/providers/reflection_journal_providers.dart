import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart' show currentUserProvider;
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

/// [value]'s entries when they are the signed-in [account]'s, else null
/// (unknown). Riverpod carries the last value through a reload and keeps it
/// after a failed read, so after an account change the previous account's
/// list is still there until the new account's read lands; each entry
/// carries its owner (`user_id`), so a list holding anyone else's entry is
/// never shown (D8 shared phones, batch-8 re-review N-1). Signed out
/// (null), no journal surface is on screen; the list is passed through.
List<JournalEntry>? ownJournalEntries(
  AsyncValue<List<JournalEntry>> value,
  String? account,
) {
  final entries = value.valueOrNull;
  if (entries == null || account == null) return entries;
  return entries.every((e) => e.userId == account) ? entries : null;
}

/// What the Conversations row and J1 read: [journalEntriesProvider], the
/// signed-in account's only (see [ownJournalEntries]).
final journalOwnEntriesProvider = Provider<List<JournalEntry>?>(
  (ref) => ownJournalEntries(
    ref.watch(journalEntriesProvider),
    ref.watch(journalAccountProvider),
  ),
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
    // Spec 1 W9c (D8, batch-8 fix round 1): the signed-in account's, read
    // again when it changes, so the Conversations row never shows the last
    // account's entry title.
    final userId = ref.watch(journalAccountProvider);
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
      // Another account by now (D8): its own build has the list.
      if (ref.read(journalAccountProvider) != userId) return;
      state = AsyncData(entries);
      unawaited(cache.writeEntries(userId, entries));
    } catch (error) {
      debugPrint(
        '[reflection_journal] background refresh failed: ${error.runtimeType}',
      );
    }
  }
}

/// The signed-in account's id (null signed out). The journal's lists and
/// its in-memory support state are this account's only: they start again
/// when it changes (Spec 1 W9c, D8 shared phones; batch-8 review I-1).
final journalAccountProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);

/// Bumped when an analysis answer changes what Patterns may show (Spec 1
/// W9c, batch-8 review I-2): a support_offered answer must replace a summary
/// read earlier in the run.
class JournalPatternsEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final journalPatternsEpochProvider =
    NotifierProvider<JournalPatternsEpoch, int>(JournalPatternsEpoch.new);

final journalPatternsProvider =
    FutureProvider<({String status, String? summary, int entryCount})>((
      ref,
    ) async {
      ref.watch(journalAccountProvider);
      ref.watch(journalPatternsEpochProvider);
      return ref.read(reflectionJournalRepositoryProvider).getPatterns();
    });

/// The journal's in-memory support state (the offers, the hidden
/// reflections, Patterns' "Not now"), emptied on sign-out and on quick exit
/// through the device-wipe registry (lib/app/device_wipes.dart): on iOS
/// quick exit leaves the process on the neutral screen, so memory survives
/// it (batch-8 review I-1, M-1).
abstract final class JournalSupportMemory {
  static final _clears = <Object, void Function()>{};

  /// [owner]'s [clear], until [ref] is disposed or rebuilt.
  static void track(Object owner, Ref ref, void Function() clear) {
    _clears[owner] = clear;
    ref.onDispose(() => _clears.remove(owner));
  }

  static Future<void> clear() async {
    for (final clear in List.of(_clears.values)) {
      try {
        clear();
      } catch (_) {
        // A notifier being torn down has nothing left to clear.
      }
    }
  }
}

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
  static const _unset = Object();
  Object? _account = _unset;

  ReflectionJournalRepository get _repo => ref.read(reflectionJournalRepositoryProvider);

  @override
  Future<JournalListState> build() async {
    // Spec 1 W9c (D8, batch-8 review I-1): another account on this phone
    // starts from its own list, never the last account's.
    final account = ref.watch(journalAccountProvider);
    if (account != _account) {
      _account = account;
      _discarded.clear();
      _swept = false;
    }
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
      final account = ref.read(journalAccountProvider);
      final page = await _repo.listEntries();
      // Another account by now (D8, batch-8 N-2): its own build has the list.
      if (ref.read(journalAccountProvider) != account) return;
      state = AsyncData(JournalListState(pinned: _keep(page.pinned), entries: _keep(page.entries), hasMore: page.hasMore));
    } catch (_) {} // keep what's on screen; the next visit retries
  }

  bool _loadingMore = false;

  /// The next page, once at a time (scrolling asks repeatedly).
  Future<void> loadMore() async {
    // Never while the list is (re)loading: what it holds then may be the
    // last account's (D8, batch-8 N-2).
    if (state.isLoading) return;
    final s = state.valueOrNull;
    if (_loadingMore || s == null || !s.hasMore || s.entries.isEmpty) return;
    _loadingMore = true;
    try {
      final account = ref.read(journalAccountProvider);
      final page = await _repo.listEntries(before: s.entries.last.createdAt);
      if (ref.read(journalAccountProvider) != account) return;
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
  Future<JournalEntryDetail> build(String entryId) async {
    // Spec 1 W9c: an answer that lands while the entry is open hides its
    // reflection at once.
    ref.listen(journalHiddenReflectionsProvider, (_, hidden) {
      final d = state.valueOrNull;
      if (d != null && hidden.contains(entryId)) _put(_visible(d));
    });
    return _visible(await _repo.getEntryDetail(entryId));
  }

  /// [d] without its reflection when the crisis check answered
  /// support_offered for this entry (Spec 1 W9c).
  JournalEntryDetail _visible(JournalEntryDetail d) =>
      d.analysis != null && ref.read(journalHiddenReflectionsProvider).contains(arg)
          ? JournalEntryDetail(entry: d.entry, blocks: d.blocks)
          : d;

  void _put(JournalEntryDetail d) {
    if (state.hasValue) state = AsyncData(d);
  }

  Future<void> _reload() async => _put(_visible(await _repo.getEntryDetail(arg)));

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

/// Spec 1 W9c (batch-7 ruling R-1): entries whose analysis answered
/// support_offered, this run and this account only (never stored). Their reflection is never
/// shown: [JournalEntryController] drops it from its state, whenever it is
/// read and the moment an entry is added here. An entry leaves only when a
/// later answer is a fresh reflection (journalAnalysisListener).
class JournalHiddenReflections extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(journalAccountProvider);
    JournalSupportMemory.track(this, ref, () => state = const {});
    return const {};
  }

  void hide(String entryId) => state = {...state, entryId};

  void reveal(String entryId) => state = {...state}..remove(entryId);
}

final journalHiddenReflectionsProvider =
    NotifierProvider<JournalHiddenReflections, Set<String>>(
      JournalHiddenReflections.new,
    );

final journalEntryDetailProvider =
    AsyncNotifierProvider.autoDispose.family<JournalEntryController, JournalEntryDetail, String>(
      JournalEntryController.new,
    );
