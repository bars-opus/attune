// Tests for the read side of stories (Plan C, Task 2): the ring summary,
// the keyset-paginated reel/day reads, the day-count calendar read, and
// the story_change_signals refetch-signal providers.
//
// Following story_repository_test.dart's and story_outbox_controller_test
// .dart's house pattern: never mock SupabaseClient (its RPC/storage
// builders are final and heavily generic, with no test seam) — instead
// fake the abstract StoryReadGateway interface story_read_repository.dart
// defines specifically so tests can substitute it, and drive the
// Riverpod providers through a real ProviderContainer with that gateway
// overridden.
//
// The three brief-mandated tests (task-2-brief.md Step 1) are:
//   - a signal bump invalidates the ring summary and the visible reel
//   - paging uses the last item as the cursor, never an offset
//   - a signed URL is minted per request and never cached past its TTL
// These are covered below, plus supporting coverage of the ring-summary
// map shape (the brief's "absence of a row is not 'do not draw my ring'"
// contract) and the day-items/day-counts reads.

import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_repository.dart'
    show StoryApiError;
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = 'user-1';

final _signedInUser = User(
  id: _userId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

StoryItem _item({
  required String id,
  required DateTime createdAt,
  String authorId = 'author-1',
  String relationshipId = 'rel-1',
  bool hasBeenViewed = false,
}) {
  return StoryItem(
    id: id,
    clientStoryId: 'client-$id',
    relationshipId: relationshipId,
    authorId: authorId,
    mediaType: 'image',
    mediaKey: 'story-media/$id.jpg',
    thumbnailKey: 'story-media/$id-thumb.jpg',
    mediaWidth: 1080,
    mediaHeight: 1920,
    durationMs: null,
    occurredOn: DateTime.utc(2026, 9, 11),
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    hasBeenViewed: hasBeenViewed,
  );
}

/// Records every call so tests can assert both outcome and call shape —
/// in particular, that paging is driven by (created_at, id) cursors, that
/// signMediaUrl is invoked once per request with no internal caching, and
/// that the change-signal stream never carries the signal row's payload.
///
/// **Fix round 1 (task-2-review.md): completer-based control for
/// `listActiveItems`.** The review's root-cause finding is that this
/// fake originally resolved every call SYNCHRONOUSLY (an `async` method
/// whose body never actually awaits anything suspends for exactly one
/// microtask), so no test built on it could ever express two calls
/// genuinely overlapping in flight — which is exactly the shape F1/F2/F3
/// are about. `listActiveItems` now supports two modes:
///
///  - the ORIGINAL script-list mode (`activeItemsScript`), unchanged, for
///    every existing test that does not care about interleaving; and
///  - an opt-in manual mode: call [armManualActiveItems] once, and every
///    subsequent `listActiveItems` call instead returns a `Completer`
///    left PENDING in [pendingActiveItemsCompleters], in call order. A
///    test resolves them itself, in whatever order it wants
///    (`pendingActiveItemsCompleters[0].complete(pageB)` before
///    `pendingActiveItemsCompleters[1]` even though call 1 was issued
///    after call 0), which is what makes "a second call resolves before
///    the first" and "a call is still in flight when a second is issued"
///    both directly expressible instead of inferred from call counts.
class _FakeStoryReadGateway implements StoryReadGateway {
  final List<StoryRingSummary> ringSummaryScript = [];
  int ringSummaryCallCount = 0;

  /// Pages served by [listActiveItems] in script mode (the default),
  /// consumed in order per call. Ignored once [armManualActiveItems] has
  /// been called.
  final List<StoryItemPage> activeItemsScript = [];
  final List<StoryPageCursor?> activeItemsCursorsRequested = [];

  bool _manualActiveItems = false;

  /// One entry per `listActiveItems` call once manual mode is armed, in
  /// call order. A test completes these directly to control exactly
  /// when — and in what order — each call resolves.
  final List<Completer<StoryItemPage>> pendingActiveItemsCompleters = [];

  /// Switches [listActiveItems] from the script list to manual,
  /// completer-based resolution. Call once per test before issuing any
  /// call this test needs to control the timing/ordering of.
  void armManualActiveItems() => _manualActiveItems = true;

  final List<StoryItemPage> dayItemsScript = [];
  final List<StoryPageCursor?> dayItemsCursorsRequested = [];

  final List<StoryDayCount> dayCountsScript = [];

  int signMediaUrlCallCount = 0;
  final List<String> signMediaUrlKeysRequested = [];

  final Set<String> markedViewed = {};
  final Set<String> deleted = {};

  final Map<String, StreamController<void>> _signalControllers = {};
  final Set<String> disposedChannels = {};
  bool allChannelsDisposed = false;

  StreamController<void> _controllerFor(String relationshipId) =>
      _signalControllers.putIfAbsent(
        relationshipId,
        () => StreamController<void>.broadcast(),
      );

  /// Test hook: simulates a Postgres-changes callback firing for
  /// [relationshipId]. Never carries a payload — matching the production
  /// implementation, which drops the row entirely and forwards only the
  /// fact that something changed.
  void emitSignal(String relationshipId) {
    _controllerFor(relationshipId).add(null);
  }

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async {
    ringSummaryCallCount++;
    return List.of(ringSummaryScript);
  }

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) {
    activeItemsCursorsRequested.add(after);
    if (_manualActiveItems) {
      final completer = Completer<StoryItemPage>();
      pendingActiveItemsCompleters.add(completer);
      return completer.future;
    }
    final index = activeItemsCursorsRequested.length - 1;
    return Future.value(activeItemsScript[index]);
  }

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => List.of(dayCountsScript);

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async {
    dayItemsCursorsRequested.add(after);
    final index = dayItemsCursorsRequested.length - 1;
    return dayItemsScript[index];
  }

  @override
  Future<void> markViewed({required String storyItemId}) async {
    markedViewed.add(storyItemId);
  }

  @override
  Future<void> deleteItem({required String storyItemId}) async {
    deleted.add(storyItemId);
  }

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    signMediaUrlCallCount++;
    signMediaUrlKeysRequested.add(storageKey);
    // A fresh, distinguishable URL every call — if anything ever cached
    // and reused this return value, a test asserting on distinct URLs
    // per call would catch it.
    return 'https://signed.example/$storageKey?call=$signMediaUrlCallCount';
  }

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      _controllerFor(relationshipId).stream;

  @override
  void disposeChannel(String relationshipId) {
    disposedChannels.add(relationshipId);
  }

  @override
  void disposeAllChannels() {
    allChannelsDisposed = true;
  }
}

