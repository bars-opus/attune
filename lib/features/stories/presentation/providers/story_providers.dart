/// Riverpod surface for reading stories (Plan C, Task 2): the ring
/// summary, the active reel, the calendar's day counts and day items, and
/// the `story_change_signals` refetch subscription that keeps all of them
/// current.
///
/// **Realtime is a refetch signal, not data** (spec §5.5). Every provider
/// here that depends on [storyChangeSignalProvider] reacts to a bump by
/// re-invoking the RPC through [StoryReadRepository] — never by reading
/// anything out of the Postgres-changes payload, which
/// [StoryReadRepository.watchChangeSignal] does not even forward. The
/// same providers also expose a manual `refresh()` so a screen can drive
/// the identical re-read on app resume and pull-to-refresh (brief global
/// constraints; spec §5.5's "It also refetches on app resume and
/// pull-to-refresh").
///
/// **Paging is keyset, never offset.** [StoryReelPagesNotifier] and
/// [StoryDayItemsNotifier] both accumulate pages by requesting
/// `after: lastPage.nextCursor` — the previous page's last
/// `(created_at, id)` tuple — and NEVER by row count or page index. A
/// signal-triggered refresh restarts pagination from the first page
/// rather than trying to "resume" a keyset walk after an unknown number
/// of concurrent inserts/deletes, which mirrors how a pull-to-refresh
/// works everywhere else in this codebase.
library;

import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final storyReadGatewayProvider = Provider<StoryReadGateway>((ref) {
  final repository = StoryReadRepository(ref.watch(supabaseClientProvider));
  // Belt-and-braces: storyChangeSignalProvider already closes its OWN
  // relationship's channel via ref.onDispose (below) whenever that
  // family instance is disposed. This catches anything left open if the
  // gateway itself is ever torn down first (e.g. sign-out), rather than
  // leaking a socket subscription for the rest of the session — the
  // same motivation as partner_presence_provider.dart cancelling its
  // Timer on dispose.
  ref.onDispose(repository.disposeAllChannels);
  return repository;
});

/// `void`-only refetch signal for one relationship's `story_change_signals`
/// row. Never exposes `version`/`updated_at` — see this file's header.
/// `.autoDispose`: a reel/calendar screen that closes should stop paying
/// for a websocket subscription nobody is listening to, exactly like
/// `partnerActiveInChatProvider`.
final storyChangeSignalProvider = StreamProvider.autoDispose
    .family<void, String>((ref, relationshipId) {
      final gateway = ref.watch(storyReadGatewayProvider);
      ref.onDispose(() => gateway.disposeChannel(relationshipId));
      return gateway.watchChangeSignal(relationshipId: relationshipId);
    });

/// `get_story_ring_summary`, keyed by relationship.
///
/// Returns a `Map<authorId, StoryRingSummary>` rather than a `List` or a
/// single value. **This shape is deliberate and load-bearing**: the RPC
/// omits an author with zero active stories entirely (spec §5.1/§5.5), so
/// a `List` invites a consumer to write `summaries.isEmpty` or
/// `summaries.firstWhere(...)` and treat "my id is not in the result" as
/// "do not draw my ring" — which is exactly the bug the brief calls out
/// ("hides the `+` for every user who has never posted, which is every
/// new user"). A `Map` makes the correct access pattern
/// (`summaries[myId]`, nullable, used only to FILL a ring the caller
/// already decided to draw) the natural one and a wrong one
/// (`summaries.isEmpty` as "nobody has stories, don't draw anything")
/// visibly awkward to write by accident.
///
/// Re-fetches whenever [storyChangeSignalProvider] fires for the same
/// relationship (spec §5.5).
final storyRingSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, StoryRingSummary>, String>((ref, relationshipId) async {
      // Refetch signal, not data: only the fact of a change is consumed,
      // triggering a re-invocation of this provider. `.future` failures
      // are swallowed the same way a first-subscribe hiccup would be —
      // AsyncValue already carries connection-state/error for a screen to
      // branch on; there is nothing additional to do with the signal
      // itself.
      ref.watch(storyChangeSignalProvider(relationshipId));

      final gateway = ref.watch(storyReadGatewayProvider);
      final rows = await gateway.getRingSummary(relationshipId: relationshipId);
      return {for (final row in rows) row.authorId: row};
    });

/// A page-accumulating notifier shared by the reel and the calendar day
/// view — both walk `story_items` oldest-first with a keyset cursor and
/// both must restart from page one on a signal-triggered or manual
/// refresh rather than attempt to resume mid-walk.
abstract class _KeysetPager extends StateNotifier<AsyncValue<List<StoryItem>>> {
  _KeysetPager() : super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  bool _loadingMore = false;
  StoryPageCursor? _cursor;
  bool _hasMore = true;

  /// Fetches one page starting after [after] (null for the first page).
  Future<StoryItemPage> fetchPage(StoryPageCursor? after);

  bool get hasMore => _hasMore;

  /// Restarts pagination from the first page. Used both for the initial
  /// load and for a signal/pull-to-refresh re-read — never resumed
  /// mid-walk, per this file's header.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    _cursor = null;
    _hasMore = true;
    try {
      final page = await fetchPage(null);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
      state = AsyncValue.data(page.items);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Appends the next page. A no-op while a load is already in flight or
  /// once the last page has been reached (a short page from the server,
  /// per `StoryItemPage.nextCursor`'s contract).
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.valueOrNull;
    if (current == null) return; // still loading the first page
    _loadingMore = true;
    try {
      final page = await fetchPage(_cursor);
      // Appends, never replaces — an insert that landed between pages
      // must show up as a NEW row after the ones already on screen, not
      // duplicate or displace them (spec §5.5, brief global constraints).
      state = AsyncValue.data([...current, ...page.items]);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
    } catch (error, stackTrace) {
      // Keep the existing items visible; surface the load-more failure
      // without discarding what was already fetched.
      state = AsyncValue<List<StoryItem>>.error(
        error,
        stackTrace,
      ).copyWithPrevious(AsyncValue.data(current));
      _hasMore = true; // allow retrying loadMore
    } finally {
      _loadingMore = false;
    }
  }
}

