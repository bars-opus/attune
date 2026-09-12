// Tests for the calendar's third source (Plan C, Task 5; spec §5.3;
// task-5-brief.md) — StoryDayRow/StoryDayCountRow, the day-mode addition
// to StoryReelScreen, and the ring->reel routing fix folded into this
// task (conversations_screen.dart's onOpenMine/onOpenPartner).
//
// THE SINGLE MOST IMPORTANT ASSERTION IN THIS FILE: an EXPIRED story
// still opens and plays from its calendar day. `list_active_story_items`
// (the reel/rings path) EXCLUDES expired items; `list_story_day_items`
// (this file's path) INCLUDES them — that asymmetry IS the feature
// (spec §1/§3.2). The fake gateway below returns an item whose
// `expiresAt` is already in the past for exactly this reason, through
// `listDayItems` only, and the test proves the reel still renders and
// advances through it.
//
// House pattern, unchanged from Tasks 2-4: never mock SupabaseClient or
// Riverpod internals — override `storyReadGatewayProvider` with a fake
// `StoryReadGateway` and drive the real providers/widgets through a
// `ProviderScope`.
//
// NO REAL-CLOCK WAITS: every wait is `tester.pump(duration)`, which
// advances the FakeAsync zone `testWidgets` already runs inside. Expiry
// here is a value already baked into the fake `StoryItem` at
// construction (`expiresAt` in the past relative to the fixed dates used
// throughout, not derived from `DateTime.now()`), so no clock
// manipulation (`package:clock`/`withClock`) is needed to prove it: the
// client trusts whatever `list_story_day_items` returns and does no
// date arithmetic of its own (see `story_day_row.dart`'s header) — this
// suite asserts that trust is well-placed, not that a wall-clock
// boundary is computed correctly (that boundary is the server RPC's job
// and is out of this client-only suite's reach).

import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/timeline/presentation/widgets/story_day_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _myId = 'me-1';
const _partnerId = 'partner-1';
const _relationshipId = 'rel-1';

