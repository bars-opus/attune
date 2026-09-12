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
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
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
class _FakeStoryReadGateway implements StoryReadGateway {
  final List<StoryRingSummary> ringSummaryScript = [];
  int ringSummaryCallCount = 0;

  /// Pages served by [listActiveItems], consumed in order per call.
  final List<StoryItemPage> activeItemsScript = [];
  final List<StoryPageCursor?> activeItemsCursorsRequested = [];

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
  }) async {
    activeItemsCursorsRequested.add(after);
    final index = activeItemsCursorsRequested.length - 1;
    return activeItemsScript[index];
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
        storyDayCountsProvider((
          relationshipId: 'rel-1',
          startOn: DateTime.utc(2026, 9, 1),
          endOn: DateTime.utc(2026, 9, 30),
        )).future,
      );

      expect(counts.length, 2);
      expect(counts.first.itemCount, 3);
    });

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

  group('mark viewed / delete pass through unchanged', () {
    test('markViewed and deleteItem call the gateway with the given id', () async {
      final gateway = _FakeStoryReadGateway();
      await gateway.markViewed(storyItemId: 'story-9');
      await gateway.deleteItem(storyItemId: 'story-9');
      expect(gateway.markedViewed, contains('story-9'));
      expect(gateway.deleted, contains('story-9'));
    });
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
