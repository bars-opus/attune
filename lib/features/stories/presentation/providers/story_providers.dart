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
///
/// **Fix round 1 (task-2-review.md, finding 4): app resume is wired
/// HERE, not deferred to a screen.** Spec §5.5 requires a refetch on app
/// resume, and it matters more than an ordinary deferral because the
/// realtime socket is torn down while backgrounded — the emit-on-
/// resubscribe behaviour only helps once the socket actually reconnects
/// in the foreground, so without this a resumed app could sit on an
/// arbitrarily stale reel. [storyChangeSignalProvider] therefore attaches
/// an `AppLifecycleListener` (not a `WidgetsBindingObserver`, so no
/// widget/BuildContext is needed at the provider layer) alongside the
/// gateway's realtime stream and emits the identical `void` signal on
/// `onResume`, reusing the exact refetch pipe every dependent provider
/// already reacts to rather than inventing a second invalidation path.
library;

import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/domain/story_day_rings.dart';
import 'package:attune/features/stories/presentation/providers/story_visible_refresh.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:attune/features/stories/presentation/state/story_ring_refresh.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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
/// row, PLUS an app-resume emission (finding 4 — see this file's header).
/// Never exposes `version`/`updated_at`. `.autoDispose`: a reel/calendar
/// screen that closes should stop paying for a websocket subscription
/// (and an idle lifecycle listener) nobody is listening to, exactly like
/// `partnerActiveInChatProvider`.
final storyChangeSignalProvider = StreamProvider.autoDispose
    .family<void, String>((ref, relationshipId) {
      final gateway = ref.watch(storyReadGatewayProvider);
      ref.onDispose(() => gateway.disposeChannel(relationshipId));

      final controller = StreamController<void>.broadcast();
      final sub = gateway
          .watchChangeSignal(relationshipId: relationshipId)
          .listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );

      // While backgrounded the realtime socket is torn down entirely, so
      // the resubscribe-on-reconnect emission cannot help until the
      // process is already back in the foreground with a live socket.
      // onResume closes that gap directly: it fires whether or not the
      // socket happened to have dropped, so a resume always re-reads
      // canonical state through the same refetch pipe (spec §5.5).
      final lifecycleListener = AppLifecycleListener(
        onResume: () {
          if (!controller.isClosed) controller.add(null);
        },
      );

      ref.onDispose(() {
        unawaited(sub.cancel());
        lifecycleListener.dispose();
        unawaited(controller.close());
      });

      return controller.stream;
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
///
/// Wave 4: coalesced, retried, re-read at expiry, and evicts deleted
/// thumbnails (story_ring_refresh.dart).
final storyRingSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, StoryRingSummary>, String>((ref, relationshipId) async {
      // Refetch signal, not data: only the fact of a change is consumed,
      // triggering a re-invocation of this provider.
      ref.watch(storyChangeSignalProvider(relationshipId));
      final gateway = ref.watch(storyReadGatewayProvider);
      final coalescer = ref.watch(storyRingFetchCoalescerProvider);
      // M-4: the return's re-read is the one the resume signal joins.
      final refresh = StoryVisibleRefresh(
        ref,
        onReturn: () => coalescer.markReturn(relationshipId),
      );
      // Captured before the fetch (review #1, #4): a wipe or an account
      // switch while it is in flight means its result is not saved.
      final userId = ref.watch(currentUserProvider.select((u) => u?.id));
      final lastKnownStore = ref.watch(storyRingLastKnownStoreProvider);
      final epoch = lastKnownStore.epoch;
      // Review #3: the first read after a launch diffs against the
      // snapshot, so a story deleted while Attune was closed is evicted.
      // Read alongside the fetch and applied off the return path: a slow
      // keychain never holds the rings.
      final evictor = ref.read(storyMediaEvictorProvider);
      final Future<StoryRingSnapshot?>? seed =
          coalescer.previous(relationshipId) == null && userId != null
          ? lastKnownStore.read().catchError((Object _) => null)
          : null;

      final StoryRingFetch fetch;
      try {
        fetch = await coalescer.run(
          relationshipId,
          () => gateway.getRingSummary(relationshipId: relationshipId),
        );
      } catch (_) {
        if (!refresh.disposed) {
          final failures = coalescer.recordFailure(relationshipId);
          if (failures <= kStoryRingMaxAutoRetries) {
            refresh.after(storyRingRetryDelay(failures));
          }
        }
        rethrow;
      }
      final map = {for (final row in fetch.rows) row.authorId: row};
      // A superseded build shares the live build's result: only the live
      // one records, schedules or evicts.
      if (refresh.disposed) return map;

      coalescer.resetFailures(relationshipId);
      ref
          .read(storyPostedHoldsProvider.notifier)
          .releaseFetchedSince(relationshipId, fetch.startedAt);
      final now = clock.now();
      final previous = coalescer.previous(relationshipId);
      coalescer.remember(relationshipId, map);
      if (previous == null && seed != null) {
        unawaited(
          seed.then((snapshot) async {
            final before = snapshot?.usableFor(
              userId: userId!,
              relationshipId: relationshipId,
              now: now,
            );
            if (before == null) return;
            final dropped = storyRingDroppedThumbnailKeys(before, map, now);
            if (dropped.isNotEmpty) await evictor.evict(dropped);
          }),
        );
      }
      // 03 M3: the last rings this phone saw, for a cold start offline.
      // Saved only if no wipe and no account switch happened since this
      // build began, stamped with when the read started.
      if (userId != null &&
          lastKnownStore.epoch == epoch &&
          lastKnownStore.acceptsWritesFor(userId) &&
          ref.read(currentUserProvider)?.id == userId &&
          (coalescer.savedEpoch(relationshipId) != epoch ||
              previous == null ||
              storyRingRowsDiffer(previous, map))) {
        coalescer.markSaved(relationshipId, epoch);
        unawaited(
          lastKnownStore.write(
            StoryRingSnapshot(
              userId: userId,
              relationshipId: relationshipId,
              savedAt: fetch.startedAt,
              rows: fetch.rows,
            ),
          ),
        );
      }
      if (previous != null) {
        final dropped = storyRingDroppedThumbnailKeys(previous, map, now);
        if (dropped.isNotEmpty) unawaited(evictor.evict(dropped));
      }
      // Wave 5 (Wave 4 M-6): judge expiry on the server's clock when it
      // sends one, so a phone clock behind it never keeps an expired story
      // on the ring.
      DateTime? serverNow;
      for (final row in fetch.rows) {
        if (row.serverNow != null) {
          serverNow = row.serverNow;
          break;
        }
      }
      final skew =
          serverNow == null
              ? Duration.zero
              : storyServerClockOffset(
                serverNow: serverNow,
                startedAt: fetch.startedAt,
                receivedAt: now,
              );
      final expiry = storyRingExpiryDelay(fetch.rows, now.add(skew));
      if (expiry != null) refresh.after(expiry);
      // I-1: a good read signs again, once, any of its thumbnails that ran
      // out of retries (offline a while), so no ring stays grey.
      storyResignFailedThumbnails(
        ref.read(storySignedUrlCacheProvider),
        [for (final row in fetch.rows) row.newestThumbnailKey],
        (key) => ref.invalidate(storyMediaSignedUrlProvider(key)),
      );
      return map;
    });

/// The rings to paint while this session's first read is in flight or has
/// failed (03 M3): the snapshot, if it is this account's and this
/// relationship's and under a day old.
final storyRingLastKnownProvider = FutureProvider.autoDispose
    .family<Map<String, StoryRingSummary>?, String>((ref, relationshipId) async {
      final userId = ref.watch(currentUserProvider.select((u) => u?.id));
      if (userId == null) return null;
      final snapshot = await ref.watch(storyRingLastKnownStoreProvider).read();
      return snapshot?.usableFor(
        userId: userId,
        relationshipId: relationshipId,
        now: clock.now(),
      );
    });

/// A page-accumulating notifier shared by the reel and the calendar day
/// view — both walk `story_items` oldest-first with a keyset cursor and
/// both must restart from page one on a signal-triggered or manual
/// refresh rather than attempt to resume mid-walk.
///
/// Fix round 1 (task-2-review.md, findings 1-3): three bugs live in this
/// class's original version, all in the same handful of lines, and share
/// one fix.
///
/// **F1 — no `mounted` guard.** `refresh()` is kicked off from the
/// constructor via `unawaited`, and both `refresh()`/`loadMore()` write
/// `state` after an `await` with nothing checking the notifier is still
/// alive. Both providers are `.autoDispose`; closing the reel/day screen
/// while the first page (or any later page) is still in flight — an
/// entirely ordinary action, and the window is as wide as `_timeout`
/// (30s) — used to throw `Bad state: ... after dispose was called` in
/// debug (StateNotifier's `_debugIsMounted` assert) and silently write
/// into a dead notifier in release. Every post-await `state =` here is
/// now guarded by `mounted`.
///
/// **F2 — no generation token, so a stale fetch can clobber a newer
/// one.** Without an epoch, whichever `fetchPage` future resolves LAST
/// wins, regardless of which was issued last. A realtime signal arriving
/// while the initial load is still in flight used to start a second,
/// fresher fetch that could be overtaken by the stale first one — the
/// user would be shown pre-signal data and `_cursor`/`_hasMore` would be
/// left describing the stale page too. Worse during `loadMore`: the old
/// `_loadingMore` flag guarded `loadMore` against itself but not against
/// a concurrent `refresh()`, so a signal landing mid-`loadMore` produced
/// two interleaved walks and the refresh's own result was discarded
/// entirely once `loadMore`'s stale `current` closure resolved after it.
///
/// The fix is `_epoch`: `refresh()` always bumps it (a full re-read must
/// win over anything in flight, including another `loadMore`);
/// `loadMore()` captures it WITHOUT bumping (it must be superseded BY a
/// refresh, never supersede one). Every post-await continuation checks
/// `mounted && epoch == _epoch` before touching `state` or the paging
/// fields; a mismatch means a newer `refresh()` has already taken over
/// and this result is simply dropped.
///
/// **F3 — no coalescing.** The signal bumps on insert, soft delete,
/// first view AND archive-key swap (spec §5.5), so a burst of several
/// signals in one turn is the normal case, not the edge case, and each
/// one used to fire an independent `refresh()` — N signals produced N
/// full RPC round-trips. `refresh()` now coalesces: a call that arrives
/// while a refresh is already in flight does not start a second RPC
/// call immediately. It sets `_refreshAgainRequested` and returns; the
/// in-flight call, on completion, checks that flag and — if set — starts
/// exactly one more refresh (not one per coalesced request). A burst of
/// any size therefore produces at most two RPC calls: the one already
/// running, plus one more that is guaranteed to observe every signal
/// that arrived during the first. This is a request-coalescing scheme,
/// not a timer — no `Future.delayed`/`Timer` is introduced, so there is
/// nothing here for a test to need a real-clock wait for.
///
/// **Wave 1 R2:** a refresh keeps the previous value (`copyWithPrevious`):
/// while it runs the state is `AsyncLoading` with `isRefreshing == true`
/// and `valueOrNull` still the last list, and a failed refresh is an
/// `AsyncError` that still carries it. Only the very first load starts
/// from a plain, value-less `AsyncLoading`. Watchers that read
/// `valueOrNull` (the reel, the calendar day sheet) therefore never blank
/// out because a signal arrived.
abstract class _KeysetPager extends StateNotifier<AsyncValue<List<StoryItem>>> {
  _KeysetPager() : super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  /// The page fetch in flight. Every concurrent caller awaits this one
  /// future instead of returning early (02 #13).
  Future<void>? _loadMoreInFlight;

  /// Completes when the running refresh ends. A loadMore during a refresh
  /// waits for it and fetches nothing: the refresh restarts from page one.
  Completer<void>? _refreshDone;
  StoryPageCursor? _cursor;
  bool _hasMore = true;

  /// Bumped by every [refresh] call (never by [loadMore]). A post-await
  /// continuation whose captured epoch no longer matches [_epoch] has
  /// been superseded by a newer refresh and must not touch [state] or
  /// the paging fields — see this class's doc comment, finding F2.
  int _epoch = 0;

  /// True while a [refresh] RPC call is actually in flight. Distinct
  /// from [_refreshAgainRequested]: this one gates STARTING a new
  /// network call; that one records that another was asked for while
  /// this one was busy. See finding F3.
  bool _refreshing = false;

  /// Set when [refresh] is called while [_refreshing] is already true.
  /// Consumed (and cleared) by the in-flight call once it completes,
  /// which then performs exactly one more refresh — coalescing any
  /// number of calls that arrived during the first into one extra
  /// round-trip rather than one each. See finding F3.
  bool _refreshAgainRequested = false;

  /// Fetches one page starting after [after] (null for the first page).
  Future<StoryItemPage> fetchPage(StoryPageCursor? after);

  bool get hasMore => _hasMore;

  /// Restarts pagination from the first page. Used both for the initial
  /// load and for a signal/pull-to-refresh re-read — never resumed
  /// mid-walk, per this file's header. Coalesces concurrent calls (F3)
  /// and always supersedes anything else in flight, including a
  /// concurrent [loadMore] (F2).
  Future<void> refresh() async {
    if (_refreshing) {
      // Another refresh is already running this exact request for us —
      // don't start a second RPC call, just make sure the in-flight one
      // runs again once it's done so it observes whatever prompted this
      // call (F3).
      _refreshAgainRequested = true;
      return;
    }
    _refreshing = true;
    final done = _refreshDone = Completer<void>();
    try {
      do {
        _refreshAgainRequested = false;
        final epoch = ++_epoch; // always wins over anything in flight (F2)
        _loadMoreInFlight = null;
        // Keep what is on screen while re-reading (07a group B): the reel
        // and the day view must never blank to a spinner, or drop a reply
        // keyboard, because a signal arrived.
        if (mounted) {
          state = state.hasValue
              ? const AsyncLoading<List<StoryItem>>().copyWithPrevious(state)
              : const AsyncLoading<List<StoryItem>>();
        }
        try {
          final page = await fetchPage(null);
          if (!mounted || epoch != _epoch) continue; // superseded (F1/F2)
          _cursor = page.nextCursor;
          _hasMore = page.nextCursor != null;
          state = AsyncValue.data(page.items);
        } catch (error, stackTrace) {
          if (!mounted || epoch != _epoch) continue; // superseded (F1/F2)
          state = AsyncValue<List<StoryItem>>.error(
            error,
            stackTrace,
          ).copyWithPrevious(state);
        }
      } while (_refreshAgainRequested && mounted);
    } finally {
      _refreshing = false;
      _refreshDone = null;
      done.complete();
    }
  }

  /// Appends the next page. Shares a load already in flight (below), and
  /// is a no-op once the last page has been reached (a short page from the server,
  /// per `StoryItemPage.nextCursor`'s contract). A concurrent [refresh]
  /// always wins (F2): this method captures [_epoch] WITHOUT bumping it,
  /// so a refresh that starts and finishes while this call is in flight
  /// causes this call's result to be silently dropped instead of
  /// appended onto data the refresh already replaced.
  ///
  /// Wave 1: shares the in-flight future — every concurrent caller awaits
  /// the one page fetch, and a call during a refresh awaits that refresh
  /// and fetches nothing (the refresh restarts from page one).
  Future<void> loadMore() {
    final refreshing = _refreshDone;
    if (refreshing != null) return refreshing.future;
    final inFlight = _loadMoreInFlight;
    if (inFlight != null) return inFlight;
    if (!_hasMore) return Future.value();
    final current = state.valueOrNull;
    if (current == null) return Future.value(); // still loading page one
    return _loadMoreInFlight = _fetchMore(current);
  }

  Future<void> _fetchMore(List<StoryItem> current) async {
    final epoch = _epoch; // do NOT bump — must be supersedable by refresh()
    try {
      final page = await fetchPage(_cursor);
      if (!mounted || epoch != _epoch) {
        return _awaitSupersedingRefresh(); // a refresh superseded us (F2)
      }
      // Appends, never replaces — an insert that landed between pages
      // must show up as a NEW row after the ones already on screen, not
      // duplicate or displace them (spec §5.5, brief global constraints).
      state = AsyncValue.data([...current, ...page.items]);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
    } catch (error, stackTrace) {
      if (!mounted || epoch != _epoch) {
        return _awaitSupersedingRefresh(); // a refresh superseded us (F2)
      }
      // Keep the existing items visible; surface the load-more failure
      // without discarding what was already fetched.
      state = AsyncValue<List<StoryItem>>.error(
        error,
        stackTrace,
      ).copyWithPrevious(AsyncValue.data(current));
      _hasMore = true; // allow retrying loadMore
    } finally {
      if (epoch == _epoch) _loadMoreInFlight = null;
    }
  }

  /// A dropped page resolves its awaiters only once the refresh that
  /// superseded it has landed, so a caller re-reading the list sees the
  /// refreshed page one and may fetch page two itself. Resolving earlier
  /// let the reel read the old list, find no next item and close while
  /// more pages existed (batch-2 review, Important 1).
  Future<void> _awaitSupersedingRefresh() async {
    final refreshing = _refreshDone;
    if (refreshing != null && mounted) await refreshing.future;
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

/// A calendar month-range key for [storyDayCountsProvider], truncated to
/// y/m/d like [StoryDayKey].
///
/// **Fix round 1, finding 6.** The original `.family` key here was a bare
/// Dart record of `(relationshipId, startOn, endOn)`. Records use
/// structural equality over `DateTime`'s exact microsecond, so two ranges
/// built from `DateTime.now()` even a second apart compared UNEQUAL —
/// every rebuild that computed `endOn` freshly (e.g. "through today")
/// minted a brand new `.family` instance, each opening its own
/// `storyChangeSignalProvider` subscription and discarding the previous
/// one's cached result. `StoryDayKey` already truncates to y/m/d for
/// exactly this reason; this class makes the day-counts key consistent
/// with it, and with what `StoryReadRepository.listDayCounts` actually
/// sends on the wire (`dateOnly()` — day precision only).
@immutable
class StoryDayRangeKey {
  const StoryDayRangeKey({
    required this.relationshipId,
    required this.startOn,
    required this.endOn,
  });

  /// The calendar month around [day]: the key the date grid, the day sheet
  /// and the reel's delete share.
  factory StoryDayRangeKey.month({
    required String relationshipId,
    required DateTime day,
  }) => StoryDayRangeKey(
    relationshipId: relationshipId,
    startOn: DateTime(day.year, day.month, 1),
    endOn: DateTime(day.year, day.month + 1, 0),
  );

  final String relationshipId;
  final DateTime startOn;
  final DateTime endOn;

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  bool operator ==(Object other) =>
      other is StoryDayRangeKey &&
      other.relationshipId == relationshipId &&
      _sameDate(other.startOn, startOn) &&
      _sameDate(other.endOn, endOn);

  @override
  int get hashCode => Object.hash(
    relationshipId,
    startOn.year,
    startOn.month,
    startOn.day,
    endOn.year,
    endOn.month,
    endOn.day,
  );
}

/// The last day counts read per month this session, to tell which past
/// stories a re-read shows deleted (05 #6). A new, empty map per account.
final storyDayCountsMemoProvider =
    Provider<Map<StoryDayRangeKey, List<StoryDayCount>>>((ref) {
      ref.watch(currentUserProvider.select((u) => u?.id));
      return {};
    });

/// `list_story_day_counts` for one relationship over `[startOn, endOn]`
/// (spec §5.5) — backs the calendar month view. Re-fetches on a change
/// signal for the same relationship, including on app resume (finding 4).
final storyDayCountsProvider = FutureProvider.autoDispose
    .family<List<StoryDayCount>, StoryDayRangeKey>((ref, key) async {
      ref.watch(storyChangeSignalProvider(key.relationshipId));
      final gateway = ref.watch(storyReadGatewayProvider);
      final memo = ref.watch(storyDayCountsMemoProvider);
      // Read before the await, like the ring summary: a signal landing as
      // the fetch returns must not lose this read's dropped keys (M-2).
      final evictor = ref.read(storyMediaEvictorProvider);
      final counts = await gateway.listDayCounts(
        relationshipId: key.relationshipId,
        startOn: key.startOn,
        endOn: key.endOn,
      );
      final dropped = storyDayCountDroppedKeys(memo[key], counts);
      memo[key] = counts;
      if (dropped.isNotEmpty) {
        unawaited(evictor.evict(dropped));
      }
      // I-1: the calendar's avatars and day rings, as the Conversations
      // rings do.
      storyResignFailedThumbnails(
        ref.read(storySignedUrlCacheProvider),
        [
          for (final count in counts)
            if (count.newestThumbnailKey != null) count.newestThumbnailKey!,
        ],
        (thumbnailKey) =>
            ref.invalidate(storyMediaSignedUrlProvider(thumbnailKey)),
      );
      return counts;
    });

@immutable
class StoryDayKey {
  const StoryDayKey({
    required this.relationshipId,
    required this.occurredOn,
    this.authorId,
  });

  final String relationshipId;
  final DateTime occurredOn;

  /// One author's stories on the day (a calendar ring, Wave 5); null is the
  /// whole day.
  final String? authorId;

  @override
  bool operator ==(Object other) =>
      other is StoryDayKey &&
      other.relationshipId == relationshipId &&
      other.authorId == authorId &&
      other.occurredOn.year == occurredOn.year &&
      other.occurredOn.month == occurredOn.month &&
      other.occurredOn.day == occurredOn.day;

  @override
  int get hashCode => Object.hash(
    relationshipId,
    authorId,
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
      authorId: _key.authorId,
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

/// In-memory signed URLs by storage key (STORIES.md §4.1 as amended, Wave
/// 4). A new, empty instance per signed-in account.
final storySignedUrlCacheProvider = Provider<StorySignedUrlCache>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final cache = StorySignedUrlCache();
  ref.onDispose(cache.dispose);
  return cache;
});

/// Forgets a story's media on this phone: its signed URLs and its image
/// bytes in the shared disk cache (both keyed by storage key; 05 #6).
/// Never throws.
class StoryMediaEvictor {
  StoryMediaEvictor(this._ref);
  final Ref _ref;

  Future<void> evict(Iterable<String> storageKeys) async {
    final keys = {
      for (final key in storageKeys)
        if (key.isNotEmpty) key,
    };
    if (keys.isEmpty) return;
    _ref.read(storySignedUrlCacheProvider).evict(keys);
    await _ref.read(chatImageCacheProvider).removeKeys(keys);
  }
}

final storyMediaEvictorProvider = Provider<StoryMediaEvictor>(
  StoryMediaEvictor.new,
);

/// Final review I-1: signs again, once, each of [keys] whose last signing
/// failed and none is in flight, with a fresh run of retries. Called on a
/// good ring or month read and by the rings' Retry, so a thumbnail that
/// spent its retries offline is not grey for the rest of the session. A
/// key that always fails stays bounded: a read that names it costs one
/// run, and a read that no longer names it costs nothing.
void storyResignFailedThumbnails(
  StorySignedUrlCache cache,
  Iterable<String> keys,
  void Function(String key) resign,
) {
  for (final key in {...keys}) {
    if (key.isEmpty || !cache.hasFailed(key)) continue;
    cache.resetFailures(key);
    resign(key);
  }
}

/// A signed URL for [storageKey]. Reuses the one whose request started
/// under 540 s ago (rings and calendar share it; it is never stored on
/// disk), and re-signs for a mounted holder when it turns 540 s old. A failed
/// signing is an error, not a silent null, and retries itself on a backoff
/// while Attune is on screen (03 M5), at most [kStorySignMaxAutoRetries]
/// times; then once on each return to the screen, and again whenever a ring
/// or month read names the key ([storyResignFailedThumbnails]).
final storyMediaSignedUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, storageKey) async {
      final cache = ref.watch(storySignedUrlCacheProvider);
      final gateway = ref.watch(storyReadGatewayProvider);
      final refresh = StoryVisibleRefresh(ref);
      // Final review M-2: a URL from before a wipe, a delete or an account
      // change is not kept on show while this signs again (a loading or
      // failed rebuild would still carry it), so no image loader fetches a
      // wiped thumbnail back to disk with it: no URL until this one lands.
      // A URL merely past 540 s stays up while it is renewed (no flash).
      if (!cache.knows(storageKey) && ref.state.hasValue) {
        ref.state = const AsyncData<String?>(null);
      }
      // One clock read decides both the reuse and its re-sign time (M-3).
      final reused = cache.reusable(storageKey);
      if (reused != null) {
        // A mounted holder re-signs when this URL turns 540 s old, before
        // the 600 s TTL, so no image loader is ever handed an expired one
        // (same cache key: no re-download, no flash).
        refresh.after(reused.left);
        return reused.url;
      }
      final startedAt = clock.now();
      String? url;
      cache.beginSigning(storageKey);
      try {
        url = await gateway.signMediaUrl(storageKey);
      } catch (_) {
        url = null;
      } finally {
        cache.endSigning(storageKey);
      }
      if (refresh.disposed) return url;
      if (url == null) {
        final failures = cache.recordFailure(storageKey);
        if (failures <= kStorySignMaxAutoRetries) {
          refresh.after(storySignRetryDelay(failures));
        } else {
          // I-1: out of retries, one more try when Attune is back on screen.
          refresh.onNextReturn();
        }
        throw StorySignFailure(storageKey);
      }
      cache.put(storageKey, url, mintedAt: startedAt);
      final left = cache.freshFor(storageKey);
      refresh.after(
        left == null || left < const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : left,
      );
      return url;
    });
