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
import 'package:attune/features/stories/data/story_read_repository.dart';
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
abstract class _KeysetPager extends StateNotifier<AsyncValue<List<StoryItem>>> {
  _KeysetPager() : super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  bool _loadingMore = false;
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
    try {
      do {
        _refreshAgainRequested = false;
        final epoch = ++_epoch; // always wins over anything in flight (F2)
        if (mounted) state = const AsyncValue.loading();
        _cursor = null;
        _hasMore = true;
        try {
          final page = await fetchPage(null);
          if (!mounted || epoch != _epoch) continue; // superseded (F1/F2)
          _cursor = page.nextCursor;
          _hasMore = page.nextCursor != null;
          state = AsyncValue.data(page.items);
        } catch (error, stackTrace) {
          if (!mounted || epoch != _epoch) continue; // superseded (F1/F2)
          state = AsyncValue.error(error, stackTrace);
        }
      } while (_refreshAgainRequested && mounted);
    } finally {
      _refreshing = false;
    }
  }

  /// Appends the next page. A no-op while a load is already in flight or
  /// once the last page has been reached (a short page from the server,
  /// per `StoryItemPage.nextCursor`'s contract). A concurrent [refresh]
  /// always wins (F2): this method captures [_epoch] WITHOUT bumping it,
  /// so a refresh that starts and finishes while this call is in flight
  /// causes this call's result to be silently dropped instead of
  /// appended onto data the refresh already replaced.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.valueOrNull;
    if (current == null) return; // still loading the first page
    final epoch = _epoch; // do NOT bump — must be supersedable by refresh()
    _loadingMore = true;
    try {
      final page = await fetchPage(_cursor);
      if (!mounted || epoch != _epoch) return; // a refresh superseded us (F2)
      // Appends, never replaces — an insert that landed between pages
      // must show up as a NEW row after the ones already on screen, not
      // duplicate or displace them (spec §5.5, brief global constraints).
      state = AsyncValue.data([...current, ...page.items]);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
    } catch (error, stackTrace) {
      if (!mounted || epoch != _epoch) return; // a refresh superseded us (F2)
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

/// `list_story_day_counts` for one relationship over `[startOn, endOn]`
/// (spec §5.5) — backs the calendar month view. Re-fetches on a change
/// signal for the same relationship, including on app resume (finding 4).
final storyDayCountsProvider = FutureProvider.autoDispose
    .family<List<StoryDayCount>, StoryDayRangeKey>((ref, key) async {
      ref.watch(storyChangeSignalProvider(key.relationshipId));
      final gateway = ref.watch(storyReadGatewayProvider);
      return gateway.listDayCounts(
        relationshipId: key.relationshipId,
        startOn: key.startOn,
        endOn: key.endOn,
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