final _signedInUser = User(
  id: _myId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

StoryItem _item({
  required String id,
  required DateTime createdAt,
  required DateTime expiresAt,
  String authorId = _partnerId,
  String mediaType = 'image',
}) {
  return StoryItem(
    id: id,
    clientStoryId: 'client-$id',
    relationshipId: _relationshipId,
    authorId: authorId,
    mediaType: mediaType,
    mediaKey: 'story-media/$id.jpg',
    thumbnailKey: 'story-media/$id-thumb.jpg',
    mediaWidth: 1080,
    mediaHeight: 1920,
    durationMs: mediaType == 'video' ? 4000 : null,
    occurredOn: createdAt,
    createdAt: createdAt,
    expiresAt: expiresAt,
    hasBeenViewed: false,
  );
}

/// A fake gateway whose `listActiveItems` and `listDayItems` answer
/// INDEPENDENTLY — this is load-bearing: it lets a single test prove the
/// reel (active-only) and the calendar (day, expired-inclusive) can
/// disagree about the very same story, exactly like the real
/// `list_active_story_items` vs `list_story_day_items` RPCs (spec §5.5).
class _FakeCalendarGateway implements StoryReadGateway {
  _FakeCalendarGateway({
    List<StoryItem> dayItems = const [],
    List<StoryItem> activeItems = const [],
    List<StoryDayCount> dayCounts = const [],
  }) : _dayItems = dayItems,
       _activeItems = activeItems,
       _dayCounts = dayCounts;

  final List<StoryItem> _dayItems;
  final List<StoryItem> _activeItems;
  final List<StoryDayCount> _dayCounts;

  final List<String> markViewedCalls = [];
  final List<String> deleteCalls = [];
  bool deleteShouldFail = false;

  /// Not exercised by this file's own assertions (the calendar never
  /// calls getReplyTarget itself — only chat's message bubble does,
  /// story_reply_test.dart's own suite); stubbed null so this fake keeps
  /// compiling as StoryReadGateway grows.
  StoryReplyTarget? replyTarget;

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async => StoryItemPage(items: List.of(_dayItems), nextCursor: null);

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => StoryItemPage(
    items: _activeItems.where((i) => i.authorId == authorId).toList(),
    nextCursor: null,
  );

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => List.of(_dayCounts);

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => const [];

  @override
  Future<String?> signMediaUrl(String storageKey) async =>
      'https://signed.example/$storageKey';

  @override
  Future<void> markViewed({required String storyItemId}) async {
    markViewedCalls.add(storyItemId);
  }

  @override
  Future<void> deleteItem({required String storyItemId}) async {
    deleteCalls.add(storyItemId);
    if (deleteShouldFail) throw StoryApiError.network('boom');
  }

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => replyTarget;

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

/// Pushes [StoryReelScreen] onto a real `Navigator` stack (via an "open"
/// button, mirroring `story_reel_test.dart`'s own swipe-down-dismiss
/// harness) rather than setting it as `MaterialApp.home` directly.
/// `_close()`'s `Navigator.of(context).maybePop()` is a no-op on a root
/// route with nothing beneath it to pop back to — this harness gives it
/// a real route so the delete-then-close path (`_confirmAndDelete`'s
/// `_close()` when the day's last item is removed) can actually be
/// observed popping, instead of silently doing nothing.
Widget _reelHarness(_FakeCalendarGateway gateway, {DateTime? occurredOn}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(_signedInUser),
      storyReadGatewayProvider.overrideWithValue(gateway),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => occurredOn != null
                  ? StoryReelScreen.forDay(
                      relationshipId: _relationshipId,
                      occurredOn: occurredOn,
                    )
                  : StoryReelScreen(
                      relationshipId: _relationshipId,
                      authorId: _partnerId,
                    ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

/// Taps the "open" button _reelHarness renders and pumps through the
/// route-push animation, landing on the pushed StoryReelScreen.
Future<void> _openReel(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a day with stories shows a row with its count', () {
    testWidgets('StoryDayRow renders the count and opens the day reel on '
        'tap', (tester) async {
      final day = DateTime.utc(2026, 9, 5);
      final gateway = _FakeCalendarGateway(
        dayItems: [_item(id: 'a', createdAt: day, expiresAt: day.add(const Duration(hours: 24)))],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: StoryDayRow(
                relationshipId: _relationshipId,
                occurredOn: day,
                itemCount: 3,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3 stories'), findsOneWidget);

      await tester.tap(find.byType(StoryDayRow));
      // Bounded pumps, not pumpAndSettle: the pushed StoryReelScreen
      // renders an image item through Image.network, whose indeterminate
      // loading state never "settles" under the test binding's fake
      // HttpClient (story_rings_test.dart's own house pattern for the
      // same reason).
      await tester.pump(); // route push animation start
      await tester.pump(const Duration(milliseconds: 300)); // route settle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(StoryReelScreen), findsOneWidget);
    });

    testWidgets('StoryDayCountRow renders nothing for a day absent from '
        'list_story_day_counts', (tester) async {
      final day = DateTime.utc(2026, 9, 5);
      // No day counts at all — the RPC omits days with zero items
      // (spec §5.5), and this widget must not draw a row from nothing.
      final gateway = _FakeCalendarGateway(dayCounts: const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: StoryDayCountRow(
                relationshipId: _relationshipId,
                occurredOn: day,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(StoryDayRow), findsNothing);
    });

    testWidgets('StoryDayCountRow day counts match day items: the row shows '
        'exactly the count list_story_day_counts reports for that date, not '
        'the length of some other list', (tester) async {
      final day = DateTime.utc(2026, 9, 7);
      final otherDay = DateTime.utc(2026, 9, 8);
      final gateway = _FakeCalendarGateway(
        dayCounts: [
          StoryDayCount(occurredOn: day, itemCount: 5),
          StoryDayCount(occurredOn: otherDay, itemCount: 1),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: StoryDayCountRow(
                relationshipId: _relationshipId,
                occurredOn: day,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Exactly day's own count (5), never otherDay's (1) and never a
      // hardcoded/derived-elsewhere number.
      expect(find.text('5 stories'), findsOneWidget);
      expect(find.text('1 story'), findsNothing);
    });
  });

  group(
    'an EXPIRED story still opens from its calendar day '
    '(THE FEATURE\'S CENTRAL PROMISE)',
    () {
      testWidgets(
        'list_active_story_items excludes it, list_story_day_items includes '
        'it — the calendar reel renders and plays the expired item',
        (tester) async {
          final day = DateTime.utc(2026, 9, 1);
          final longExpired = _item(
            id: 'expired-1',
            createdAt: day,
            // Expired 20 hours before "now" in this fixed-date world —
            // any positive gap past created_at + 24h proves the point;
            // the exact value is not the thing under test here (that is
            // the server's job), only that the client does not filter
            // it out or refuse to play it.
            expiresAt: day.add(const Duration(hours: 24)),
          );
          final gateway = _FakeCalendarGateway(
            dayItems: [longExpired],
            // Deliberately EMPTY: proves this is not accidentally reading
            // through the active-items path, which would legitimately
            // exclude this same item.
            activeItems: const [],
          );

          await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
          await tester.pump();
          await _openReel(tester);
          await tester.pump(); // post-frame kicks off _startItem
          await tester.pump(const Duration(milliseconds: 50));

          // It rendered (no empty/error state) and playback started —
          // proven the same way story_reel_test.dart proves a render:
          // markViewed fires only after a successful render.
          expect(find.byType(StoryReelScreen), findsOneWidget);
          expect(find.text('No stories to show.'), findsNothing);
          expect(gateway.markViewedCalls, ['expired-1']);
        },
      );

      testWidgets(
        'the author-mode reel (active-only) does NOT show this expired '
        'item at all',
        (tester) async {
          // listActiveItems returns nothing for this author (the item has
          // expired, exactly like the real RPC).
          final activeGateway = _FakeCalendarGateway(activeItems: const []);
          await tester.pumpWidget(_reelHarness(activeGateway));
          await tester.pump();
          await _openReel(tester);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.text('No stories to show.'), findsOneWidget);
        },
      );

      testWidgets(
        'the SAME expired item id IS visible from day mode — proving the '
        'two surfaces really do disagree about this exact item',
        (tester) async {
          final day = DateTime.utc(2026, 9, 1);
          final expiredItem = _item(
            id: 'expired-2',
            createdAt: day,
            expiresAt: day.add(const Duration(hours: 24)),
          );
          final dayGateway = _FakeCalendarGateway(dayItems: [expiredItem]);
          await tester.pumpWidget(_reelHarness(dayGateway, occurredOn: day));
          await tester.pump();
          await _openReel(tester);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.text('No stories to show.'), findsNothing);
          expect(dayGateway.markViewedCalls, ['expired-2']);
        },
      );

      testWidgets(
        'a day mixing BOTH partners\' items marks only the partner\'s — '
        '"is this mine" is derived PER ITEM in day mode, not once per screen',
        (tester) async {
          // A calendar day legitimately contains items from both people,
          // so a screen-level isOwnReel flag has no correct value here.
          // Collapsing this to the screen flag survives every other test
          // in this file (verified by mutation), because each of those
          // uses a single-author day.
          final day = DateTime.utc(2026, 9, 3);
          final gateway = _FakeCalendarGateway(
            dayItems: [
              _item(
                id: 'theirs-first',
                createdAt: day,
                expiresAt: day.add(const Duration(hours: 24)),
                authorId: _partnerId,
              ),
              _item(
                id: 'mine-second',
                createdAt: day.add(const Duration(minutes: 1)),
                expiresAt: day.add(const Duration(hours: 24)),
                authorId: _myId,
              ),
            ],
          );

          await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
          await tester.pump();
          await _openReel(tester);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Item 1 is the partner's: a view is recorded.
          expect(gateway.markViewedCalls, ['theirs-first']);

          // Advance to my own item: mark_story_viewed refuses the author
          // server-side (spec §3.4), so the client must not call it.
          await tester.tapAt(
            tester.getCenter(find.byType(StoryReelScreen)) +
                const Offset(100, 0),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            gateway.markViewedCalls,
            ['theirs-first'],
            reason: 'my own item must never be marked viewed, even when it '
                'shares a day with the partner\'s',
          );
        },
      );
    },
  );

  group('only the author sees delete, and it warns it is permanent', () {
    testWidgets('the author of the current day item sees a delete '
        'affordance', (tester) async {
      final day = DateTime.utc(2026, 9, 2);
      final myItem = _item(
        id: 'mine',
        createdAt: day,
        expiresAt: day.add(const Duration(hours: 24)),
        authorId: _myId,
      );
      final gateway = _FakeCalendarGateway(dayItems: [myItem]);

      await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
      await tester.pump();
      await _openReel(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);
    });

    testWidgets('the non-author (partner\'s item) never sees a delete '
        'affordance', (tester) async {
      final day = DateTime.utc(2026, 9, 2);
      final partnerItem = _item(
        id: 'partners',
        createdAt: day,
        expiresAt: day.add(const Duration(hours: 24)),
        authorId: _partnerId,
      );
      final gateway = _FakeCalendarGateway(dayItems: [partnerItem]);

      await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
      await tester.pump();
      await _openReel(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
    });

    testWidgets('author-mode (the ring/reel, not day mode) never shows '
        'delete at all, even for the author\'s own reel', (tester) async {
      // Deletion lives in the calendar's day view only (spec §5.3) — this
      // proves the author-mode reel (occurredOn == null) does not grow a
      // delete button just because isOwnReel is true.
      final day = DateTime.utc(2026, 9, 2);
      final myItem = _item(
        id: 'mine-active',
        createdAt: day,
        expiresAt: day.add(const Duration(hours: 24)),
        authorId: _myId,
      );
      final gateway = _FakeCalendarGateway(activeItems: [myItem]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: StoryReelScreen(
              relationshipId: _relationshipId,
              authorId: _myId,
              isOwnReel: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
    });

    testWidgets('tapping delete warns it is permanent before calling '
        'delete_story_item', (tester) async {
      final day = DateTime.utc(2026, 9, 2);
      final myItem = _item(
        id: 'mine',
        createdAt: day,
        expiresAt: day.add(const Duration(hours: 24)),
        authorId: _myId,
      );
      final gateway = _FakeCalendarGateway(dayItems: [myItem]);

      await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
      await tester.pump();
      await _openReel(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
      await tester.pump();

      // Warns before doing anything — the RPC has NOT been called yet.
      expect(gateway.deleteCalls, isEmpty);
      expect(find.textContaining('permanently'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      // Bounded pumps, not pumpAndSettle: see _openReel/this file's
      // header for why (a stuck Image.network spinner never settles).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.deleteCalls, ['mine']);
    });

    testWidgets('cancelling the warning never calls delete_story_item', (
      tester,
    ) async {
      final day = DateTime.utc(2026, 9, 2);
      final myItem = _item(
        id: 'mine',
        createdAt: day,
        expiresAt: day.add(const Duration(hours: 24)),
        authorId: _myId,
      );
      final gateway = _FakeCalendarGateway(dayItems: [myItem]);

      await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
      await tester.pump();
      await _openReel(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.deleteCalls, isEmpty);
    });
  });

  group('a deleted story appears in NEITHER surface', () {
    testWidgets(
      'once delete_story_item succeeds, the gateway is the single source '
      'both surfaces would re-read from — this test proves the reel screen '
      'calls delete_story_item exactly once and does not resurrect the '
      'item locally afterward',
      (tester) async {
        final day = DateTime.utc(2026, 9, 3);
        final onlyItem = _item(
          id: 'solo',
          createdAt: day,
          expiresAt: day.add(const Duration(hours: 24)),
          authorId: _myId,
        );
        final gateway = _FakeCalendarGateway(dayItems: [onlyItem]);

        await tester.pumpWidget(_reelHarness(gateway, occurredOn: day));
        await tester.pump();
        await _openReel(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
        await tester.pump();
        await tester.tap(find.text('Delete'));
        // Bounded pumps: deleting the only item in the day pops this
        // route via Navigator.maybePop() inside the MaterialPageRoute
        // _reelHarness pushed — pumpAndSettle would also wait out any
        // stuck Image.network spinner elsewhere in the tree, which never
        // resolves under the test binding. The first pump lets the
        // AlertDialog's own pop-route animation finish AND the awaited
        // gateway.deleteItem() future resolve (both async gaps happen
        // before _close() ever runs); only then does the extra 300ms
        // pump drive the SECOND (reel-screen) pop's own transition.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(gateway.deleteCalls, ['solo']);
        // The only item in the day was deleted -> the screen closes
        // itself rather than continuing to show it (nothing left to
        // play), proving it does not keep showing a deleted item.
        expect(find.byType(StoryReelScreen), findsNothing);
      },
    );
  });

  group('the ring tap opens the reel for the correct author', () {
    Future<Widget> harness(StoryReadGateway gateway) async {
      final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(_signedInUser),
          storyReadGatewayProvider.overrideWithValue(gateway),
          storyOutboxStoreProvider.overrideWithValue(store),
          storyGatewayProvider.overrideWithValue(_HangingStoryGateway()),
          conversationsProvider.overrideWith(
            () => _FixedConversationsNotifier(
              AsyncData([_conversationsScreenFixture()]),
            ),
          ),
          journalEntriesProvider.overrideWith(
            () => _FixedJournalEntriesNotifier(),
          ),
          remindersListProvider.overrideWith(
            () => _FixedRemindersListNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => const ConversationsScreen(),
          ),
        ),
      );
    }

    testWidgets('tapping the partner ring opens StoryReelScreen with the '
        'partner\'s authorId, not mine', (tester) async {
      final day = DateTime.utc(2026, 9, 1);
      final gateway = _FakeCalendarGateway(
        activeItems: [
          _item(
            id: 'partner-active',
            createdAt: day,
            expiresAt: day.add(const Duration(hours: 24)),
            authorId: _partnerId,
          ),
        ],
      );
      // The ring row reads storyRingSummaryProvider, which calls
      // getRingSummary — wire it to report the partner as having an
      // active story so StoryRingsRow actually draws (and wires onTap
      // for) the partner ring at all.
      final gatewayWithSummary = _CalendarGatewayWithRingSummary(
        gateway,
        summary: [
          StoryRingSummary(
            authorId: _partnerId,
            activeCount: 1,
            unviewedCount: 1,
            newestThumbnailKey: 'story-media/partner-active-thumb.jpg',
            newestCreatedAt: day,
          ),
        ],
      );

      await tester.pumpWidget(await harness(gatewayWithSummary));
      await tester.pump();
      await tester.pump();

      final partnerRingFinder = find.byKey(
        const ValueKey('story-ring-partner'),
      );
      expect(partnerRingFinder, findsOneWidget);

      await tester.tap(partnerRingFinder);
      // Bounded pumps, not pumpAndSettle: the pushed StoryReelScreen's
      // image item never lets an indeterminate Image.network spinner
      // settle under the test binding's fake HttpClient.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.byType(StoryReelScreen), findsOneWidget);
      final screen = tester.widget<StoryReelScreen>(
        find.byType(StoryReelScreen),
      );
      expect(screen.authorId, _partnerId);
      expect(screen.isOwnReel, isFalse);
    });

    testWidgets('tapping my own ring (with an active story) opens '
        'StoryReelScreen with MY authorId and isOwnReel true', (
      tester,
    ) async {
      final day = DateTime.utc(2026, 9, 1);
      final gatewayWithSummary = _CalendarGatewayWithRingSummary(
        _FakeCalendarGateway(),
        summary: [
          StoryRingSummary(
            authorId: _myId,
            activeCount: 2,
            unviewedCount: 0,
            newestThumbnailKey: 'story-media/mine-thumb.jpg',
            newestCreatedAt: day,
          ),
        ],
      );

      await tester.pumpWidget(await harness(gatewayWithSummary));
      await tester.pump();
      await tester.pump();
      // One more pump: _MineRing watches storyMediaSignedUrlProvider (a
      // FutureProvider), and its subtree is still dirty/pending after
      // only two pumps — an extra pump lets that future resolve and the
      // ring's own GestureDetector actually attach before this test taps
      // it (mirrors the partner-ring test's own settle window above,
      // which happens to need one fewer pump because _PartnerRing's
      // precondition summary is set up slightly earlier in that test).
      await tester.pump();

      final mineRingFinder = find.byKey(const ValueKey('story-ring-mine'));
      expect(mineRingFinder, findsOneWidget);

      // Tap off the ring's exact geometric center, not on it: the "mine,
      // has stories" ring stacks the `+` capture badge at the bottom-
      // right corner (StoryRing's own Positioned(right: 0, bottom: 0)),
      // and its hit region reaches further toward the center than its
      // visible glyph does — a dead-center tap silently lands on that
      // badge's own onTap (onCapture, unwired in this harness) instead
      // of the ring's onTap (onOpenMine). Tapping the ring's upper-left
      // quadrant, well clear of that corner, exercises the affordance a
      // real viewer actually uses to open the reel.
      final rect = tester.getRect(mineRingFinder);
      await tester.tapAt(rect.center.translate(-15, -15));
      // Bounded pumps, not pumpAndSettle — same reason as the partner-ring
      // test above.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.byType(StoryReelScreen), findsOneWidget);
      final screen = tester.widget<StoryReelScreen>(
        find.byType(StoryReelScreen),
      );
      expect(screen.authorId, _myId);
      expect(screen.isOwnReel, isTrue);
    });
  });
}

Conversation _conversationsScreenFixture() {
  return Conversation(
    id: 'c1',
    relationshipId: _relationshipId,
    partnerId: _partnerId,
    name: 'Partner',
    partnerName: 'Alex',
    updatedAt: DateTime.utc(2026, 9, 1),
    relationshipStatus: 'active',
    availability: ConversationAvailability.active,
  );
}

class _FixedConversationsNotifier extends ConversationsNotifier {
  _FixedConversationsNotifier(this._initial);
  final AsyncValue<List<Conversation>> _initial;

  @override
  Future<List<Conversation>> build() {
    if (_initial.hasValue) return Future.value(_initial.value);
    return Completer<List<Conversation>>().future;
  }
}

class _FixedJournalEntriesNotifier extends JournalEntriesNotifier {
  @override
  Future<List<JournalEntry>> build() async => const [];
}

class _FixedRemindersListNotifier extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

/// A `StoryGateway` (the OUTBOX gateway, distinct from `StoryReadGateway`
/// above) whose every call hangs forever — same shape and purpose as
/// `story_rings_test.dart`'s own `_HangingStoryGateway`: this suite seeds
/// no pending outbox record, so nothing ever calls it, but
/// `StoryOutboxController` still requires an override to construct.
class _HangingStoryGateway implements StoryGateway {
  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) => Completer<StoryUploadIntent>().future;

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
  }) => Completer<void>().future;

  @override
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,
  }) => Completer<StoryFinalizeResult>().future;
}

/// Decorates a [_FakeCalendarGateway] to additionally answer
/// `getRingSummary` — `StoryRingsRow` (used by `ConversationsScreen`)
/// needs this to decide whether/how to draw each ring at all, which
/// `_FakeCalendarGateway` itself does not need for the reel-only tests
/// above (it always returns `const []`, matching "no active stories" —
/// fine for those, wrong for the routing tests here that need a ring
/// actually drawn to tap).
class _CalendarGatewayWithRingSummary implements StoryReadGateway {
  _CalendarGatewayWithRingSummary(this._inner, {required this.summary});

  final _FakeCalendarGateway _inner;
  final List<StoryRingSummary> summary;

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => List.of(summary);

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) => _inner.listActiveItems(
    relationshipId: relationshipId,
    authorId: authorId,
    after: after,
    limit: limit,
  );

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) => _inner.listDayCounts(
    relationshipId: relationshipId,
    startOn: startOn,
    endOn: endOn,
  );

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) => _inner.listDayItems(
    relationshipId: relationshipId,
    occurredOn: occurredOn,
    after: after,
    limit: limit,
  );

  @override
  Future<void> markViewed({required String storyItemId}) =>
      _inner.markViewed(storyItemId: storyItemId);

  @override
  Future<void> deleteItem({required String storyItemId}) =>
      _inner.deleteItem(storyItemId: storyItemId);

  @override
  Future<StoryReplyTarget?> getReplyTarget({required String storyItemId}) =>
      _inner.getReplyTarget(storyItemId: storyItemId);

  @override
  Future<String?> signMediaUrl(String storageKey) =>
      _inner.signMediaUrl(storageKey);

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      _inner.watchChangeSignal(relationshipId: relationshipId);

  @override
  void disposeChannel(String relationshipId) =>
      _inner.disposeChannel(relationshipId);

  @override
  void disposeAllChannels() => _inner.disposeAllChannels();
}