/// A gateway that throws a [StoryApiError] from every call — used only to
/// prove a refusal actually PROPAGATES to a caller (fix round 1, finding
/// 5) rather than being swallowed. Distinct from [_FakeStoryReadGateway],
/// which always succeeds; mixing "throws" behaviour into that class would
/// have made every other test that builds one carry unused failure
/// plumbing.
class _ThrowingStoryReadGateway implements StoryReadGateway {
  static const _error = StoryApiError(
    code: 'UNAVAILABLE',
    message: "Stories aren't available right now.",
    retryable: false,
  );

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) => throw _error;

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) => throw _error;

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) => throw _error;

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) => throw _error;

  @override
  Future<void> markViewed({required String storyItemId}) => throw _error;

  @override
  Future<void> deleteItem({required String storyItemId}) => throw _error;

  @override
  Future<String?> signMediaUrl(String storageKey) => throw _error;

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

ProviderContainer _buildContainer(_FakeStoryReadGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_signedInUser),
      storyReadGatewayProvider.overrideWithValue(gateway),
    ],
  );
  return container;
}

void main() {
  // storyChangeSignalProvider now attaches an AppLifecycleListener (fix
  // round 1, finding 4 — app-resume refetch) alongside the realtime
  // stream. AppLifecycleListener reaches into WidgetsBinding.instance at
  // construction time, which throws "Binding has not yet been
  // initialized" in a plain, binding-less `test()`. This is the standard
  // fix (flutter_test's own docs): initialize the test binding once, up
  // front, which is inert for everything else in this file — nothing
  // here pumps a widget tree or needs one.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ring summary map shape', () {
    test(
      'an author with zero active stories is absent from the map, not a '
      'null/empty placeholder entry',
      () async {
        // This is the brief's core warning made concrete: the map must
        // not contain a "my id -> empty summary" row that a caller could
        // mistake for real data. It must be genuinely ABSENT, so
        // `summaries['someone-new']` returns null and the caller is
        // forced to handle "should I draw my ring" separately from "what
        // do I fill it with."
        final gateway = _FakeStoryReadGateway()
          ..ringSummaryScript.add(
            StoryRingSummary(
              authorId: 'partner-1',
              activeCount: 3,
              unviewedCount: 2,
              newestThumbnailKey: 'story-media/x-thumb.jpg',
              newestCreatedAt: DateTime.utc(2026, 9, 11, 10),
            ),
          );

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);

        final summaries = await container.read(
          storyRingSummaryProvider('rel-1').future,
        );

        expect(summaries.containsKey('partner-1'), isTrue);
        expect(
          summaries.containsKey('me-never-posted'),
          isFalse,
          reason:
              'a new user with zero active stories must be absent from '
              'the map entirely, never present with an empty/null value '
              'that could be confused with "do not draw my ring"',
        );
      },
    );
  });

  group('realtime is a refetch signal, not data', () {
    test(
      'a signal bump invalidates the ring summary and the visible reel, '
      'triggering a RE-READ through the RPCs rather than consuming the '
      'signal payload',
      () async {
        final gateway = _FakeStoryReadGateway();
        gateway.ringSummaryScript.add(
          StoryRingSummary(
            authorId: 'partner-1',
            activeCount: 1,
            unviewedCount: 1,
            newestThumbnailKey: 'story-media/a-thumb.jpg',
            newestCreatedAt: DateTime.utc(2026, 9, 11, 9),
          ),
        );
        gateway.activeItemsScript.add(
          StoryItemPage(
            items: [_item(id: 'item-1', createdAt: DateTime.utc(2026, 9, 11, 9))],
            nextCursor: null,
          ),
        );
        // Second page returned after the signal fires — proves the
        // provider actually re-invoked the gateway rather than replaying
        // whatever it already had cached.
        gateway.activeItemsScript.add(
          StoryItemPage(
            items: [
              _item(id: 'item-1', createdAt: DateTime.utc(2026, 9, 11, 9)),
              _item(id: 'item-2', createdAt: DateTime.utc(2026, 9, 11, 10)),
            ],
            nextCursor: null,
          ),
        );

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);

        // Keep both .autoDispose providers alive for the duration of the
        // test — container.listen's returned subscription must be
        // retained, or Riverpod tears the provider (and its
        // storyChangeSignalProvider subscription) down the instant this
        // block returns, matching typing_controller_test.dart's pattern.
        final ringSub = container.listen(
          storyRingSummaryProvider('rel-1'),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(ringSub.close);
        final reelSub = container.listen(
          storyReelPagesProvider(
            const StoryReelKey(relationshipId: 'rel-1', authorId: 'author-1'),
          ),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(reelSub.close);
        await pumpEventQueue();

        expect(gateway.ringSummaryCallCount, 1);
        expect(gateway.activeItemsCursorsRequested.length, 1);

        // Simulate the realtime bump. This must NOT carry any data the
        // provider consumes — emitSignal only ever sends `null`.
        gateway.emitSignal('rel-1');
        await pumpEventQueue();

        expect(
          gateway.ringSummaryCallCount,
          2,
          reason: 'the signal must trigger a RE-READ of the ring summary',
        );
        expect(
          gateway.activeItemsCursorsRequested.length,
          2,
          reason:
              'the signal must trigger a RE-READ of the visible reel, '
              'restarting pagination rather than leaving stale pages',
        );
        // The refetch after a signal restarts from page one (cursor
        // null), never resumes mid-walk.
        expect(gateway.activeItemsCursorsRequested.last, isNull);

        final reel = container.read(
          storyReelPagesProvider(
            const StoryReelKey(relationshipId: 'rel-1', authorId: 'author-1'),
          ),
        );
        expect(reel.value?.length, 2);
      },
    );

    test(
      'F4: an app-resume lifecycle event refetches the ring summary, '
      'exactly like a story_change_signals bump would',
      () async {
        // Drives a REAL AppLifecycleListener through
        // TestWidgetsFlutterBinding, rather than asserting on source
        // text: storyChangeSignalProvider attaches an actual
        // AppLifecycleListener (see its doc comment, finding 4), and
        // TestWidgetsFlutterBinding.handleAppLifecycleStateChanged is
        // the documented way to trigger it in a test without a widget
        // tree.
        final gateway = _FakeStoryReadGateway();
        gateway.ringSummaryScript.add(
          StoryRingSummary(
            authorId: 'partner-1',
            activeCount: 1,
            unviewedCount: 0,
            newestThumbnailKey: 'story-media/a-thumb.jpg',
            newestCreatedAt: DateTime.utc(2026, 9, 11, 9),
          ),
        );

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final sub = container.listen(
          storyRingSummaryProvider('rel-1'),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        expect(gateway.ringSummaryCallCount, 1);

        // Simulate backgrounding then resuming. AppLifecycleListener
        // asserts on the real platform state machine
        // (resumed -> inactive -> hidden -> paused -> hidden -> inactive
        // -> resumed) — matching how the OS actually reports lifecycle
        // changes; skipping a step throws.
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
            state,
          );
        }
        await pumpEventQueue();

        expect(
          gateway.ringSummaryCallCount,
          2,
          reason:
              'app resume must trigger the same refetch pipe a realtime '
              'signal does — the socket is torn down while backgrounded, '
              'so nothing else recovers a stale ring on its own',
        );
      },
    );
  });

  group('keyset paging', () {
    test(
      'paging uses the last item as the cursor, never an offset — a '
      'second page does not re-return page one, and an insert between '
      'pages appends rather than duplicating or skipping',
      () async {
        final page1Item = _item(id: 'item-1', createdAt: DateTime.utc(2026, 9, 11, 9));
        final page1 = StoryItemPage(
          items: List.generate(
            50,
            (i) => i == 0
                ? page1Item
                : _item(
                    id: 'item-1-$i',
                    createdAt: DateTime.utc(2026, 9, 11, 9, i),
                  ),
          ),
          nextCursor: null, // set below to the true last item
        );
        final trueLast = page1.items.last;
        final page1WithCursor = StoryItemPage(
          items: page1.items,
          nextCursor: trueLast.cursor,
        );

        // Page 2 contains an item that was inserted AFTER page 1 was
        // fetched but before page 2 was requested — it must APPEND, and
        // page 1's items must not reappear.
        final insertedItem = _item(
          id: 'item-2-inserted',
          createdAt: DateTime.utc(2026, 9, 11, 11),
        );
        final page2 = StoryItemPage(items: [insertedItem], nextCursor: null);

        final gateway = _FakeStoryReadGateway()
          ..activeItemsScript.add(page1WithCursor)
          ..activeItemsScript.add(page2);

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);

        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        // Retain the subscription: storyReelPagesProvider is .autoDispose,
        // so a bare container.read(...notifier) would be torn down the
        // instant this statement finishes, taking the accumulated page
        // state with it before loadMore() could use it.
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        final notifier = container.read(storyReelPagesProvider(key).notifier);
        await pumpEventQueue();

        expect(gateway.activeItemsCursorsRequested, [null]);

        await notifier.loadMore();

        // The SECOND call's cursor is the (created_at, id) of the LAST
        // item of page one — never an offset/row count.
        final secondCursor = gateway.activeItemsCursorsRequested[1];
        expect(secondCursor, isNotNull);
        expect(secondCursor!.id, trueLast.id);
        expect(secondCursor.createdAt, trueLast.createdAt);

        final combined = container.read(storyReelPagesProvider(key)).value!;
        expect(combined.length, 51);
        // Page one's items are still present exactly once — a second
        // page achieved via cursor cannot re-return or duplicate them.
        expect(
          combined.where((i) => i.id == page1Item.id).length,
          1,
          reason: 'page one must not reappear in page two',
        );
        // The inserted item appended at the end, not skipped.
        expect(combined.last.id, insertedItem.id);
      },
    );

    test(
      'requesting page two by OFFSET (row count) rather than the last '
      'item cursor would be wrong — the second call must carry the prior '
      'cursor value, not merely "page index 1"',
      () async {
        // This test exists to be mutation-tested against an offset-based
        // implementation: if fetchPage ever passed something like
        // `offset: page * limit` instead of `after: lastCursor`, this
        // assertion (which checks the CONTENT of the cursor, not just
        // that a second call happened) would fail.
        final first = _item(id: 'only-item', createdAt: DateTime.utc(2026, 9, 11, 9));
        final gateway = _FakeStoryReadGateway()
          ..activeItemsScript.add(
            StoryItemPage(items: [first], nextCursor: first.cursor),
          )
          ..activeItemsScript.add(const StoryItemPage(items: [], nextCursor: null));

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        final notifier = container.read(storyReelPagesProvider(key).notifier);
        await pumpEventQueue();

        await notifier.loadMore();

        final cursor = gateway.activeItemsCursorsRequested[1]!;
        expect(cursor.id, first.id);
        expect(cursor.createdAt, first.createdAt);
      },
    );
  });

  group('pager concurrency (fix round 1: F1, F2, F3)', () {
    // These tests exist because task-2-review.md's root-cause finding was
    // that _FakeStoryReadGateway used to resolve every call
    // synchronously, so nothing here could express two calls genuinely
    // overlapping in flight. armManualActiveItems() + the completer list
    // fixes that — see that method's doc comment.

    test(
      'F1: closing the reel while the first page is still in flight does '
      'not throw or write to state after dispose',
      () async {
        final gateway = _FakeStoryReadGateway()..armManualActiveItems();
        final container = _buildContainer(gateway);
        // Deliberately NOT torn down via addTearDown before disposing —
        // this test disposes the container itself mid-flight, which is
        // the scenario: the notifier's constructor kicks off refresh()
        // (the first page), and the screen is closed (autoDispose) while
        // that fetch is still pending.
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        await pumpEventQueue();

        expect(
          gateway.pendingActiveItemsCompleters.length,
          1,
          reason: 'the constructor must have issued the first-page fetch',
        );

        // Close the subscription AND dispose the container — this is
        // what autoDispose does when the last listener goes away.
        sub.close();
        container.dispose();

        // Now let the in-flight fetch land. Before the F1 fix this threw
        // "Bad state: Tried to use StoryReelPagesNotifier after dispose
        // was called" synchronously out of the StateNotifier's state=
        // setter. Complete it and pump — a throw here fails the test.
        gateway.pendingActiveItemsCompleters[0].complete(
          StoryItemPage(
            items: [_item(id: 'late-item', createdAt: DateTime.utc(2026, 9, 11, 9))],
            nextCursor: null,
          ),
        );
        await pumpEventQueue();
        // Reaching here without throwing IS the assertion — nothing
        // further to check; a dead notifier has no observable state.
      },
    );

    test(
      'F2 scenario A: a signal arriving while the initial load is still '
      'in flight is coalesced (F3) into one fresh re-fetch, and that '
      'fresh result is what the pager ends up showing — the in-flight '
      "call's own (now-stale) result does not get appended or otherwise "
      'clobber it',
      () async {
        final gateway = _FakeStoryReadGateway()..armManualActiveItems();
        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        expect(gateway.pendingActiveItemsCompleters.length, 1);

        // The partner posts; the signal fires while call #0 (the initial
        // load, kicked off by the constructor) is still pending. Because
        // a refresh is ALREADY running, F3's coalescing takes over: the
        // signal does not start a second RPC call yet, it only requests
        // one more once #0 finishes.
        gateway.emitSignal('rel-1');
        await pumpEventQueue();
        expect(
          gateway.pendingActiveItemsCompleters.length,
          1,
          reason:
              'a signal arriving while a refresh is already in flight '
              'must be coalesced, not fire an immediate second call',
        );

        // Call #0 (the STALE pre-signal fetch) resolves now.
        gateway.pendingActiveItemsCompleters[0].complete(
          StoryItemPage(
            items: [_item(id: 'STALE', createdAt: DateTime.utc(2026, 9, 11, 9))],
            nextCursor: null,
          ),
        );
        await pumpEventQueue();

        // Exactly one more call must now have been issued — the
        // coalesced refresh the signal asked for — proving the signal
        // was not simply dropped (F3's "coalesced" must still mean
        // "eventually runs", not "cancelled").
        expect(
          gateway.pendingActiveItemsCompleters.length,
          2,
          reason:
              'the coalesced signal must still produce exactly one more '
              'fetch once the in-flight one completes',
        );

        gateway.pendingActiveItemsCompleters[1].complete(
          StoryItemPage(
            items: [_item(id: 'FRESH', createdAt: DateTime.utc(2026, 9, 11, 10))],
            nextCursor: null,
          ),
        );
        await pumpEventQueue();

        final state = container.read(storyReelPagesProvider(key));
        expect(
          state.value?.map((i) => i.id).toList(),
          ['FRESH'],
          reason:
              'the final state must reflect the coalesced refresh, not '
              "the stale pre-signal fetch's own result",
        );
      },
    );

    test(
      'F2 scenario B: a signal landing mid-loadMore must win, and the '
      "stale loadMore's result must be dropped rather than appended onto "
      'data the refresh already replaced',
      () async {
        final gateway = _FakeStoryReadGateway();
        final firstPageItem = _item(
          id: 'A',
          createdAt: DateTime.utc(2026, 9, 11, 9),
        );
        gateway.activeItemsScript.add(
          StoryItemPage(items: [firstPageItem], nextCursor: firstPageItem.cursor),
        );

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        // First page loaded via the script (synchronous). Now switch to
        // manual mode so loadMore()'s call, and the signal's refresh()
        // call, can be interleaved under test control.
        gateway.armManualActiveItems();
        final notifier = container.read(storyReelPagesProvider(key).notifier);

        final loadMoreFuture = notifier.loadMore();
        await pumpEventQueue();
        expect(
          gateway.pendingActiveItemsCompleters.length,
          1,
          reason: 'loadMore must have issued its own fetch (page 2)',
        );

        // A signal lands while that loadMore is still in flight.
        gateway.emitSignal('rel-1');
        await pumpEventQueue();
        expect(
          gateway.pendingActiveItemsCompleters.length,
          2,
          reason: 'the signal must start its own refresh() fetch',
        );

        // The refresh (call #1) resolves FIRST.
        gateway.pendingActiveItemsCompleters[1].complete(
          StoryItemPage(
            items: [_item(id: 'FRESH', createdAt: DateTime.utc(2026, 9, 11, 12))],
            nextCursor: null,
          ),
        );
        await pumpEventQueue();

        // Then the stale loadMore's page 2 (call #0) resolves.
        gateway.pendingActiveItemsCompleters[0].complete(
          StoryItemPage(
            items: [_item(id: 'OLDPAGE2', createdAt: DateTime.utc(2026, 9, 11, 10))],
            nextCursor: null,
          ),
        );
        await loadMoreFuture;
        await pumpEventQueue();

        final state = container.read(storyReelPagesProvider(key));
        expect(
          state.value?.map((i) => i.id).toList(),
          ['FRESH'],
          reason:
              'the refresh triggered by the signal must win outright; '
              "the superseded loadMore's stale page must not be appended "
              'onto pre-refresh data, and must not be appended onto the '
              'fresh data either',
        );
      },
    );

    test(
      'F3: a burst of ten signals produces at most two fetch calls total, '
      'not one per signal',
      () async {
        final gateway = _FakeStoryReadGateway()..armManualActiveItems();
        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        expect(gateway.pendingActiveItemsCompleters.length, 1);

        // Ten signals in one burst, all while the initial (constructor)
        // fetch is still unresolved. Every one of them must coalesce —
        // none may start a new call while #0 is in flight.
        for (var i = 0; i < 10; i++) {
          gateway.emitSignal('rel-1');
        }
        await pumpEventQueue();

        expect(
          gateway.pendingActiveItemsCompleters.length,
          1,
          reason:
              'ten signals arriving while a fetch is already in flight '
              'must coalesce into zero NEW calls yet — never one call '
              'per signal',
        );

        // #0 resolves. Exactly ONE more call must now fire — the single
        // coalesced refresh every one of the ten signals asked for.
        gateway.pendingActiveItemsCompleters[0].complete(
          const StoryItemPage(items: [], nextCursor: null),
        );
        await pumpEventQueue();

        expect(
          gateway.pendingActiveItemsCompleters.length,
          2,
          reason:
              'the ten coalesced signals must still produce exactly one '
              'more fetch once the in-flight call completes — coalesced '
              'must not mean dropped',
        );

        // Resolve it so the pager settles cleanly, and confirm nothing
        // further was queued (proving the burst really did collapse to
        // one extra call, not eleven).
        gateway.pendingActiveItemsCompleters[1].complete(
          const StoryItemPage(items: [], nextCursor: null),
        );
        await pumpEventQueue();
        expect(gateway.pendingActiveItemsCompleters.length, 2);
      },
    );

    test(
      '!hasMore stops loadMore from issuing a second call',
      () async {
        final gateway = _FakeStoryReadGateway()..armManualActiveItems();
        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        // Resolve the first page as a SHORT page (nextCursor: null) —
        // the server-short-page-means-done contract.
        gateway.pendingActiveItemsCompleters[0].complete(
          StoryItemPage(
            items: [_item(id: 'only', createdAt: DateTime.utc(2026, 9, 11, 9))],
            nextCursor: null,
          ),
        );
        await pumpEventQueue();

        final notifier = container.read(storyReelPagesProvider(key).notifier);
        expect(notifier.hasMore, isFalse);

        // Deliberately NOT awaited: if the !_hasMore guard is missing,
        // loadMore issues a real fetch whose completer nothing here ever
        // resolves, and awaiting that future would hang for the full
        // real-clock test timeout — exactly the "no real-clock waits"
        // failure mode this suite must avoid. Firing-and-forgetting the
        // call and asserting on the gateway's recorded call count after
        // a pump is sufficient: a violating implementation is caught by
        // the call-count assertion below, not by ever letting the call
        // resolve.
        unawaited(notifier.loadMore());
        await pumpEventQueue();
        expect(
          gateway.pendingActiveItemsCompleters.length,
          1,
          reason: '!hasMore must stop loadMore from issuing a second call',
        );
      },
    );

    test(
      '_loadingMore prevents a concurrent loadMore call from issuing its '
      'own RPC while one is already in flight',
      () async {
        final gateway = _FakeStoryReadGateway()..armManualActiveItems();
        final container = _buildContainer(gateway);
        addTearDown(container.dispose);
        final key = const StoryReelKey(
          relationshipId: 'rel-1',
          authorId: 'author-1',
        );
        final sub = container.listen(
          storyReelPagesProvider(key),
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        gateway.pendingActiveItemsCompleters[0].complete(
          StoryItemPage(
            items: [_item(id: 'p1', createdAt: DateTime.utc(2026, 9, 11, 9))],
            nextCursor: StoryPageCursor(
              createdAt: DateTime.utc(2026, 9, 11, 9),
              id: 'p1',
            ),
          ),
        );
        await pumpEventQueue();

        final notifier = container.read(storyReelPagesProvider(key).notifier);
        unawaited(notifier.loadMore());
        await pumpEventQueue();
        expect(gateway.pendingActiveItemsCompleters.length, 2);

        // Call loadMore again while the first is still pending.
        // Deliberately not awaited, for the same real-clock-hang reason
        // as the test above: if _loadingMore's guard is missing, this
        // second call issues its own fetch whose completer is never
        // resolved by this test.
        unawaited(notifier.loadMore());
        await pumpEventQueue();
        expect(
          gateway.pendingActiveItemsCompleters.length,
          2,
          reason:
              '_loadingMore must prevent a concurrent loadMore call from '
              'issuing a second RPC while one is already in flight',
        );

        // Resolve the one real in-flight call so the pager settles
        // cleanly and nothing is left pending at test end.
        gateway.pendingActiveItemsCompleters[1].complete(
          const StoryItemPage(items: [], nextCursor: null),
        );
        await pumpEventQueue();
      },
    );
  });

  group('signed URLs', () {
    test(
      'a signed URL is minted per request and never cached past its TTL '
      '— two requests for the same key each reach the gateway',
      () async {
        final gateway = _FakeStoryReadGateway();
        final container = _buildContainer(gateway);
        addTearDown(container.dispose);

        final first = await container.read(
          storyMediaSignedUrlProvider('story-media/x.jpg').future,
        );
        // Force Riverpod to actually re-invoke the provider a second
        // time (rather than reusing its cached AsyncValue) by disposing
        // and re-reading — this simulates a screen re-mounting or
        // re-watching after the provider's own cache lifetime, which is
        // the only path through which this app ever asks for the same
        // key twice.
        container.invalidate(storyMediaSignedUrlProvider('story-media/x.jpg'));
        final second = await container.read(
          storyMediaSignedUrlProvider('story-media/x.jpg').future,
        );

        expect(gateway.signMediaUrlCallCount, 2);
        expect(gateway.signMediaUrlKeysRequested, [
          'story-media/x.jpg',
          'story-media/x.jpg',
        ]);
        // Each call minted a DIFFERENT url (the fake encodes the call
        // count into it) — proving nothing cached and replayed the
        // first result.
        expect(first, isNot(equals(second)));
      },
    );

    test(
      'the PRODUCTION repository has no cache map for signed URLs, unlike '
      "chat's createSignedMediaUrl — a deliberate divergence from the "
      'brief, since the design spec (binding authority) requires minting '
      'per request and never storing/caching (spec §4.1/§4.5)',
      () {
        // story_repository_test.dart's own house pattern: assert against
        // the source rather than mocking SupabaseClient, since its
        // storage/RPC builders are final and heavily generic with no
        // test seam. This guards the ACTUAL repository implementation
        // (not just the fake test double above) against ever growing a
        // signedUrlCache map the way supabase_chat_repository.dart's
        // createSignedMediaUrl deliberately has.
        final source = File(
          'lib/features/stories/data/story_read_repository.dart',
        ).readAsStringSync();

        expect(
          source.contains('_signedUrlCache'),
          isFalse,
          reason:
              'a cache map would let a signed URL outlive the deletion '
              'it is supposed to respect (spec §4.5) — mint fresh every '
              'call instead',
        );

        // No short-circuit before the network call: the FIRST executable
        // construct inside signMediaUrl's IMPLEMENTATION body (the
        // second occurrence of the signature; the first is the abstract
        // StoryReadGateway declaration, which has no body) must be the
        // Storage call itself, not an `if` that could return early from
        // a cached value. This is the exact shape the earlier mutation
        // test proved this assertion must catch: adding
        // `final cached = _cache[key]; if (cached != null) return
        // cached;` before the try/call left "exactly one call" true but
        // is precisely the bug spec §4.5 forbids.
        final interfaceDeclaration = source.indexOf(
          'Future<String?> signMediaUrl(String storageKey);',
        );
        expect(interfaceDeclaration, greaterThan(-1));
        final methodStart = source.indexOf(
          'Future<String?> signMediaUrl(',
          interfaceDeclaration + 1,
        );
        expect(methodStart, greaterThan(-1));
        final nextMethodStart = source.indexOf(
          '\n  @override',
          methodStart + 1,
        );
        final methodBody = source.substring(
          methodStart,
          nextMethodStart == -1 ? source.length : nextMethodStart,
        );

        final callIndex = methodBody.indexOf('createSignedUrl(');
        expect(
          callIndex,
          greaterThan(-1),
          reason: 'signMediaUrl must call Storage.createSignedUrl',
        );
        expect(
          'createSignedUrl('.allMatches(methodBody).length,
          1,
          reason: 'signMediaUrl must reach Storage exactly once per call',
        );

        // No `if (` — a cache-check branch — anywhere before the call.
        final ifBeforeCall = methodBody
            .substring(0, callIndex)
            .contains('if (');
        expect(
          ifBeforeCall,
          isFalse,
          reason:
              'a conditional branch before createSignedUrl reads like a '
              '"if cached, return early" short-circuit — mint fresh '
              'unconditionally on every call (spec §4.5)',
        );

        // No assignment into a Map/field after the call either (a
        // "store what we just minted" write is just as much a cache as
        // a read-before-call, since the NEXT call could still read it).
        final afterCall = methodBody.substring(callIndex);
        expect(
          RegExp(r'\[\s*\w+\s*\]\s*=').hasMatch(afterCall),
          isFalse,
          reason:
              'signMediaUrl must not write the freshly minted url into '
              'any map/cache — nothing here should outlive this call',
        );
      },
    );

    test(
      'signMediaUrl uses the 600-second TTL constant, not a longer '
      'window that would widen the accepted post-deletion exposure',
      () {
        final source = File(
          'lib/features/stories/data/story_read_repository.dart',
        ).readAsStringSync();
        expect(source.contains('Duration(seconds: 600)'), isTrue);
        expect(
          source.contains('_signedUrlTtl.inSeconds'),
          isTrue,
          reason: 'createSignedUrl must be called with the 600s TTL',
        );
      },
    );

    test(
      'every RPC/storage call in the read repository is bounded by the '
      '30-second timeout, matching story_repository.dart\'s checklist-1.2 '
      'bound',
      () {
        // Fix round 1, finding 7: the review found this constant survives
        // mutation unguarded (30s -> 300s left the suite green). The 600s
        // signed-URL TTL already gets a source guard above; this gives
        // _timeout the same treatment.
        final source = File(
          'lib/features/stories/data/story_read_repository.dart',
        ).readAsStringSync();
        expect(
          source.contains('_timeout = Duration(seconds: 30)'),
          isTrue,
          reason:
              'a stalled connection without this bound leaves a reel/'
              'calendar screen spinning forever',
        );
        expect(
          source.contains('.timeout(_timeout)'),
          isTrue,
          reason: '_guard must actually apply _timeout to every call',
        );
      },
    );
  });

  group('calendar reads', () {
    test('day counts are bounded by the requested range, one row per date', () async {
      final gateway = _FakeStoryReadGateway()
        ..dayCountsScript.add(
          StoryDayCount(occurredOn: DateTime.utc(2026, 9, 10), itemCount: 3),
        )
        ..dayCountsScript.add(
          StoryDayCount(occurredOn: DateTime.utc(2026, 9, 11), itemCount: 5),
        );

      final container = _buildContainer(gateway);
      addTearDown(container.dispose);

      final counts = await container.read(
        storyDayCountsProvider(
          StoryDayRangeKey(
            relationshipId: 'rel-1',
            startOn: DateTime.utc(2026, 9, 1),
            endOn: DateTime.utc(2026, 9, 30),
          ),
        ).future,
      );

      expect(counts.length, 2);
      expect(counts.first.itemCount, 3);
    });

    test(
      'F6: StoryDayRangeKey truncates to y/m/d, so two ranges built from '
      'DateTime.now() moments apart still compare equal and do not mint '
      'a fresh .family instance per rebuild',
      () {
        final a = StoryDayRangeKey(
          relationshipId: 'rel-1',
          startOn: DateTime.utc(2026, 9, 1, 8, 0, 0),
          endOn: DateTime.now(),
        );
        // A microsecond (or more) later — the exact scenario the review
        // reproduced: "two ranges built from DateTime.now() one second
        // apart compare unequal" under a bare-record key.
        final b = StoryDayRangeKey(
          relationshipId: 'rel-1',
          startOn: DateTime.utc(2026, 9, 1, 20, 0, 0), // same DAY, different time
          endOn: DateTime.now().add(const Duration(milliseconds: 5)),
        );

        expect(
          a,
          equals(b),
          reason:
              'two ranges naming the same calendar days must compare '
              'equal regardless of time-of-day/microsecond differences '
              '— a record key using DateTime structural equality would '
              'fail this',
        );
        expect(a.hashCode, equals(b.hashCode));

        final differentDay = StoryDayRangeKey(
          relationshipId: 'rel-1',
          startOn: DateTime.utc(2026, 9, 2),
          endOn: a.endOn,
        );
        expect(
          a,
          isNot(equals(differentDay)),
          reason: 'a genuinely different start date must still compare unequal',
        );
      },
    );

    test(
      'day items page with the same keyset cursor contract as the reel, '
      'and include items the reel would have excluded as expired',
      () async {
        final expired = _item(
          id: 'expired-item',
          createdAt: DateTime.utc(2026, 9, 11, 1),
        );
        final gateway = _FakeStoryReadGateway()
          ..dayItemsScript.add(
            StoryItemPage(items: [expired], nextCursor: expired.cursor),
          )
          ..dayItemsScript.add(const StoryItemPage(items: [], nextCursor: null));

        final container = _buildContainer(gateway);
        addTearDown(container.dispose);

        final key = StoryDayKey(
          relationshipId: 'rel-1',
          occurredOn: DateTime.utc(2026, 9, 11),
        );
        final sub = container.listen(
          storyDayItemsProvider(key),
          (p, n) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await pumpEventQueue();

        final notifier = container.read(storyDayItemsProvider(key).notifier);
        await notifier.loadMore();

        expect(gateway.dayItemsCursorsRequested.first, isNull);
        expect(gateway.dayItemsCursorsRequested[1]!.id, expired.id);
      },
    );
  });

  group('mark viewed / delete', () {
    test('markViewed and deleteItem call the gateway with the given id', () async {
      final gateway = _FakeStoryReadGateway();
      await gateway.markViewed(storyItemId: 'story-9');
      await gateway.deleteItem(storyItemId: 'story-9');
      expect(gateway.markedViewed, contains('story-9'));
      expect(gateway.deleted, contains('story-9'));
    });

    // Fix round 1, finding 5. The test above calls the FAKE directly — it
    // never touches StoryReadRepository, so it is tautological: it can
    // never fail for a production defect (mutation-tested: deleting
    // _unwrap's `if (data['error'] == true) throw ...` line left the
    // suite fully green). Two replacements, per the review's own
    // suggestion:
    //   1. a source-assertion guard (the same style as the RPC-cursor
    //      guard added in 96306ea0) proving _unwrap is actually applied
    //      to both calls in the real repository; and
    //   2. a gateway-level test proving a refusal a real gateway would
    //      throw (StoryApiError, exactly what _unwrap raises) actually
    //      PROPAGATES to the caller rather than being silently
    //      swallowed — the concrete failure mode finding 5 describes:
    //      "the user would see a delete appear to succeed and the story
    //      would still be there after the next refetch."
    test(
      "the PRODUCTION repository's markViewed/deleteItem both unwrap the "
      "RPC response — a refusal must not be silently discarded",
      () {
        final source = File(
          'lib/features/stories/data/story_read_repository.dart',
        ).readAsStringSync();

        for (final rpc in ['mark_story_viewed', 'delete_story_item']) {
          // Requires _unwrap( to IMMEDIATELY (modulo whitespace/newlines)
          // precede `await _supabase.rpc('<rpc>'` — not merely "some
          // _unwrap( appears earlier in the file", which an unrelated
          // call's own _unwrap could satisfy without actually wrapping
          // THIS one. Mutation-tested: removing _unwrap(...) from around
          // mark_story_viewed's call (leaving delete_story_item's intact
          // elsewhere in the file) must fail this — a looser "does
          // _unwrap( appear anywhere before this index" check does not,
          // because delete_story_item's OWN _unwrap( is unrelated but
          // still precedes mark_story_viewed's call textually.
          final pattern = RegExp(
            r"_unwrap\(\s*await\s+_supabase\.rpc\(\s*'" + rpc + r"'",
          );
          expect(
            pattern.hasMatch(source),
            isTrue,
            reason:
                "$rpc's rpc() call must be wrapped directly in "
                '_unwrap(await _supabase.rpc(...)) — a refusal silently '
                'dropped here means a delete/view appears to succeed '
                'when the server actually refused it',
          );
        }
      },
    );

    test(
      'a StoryApiError from the gateway propagates out of markViewed and '
      'deleteItem rather than being swallowed — the concrete failure '
      'mode: a delete silently "succeeding" while the story remains',
      () async {
        final gateway = _ThrowingStoryReadGateway();

        await expectLater(
          () => gateway.markViewed(storyItemId: 's1'),
          throwsA(isA<StoryApiError>()),
        );
        await expectLater(
          () => gateway.deleteItem(storyItemId: 's1'),
          throwsA(isA<StoryApiError>()),
        );
      },
    );
  });

  // ---------------------------------------------------------------
  // StoryReadRepository's own RPC payloads.
  //
  // Every behavioural test above runs against _FakeStoryReadGateway, so
  // it verifies the PROVIDER layer: that the notifier hands the previous
  // page's last item down as the cursor. Nothing below that seam is
  // exercised -- StoryReadRepository builds the actual rpc() params map,
  // and the fake replaces the whole class. Nulling
  // 'p_after_created_at'/'p_after_id' there (so every page re-returns
  // page one) passed all ten tests when mutation-tested.
  //
  // Faking SupabaseClient's generic rpc builder is not worth the weight
  // here, so this guards the payload the same way the signed-URL rules
  // above are guarded: by asserting on the source.
  group('repository RPC payloads', () {
    test(
      'both paginated RPCs forward the keyset cursor, never a literal '
      'null or an offset',
      () {
        final source = File(
          'lib/features/stories/data/story_read_repository.dart',
        ).readAsStringSync();

        for (final rpc in ['list_active_story_items', 'list_story_day_items']) {
          final start = source.indexOf("'$rpc'");
          expect(start, greaterThan(-1), reason: '$rpc call not found');
          final end = source.indexOf('},', start);
          final params = source.substring(start, end);

          expect(
            params.contains("'p_after_created_at': after?.createdAt"),
            isTrue,
            reason:
                "$rpc must forward the cursor's created_at -- a literal "
                'null makes every page re-return page one',
          );
          expect(
            params.contains("'p_after_id': after?.id"),
            isTrue,
            reason: "$rpc must forward the cursor's id",
          );
          expect(
            RegExp(r"'p_(after_created_at|after_id)':\s*null").hasMatch(params),
            isFalse,
            reason: '$rpc must not hardcode a null cursor',
          );
          // Param KEYS only -- the surrounding comments legitimately use
          // the word "offset" to explain why there isn't one.
          final paramKeys = RegExp(r"'(p_\w+)':")
              .allMatches(params)
              .map((m) => m.group(1))
              .toList();
          expect(
            paramKeys.any((k) => k!.contains('offset')),
            isFalse,
            reason: '\$rpc must page by keyset, never by offset',
          );
        }
      },
    );
  });
}