@immutable
class StoryReelKey {
  const StoryReelKey({required this.relationshipId, required this.authorId});

  final String relationshipId;
  final String authorId;

  @override
  bool operator ==(Object other) =>
      other is StoryReelKey &&
      other.relationshipId == relationshipId &&
      other.authorId == authorId;

  @override
  int get hashCode => Object.hash(relationshipId, authorId);
}

class StoryReelPagesNotifier extends _KeysetPager {
  StoryReelPagesNotifier(this._gateway, this._key);

  final StoryReadGateway _gateway;
  final StoryReelKey _key;

  @override
  Future<StoryItemPage> fetchPage(StoryPageCursor? after) {
    return _gateway.listActiveItems(
      relationshipId: _key.relationshipId,
      authorId: _key.authorId,
      after: after,
    );
  }
}

/// One author's active reel within one relationship (`list_active_story_items`
/// — EXCLUDES expired items, spec §5.5). `.autoDispose`: a closed reel
/// screen should not keep paging state or a signal subscription alive.
final storyReelPagesProvider = StateNotifierProvider.autoDispose
    .family<
      StoryReelPagesNotifier,
      AsyncValue<List<StoryItem>>,
      StoryReelKey
    >((ref, key) {
      final gateway = ref.watch(storyReadGatewayProvider);
      final notifier = StoryReelPagesNotifier(gateway, key);
      // A change signal invalidates the visible reel (spec §5.5): restart
      // pagination from page one rather than trying to patch an
      // in-progress keyset walk.
      ref.listen(storyChangeSignalProvider(key.relationshipId), (
        previous,
        next,
      ) {
        if (next.hasValue) unawaited(notifier.refresh());
      });
      return notifier;
    });

/// `list_story_day_counts` for one relationship over `[startOn, endOn]`
/// (spec §5.5) — backs the calendar month view. Re-fetches on a change
/// signal for the same relationship.
final storyDayCountsProvider = FutureProvider.autoDispose
    .family<List<StoryDayCount>, ({String relationshipId, DateTime startOn, DateTime endOn})>((
      ref,
      args,
    ) async {
      ref.watch(storyChangeSignalProvider(args.relationshipId));
      final gateway = ref.watch(storyReadGatewayProvider);
      return gateway.listDayCounts(
        relationshipId: args.relationshipId,
        startOn: args.startOn,
        endOn: args.endOn,
      );
    });

@immutable
class StoryDayKey {
  const StoryDayKey({required this.relationshipId, required this.occurredOn});

  final String relationshipId;
  final DateTime occurredOn;

  @override
  bool operator ==(Object other) =>
      other is StoryDayKey &&
      other.relationshipId == relationshipId &&
      other.occurredOn.year == occurredOn.year &&
      other.occurredOn.month == occurredOn.month &&
      other.occurredOn.day == occurredOn.day;

  @override
  int get hashCode => Object.hash(
    relationshipId,
    occurredOn.year,
    occurredOn.month,
    occurredOn.day,
  );
}

class StoryDayItemsNotifier extends _KeysetPager {
  StoryDayItemsNotifier(this._gateway, this._key);

  final StoryReadGateway _gateway;
  final StoryDayKey _key;

  @override
  Future<StoryItemPage> fetchPage(StoryPageCursor? after) {
    return _gateway.listDayItems(
      relationshipId: _key.relationshipId,
      occurredOn: _key.occurredOn,
      after: after,
    );
  }
}

/// One calendar day's items (`list_story_day_items` — INCLUDES expired
/// items, spec §5.5/§3.2). Obtains later pages as the viewer advances
/// (call [StoryDayItemsNotifier.loadMore]) rather than loading an
/// unbounded day at open (spec §5.5). `.autoDispose` for the same reason
/// as the reel provider.
final storyDayItemsProvider = StateNotifierProvider.autoDispose
    .family<StoryDayItemsNotifier, AsyncValue<List<StoryItem>>, StoryDayKey>((
      ref,
      key,
    ) {
      final gateway = ref.watch(storyReadGatewayProvider);
      final notifier = StoryDayItemsNotifier(gateway, key);
      ref.listen(storyChangeSignalProvider(key.relationshipId), (
        previous,
        next,
      ) {
        if (next.hasValue) unawaited(notifier.refresh());
      });
      return notifier;
    });

/// A signed URL minted fresh for [storageKey] on every call — never
/// cached, never reused across rebuilds. `.autoDispose` + `.family` means
/// Riverpod itself will re-invoke this (and therefore re-mint) whenever a
/// consumer re-watches it after the provider was disposed, but the
/// important guarantee lives in [StoryReadRepository.signMediaUrl]
/// itself: this provider adds no caching layer on top of it. A screen
/// that needs a URL to persist across a rebuild must re-watch this
/// provider, not stash the returned string.
final storyMediaSignedUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, storageKey) {
      final gateway = ref.watch(storyReadGatewayProvider);
      return gateway.signMediaUrl(storageKey);
    });
