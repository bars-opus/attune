// Tests for the reel — the full-screen story viewer (Plan C, Task 4;
// spec §5.2/§5.5; task-4-brief.md).
//
// House pattern, unchanged from Task 2/3: never mock SupabaseClient or
// Riverpod internals — override `storyReadGatewayProvider` with a fake
// `StoryReadGateway` (`_FakeReelGateway` below) and drive the real
// providers/widget through a `ProviderScope`.
//
// THE PLAYER SEAM: `VideoPlayerController.initialize()` always rejects
// in this test host (no platform decoder — see
// `ephemeral_video_viewer_screen_test.dart`'s own notes). Constructing
// one directly inside the reel would make every video test exercise
// only the error path. `StoryReelScreen.videoPlayerFactory` lets this
// suite substitute `_FakeStoryItemPlayer`, which reports
// initialized/duration/position/onEnded on command with no platform
// channel involved at all. See `story_reel_screen.dart`'s header for
// exactly what this leaves unexercised below the seam (the real
// VideoPlayerController <-> platform-channel <-> codec path).
//
// NO REAL-CLOCK WAITS: every wait below is `tester.pump(duration)`,
// which advances the FakeAsync zone `testWidgets` already runs inside
// (see AutomatedTestWidgetsFlutterBinding) — never a bare
// `Future.delayed` against the real clock. The 5-second image hold is
// driven this way, with `imageHoldDuration` also shortened via the
// screen's own test seam so the assertions stay fast without weakening
// what production actually holds for (`kStoryImageHoldDuration`, which
// a separate test pins directly).

import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String mediaType = 'image',
  String authorId = _partnerId,
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
    expiresAt: createdAt.add(const Duration(hours: 24)),
    hasBeenViewed: false,
  );
}

/// Fixed-script fake: the reel's own page provider handles refresh/paging
/// (Task 2, already tested there), so this fake only needs to answer with
/// one page and record calls this suite asserts against.
class _FakeReelGateway implements StoryReadGateway {
  _FakeReelGateway({required List<StoryItem> items})
    : _items = items,
      _pages = null;

  /// Fix round 1, F3: an alternate constructor for a paged script —
  /// `pages[0]` answers the first `listActiveItems` call (`after ==
  /// null`), `pages[1]` the second (once the reel calls `loadMore()`),
  /// and so on. Lets a test prove the reel actually calls `loadMore()`
  /// at the page boundary rather than treating `items.length` as the
  /// end of the whole reel.
  _FakeReelGateway.paged({required List<List<StoryItem>> pages})
    : _items = pages.isEmpty ? const [] : pages.first,
      _pages = pages;

  final List<StoryItem> _items;
  final List<List<StoryItem>>? _pages;
  int _listActiveItemsCallCount = 0;
  int get listActiveItemsCallCount => _listActiveItemsCallCount;
  final List<String> markViewedCalls = [];
  final Set<String> signUrlFailuresFor = {};

  /// When set, [signMediaUrl] for this exact key does not resolve until
  /// the test completes [signUrlGate] itself — lets a test freeze the
  /// reel precisely at "render has not happened yet" rather than
  /// guessing how many microtask pumps that takes.
  String? gatedKey;
  Completer<void>? signUrlGate;

  /// Every [signMediaUrl] call, in order — fix round 1, F5's regression
  /// guard needs to prove exactly ONE mint per image item, not two.
  final List<String> _signUrlCalls = [];

  int signUrlCallsFor(String storageKey) =>
      _signUrlCalls.where((k) => k == storageKey).length;

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async {
    final pages = _pages;
    if (pages == null) {
      _listActiveItemsCallCount++;
      return StoryItemPage(items: List.of(_items), nextCursor: null);
    }
    // Keyset-shaped fake: `after == null` is always page 0; any
    // non-null cursor is "the next page after whatever came before" —
    // sufficient for this suite, which never asks for a THIRD page.
    final pageIndex = after == null ? 0 : _listActiveItemsCallCount;
    _listActiveItemsCallCount++;
    if (pageIndex >= pages.length) {
      return const StoryItemPage(items: [], nextCursor: null);
    }
    final pageItems = pages[pageIndex];
    final isLastPage = pageIndex == pages.length - 1;
    return StoryItemPage(
      items: pageItems,
      nextCursor: isLastPage || pageItems.isEmpty
          ? null
          : StoryPageCursor(
              createdAt: pageItems.last.createdAt,
              id: pageItems.last.id,
            ),
    );
  }

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    _signUrlCalls.add(storageKey);
    if (storageKey == gatedKey) {
      await signUrlGate!.future;
    }
    if (signUrlFailuresFor.contains(storageKey)) return null;
    return 'https://signed.example/$storageKey';
  }

  @override
  Future<void> markViewed({required String storyItemId}) async {
    markViewedCalls.add(storyItemId);
  }

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => const [];

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => const [];

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<void> deleteItem({required String storyItemId}) async {}

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => null;

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

/// Drives [StoryItemPlayer] entirely under test control — see this
/// file's header for why this exists. `complete()` simulates the video
/// reaching its natural end (fires `onEnded` exactly once, mirroring
/// [VideoControllerStoryItemPlayer]'s own latch).
class _FakeStoryItemPlayer implements StoryItemPlayer {
  _FakeStoryItemPlayer({this.duration = const Duration(seconds: 4)});

  @override
  final Duration duration;

  Duration _position = Duration.zero;
  bool _playing = false;
  bool disposed = false;
  bool initializeCalled = false;
  final _endedController = StreamController<void>.broadcast();

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Duration get position => _position;

  @override
  void play() => _playing = true;

  @override
  void pause() => _playing = false;

  bool get isPlaying => _playing;

  @override
  Stream<void> get onEnded => _endedController.stream;

  /// Advances position by [by] — only while "playing," mirroring a real
  /// player's position not advancing while paused.
  void advance(Duration by) {
    if (!_playing) return;
    _position += by;
  }

  /// Advances position UNCONDITIONALLY, ignoring [_playing] — used only
  /// to prove the REEL's own ticker is what stops progress while
  /// backgrounded, not this fake's own early-return in [advance].
  ///
  /// Fix round 1, F9: a background test previously used [advance] here,
  /// which is a no-op whenever `_playing` is false — so "nothing
  /// advanced" was trivially true because THIS FAKE swallowed the call,
  /// regardless of anything the reel itself did. `_startTicker`'s tick
  /// callback (`story_reel_screen.dart`) reads `player.position`
  /// directly when a player exists, so forcing the position past
  /// [duration] here and then pumping genuinely exercises the reel's
  /// OWN `if (!mounted || generation != _generation || _paused) return;`
  /// guard — if that guard were ever deleted, this test would now
  /// observe an advance to 'after' that [advance] alone could never
  /// have revealed.
  void forceAdvancePastEnd() {
    _position = duration + const Duration(seconds: 1);
  }

  void complete() {
    _position = duration;
    _playing = false;
    if (!_endedController.isClosed) _endedController.add(null);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _endedController.close();
  }
}

/// One player per video item, in item order, so a multi-video-item test
/// can reach into `players[i]` for the i-th video mint.
class _FakePlayerFactory {
  final List<_FakeStoryItemPlayer> players = [];

  StoryItemPlayer Function(Uri uri) get factory => (uri) {
    final player = _FakeStoryItemPlayer();
    players.add(player);
    return player;
  };
}

Widget _harness({
  required StoryReadGateway gateway,
  StoryItemPlayer Function(Uri uri)? videoPlayerFactory,
  Duration imageHoldDuration = const Duration(seconds: 5),
  bool isOwnReel = false,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(_signedInUser),
      storyReadGatewayProvider.overrideWithValue(gateway),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: StoryReelScreen(
        relationshipId: _relationshipId,
        authorId: _partnerId,
        isOwnReel: isOwnReel,
        videoPlayerFactory: videoPlayerFactory,
        imageHoldDuration: imageHoldDuration,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'fix round 1, F2: two callers racing on the same stale generation '
    'cannot double-advance',
    () {
      testWidgets(
        'two _advance calls that both captured the SAME generation '
        '(e.g. onEnded and a tap landing in the same frame) advance '
        'exactly ONE item, never skipping the middle one',
        (tester) async {
          final items = [
            _item(id: 'a', createdAt: DateTime.utc(2026, 9, 1)),
            _item(id: 'b', createdAt: DateTime.utc(2026, 9, 2)),
            _item(id: 'c', createdAt: DateTime.utc(2026, 9, 3)),
          ];
          final gateway = _FakeReelGateway(items: items);

          await tester.pumpWidget(_harness(gateway: gateway));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(gateway.markViewedCalls, ['a']);

          // Fix round 1, F2's exact race — two callers who both
          // observed the SAME `_generation` (a video's `onEnded` firing
          // in the same frame as a tap-right is the realistic trigger)
          // each calling `_advance` before either's own `_startItem`
          // has run. The public gesture-testing API cannot force this:
          // `tester.tap()`/`tapAt()` fully settle each dispatched
          // gesture — including any interleaved stream microtask —
          // before returning, so two sequential taps are provably
          // sequential, never actually concurrent, and never exercise
          // this guard. `raceAdvanceForTest` (a `@visibleForTesting`
          // hook on the State, mirroring `StreakViewerScreen
          // .finishForTest()`'s own precedent for exactly this kind of
          // problem) captures `_generation` ONCE and fires two
          // `_advance` calls with it, reproducing the race directly:
          // without the `fromGeneration == _generation` guard, the
          // SECOND call would still act on the pre-advance `_index`,
          // skipping 'b' and marking it viewed despite it never
          // rendering for a single frame.
          final state = tester.state(find.byType(StoryReelScreen));
          await (state as dynamic).raceAdvanceForTest(items);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Exactly ONE advance: on 'b', not skipped to 'c'.
          expect(gateway.markViewedCalls, ['a', 'b']);
          expect(gateway.markViewedCalls, isNot(contains('c')));
        },
      );
    },
  );

  group('fix round 1, F3: paging past the first page', () {
    testWidgets(
      'advancing past the last item of a short first page calls '
      'loadMore() and reaches the next page, rather than closing',
      (tester) async {
        final page1 = [
          _item(id: 'i0', createdAt: DateTime.utc(2026, 9, 1)),
          _item(id: 'i1', createdAt: DateTime.utc(2026, 9, 2)),
        ];
        final page2 = [_item(id: 'i2', createdAt: DateTime.utc(2026, 9, 3))];
        final gateway = _FakeReelGateway.paged(pages: [page1, page2]);

        await tester.pumpWidget(_harness(gateway: gateway));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(gateway.markViewedCalls, ['i0']);
        expect(gateway.listActiveItemsCallCount, 1);

        final size = tester.getSize(find.byType(StoryReelScreen));
        // i0 -> i1 (still within page 1, no loadMore needed yet).
        await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(gateway.markViewedCalls, ['i0', 'i1']);
        expect(gateway.listActiveItemsCallCount, 1);

        // i1 is the last item of the loaded page. Advancing past it
        // must call loadMore() (a SECOND listActiveItems call) and land
        // on i2 — not close the reel as if the story were over.
        await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(gateway.listActiveItemsCallCount, 2);
        expect(gateway.markViewedCalls, ['i0', 'i1', 'i2']);
        expect(find.byType(StoryReelScreen), findsOneWidget);
      },
    );

    testWidgets(
      'reaching the end of the LAST page (hasMore false) still closes '
      'the reel normally',
      (tester) async {
        final items = [_item(id: 'only', createdAt: DateTime.utc(2026, 9, 1))];
        final gateway = _FakeReelGateway.paged(pages: [items]);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProviderScope(
                      overrides: [
                        currentUserProvider.overrideWithValue(_signedInUser),
                        storyReadGatewayProvider.overrideWithValue(gateway),
                      ],
                      child: StoryReelScreen(
                        relationshipId: _relationshipId,
                        authorId: _partnerId,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final size = tester.getSize(find.byType(StoryReelScreen));
        await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
        await tester.pumpAndSettle();

        expect(find.byType(StoryReelScreen), findsNothing);
      },
    );
  });

  group('the reel opens at the OLDEST active item', () {
    testWidgets(
      'index 0 (the oldest, since items arrive oldest-first) plays first, '
      'not the newest item',
      (tester) async {
        final oldest = _item(
          id: 'old',
          createdAt: DateTime.utc(2026, 9, 1),
        );
        final newest = _item(
          id: 'new',
          createdAt: DateTime.utc(2026, 9, 10),
        );
        // Oldest-first, matching what list_active_story_items actually
        // returns (spec §5.5) — this fake does not reorder.
        final gateway = _FakeReelGateway(items: [oldest, newest]);

        await tester.pumpWidget(_harness(gateway: gateway));
        await tester.pump(); // build
        await tester.pump(); // post-frame callback kicks off _startItem
        await tester.pump(const Duration(milliseconds: 50));

        // The signed URL requested is the OLDEST item's media key, not
        // the newest's — proves playback started at index 0 = oldest.
        expect(find.byKey(const ValueKey('story-progress-0')), findsNothing);
        // Direct behavioural proof: mark_story_viewed (fired after
        // render) is called with the oldest item's id first.
        await tester.pump(const Duration(seconds: 6));
        expect(gateway.markViewedCalls, isNotEmpty);
        expect(gateway.markViewedCalls.first, 'old');
      },
    );
  });

  group('tap right advances, tap left goes back', () {
    testWidgets('tapping the right half moves to the next item', (
      tester,
    ) async {
      final items = [
        _item(id: 'a', createdAt: DateTime.utc(2026, 9, 1)),
        _item(id: 'b', createdAt: DateTime.utc(2026, 9, 2)),
      ];
      final gateway = _FakeReelGateway(items: items);

      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // First item rendered and marked viewed.
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.markViewedCalls, ['a']);

      // Tap the right half of the screen.
      final size = tester.getSize(find.byType(StoryReelScreen));
      await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.markViewedCalls, ['a', 'b']);
    });

    testWidgets('tapping the left half moves back to the previous item', (
      tester,
    ) async {
      final items = [
        _item(id: 'a', createdAt: DateTime.utc(2026, 9, 1)),
        _item(id: 'b', createdAt: DateTime.utc(2026, 9, 2)),
      ];
      final gateway = _FakeReelGateway(items: items);

      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Advance to item b first.
      final size = tester.getSize(find.byType(StoryReelScreen));
      await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.markViewedCalls, ['a', 'b']);

      // Now tap left: goes back to item a. a is already marked, so the
      // call list must NOT grow — proving navigation moved back to 'a'
      // rather than forward again or nowhere.
      await tester.tapAt(Offset(size.width * 0.2, size.height / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.markViewedCalls, ['a', 'b']);
    });

    testWidgets('tapping left on the first item stays put (no crash, no '
        'call beyond bounds)', (tester) async {
      final items = [_item(id: 'a', createdAt: DateTime.utc(2026, 9, 1))];
      final gateway = _FakeReelGateway(items: items);

      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final size = tester.getSize(find.byType(StoryReelScreen));
      await tester.tapAt(Offset(size.width * 0.2, size.height / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Still on 'a', not popped, not re-marked (already marked once).
      expect(gateway.markViewedCalls, ['a']);
      expect(find.byType(StoryReelScreen), findsOneWidget);
    });
  });

  group('hold pauses, release resumes', () {
    testWidgets(
      'holding the screen pauses the video player; releasing resumes it',
      (tester) async {
        final items = [
          _item(id: 'v', createdAt: DateTime.utc(2026, 9, 1), mediaType: 'video'),
        ];
        final gateway = _FakeReelGateway(items: items);
        final playerFactory = _FakePlayerFactory();

        await tester.pumpWidget(
          _harness(
            gateway: gateway,
            videoPlayerFactory: playerFactory.factory,
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final player = playerFactory.players.single;
        expect(player.isPlaying, isTrue);

        final center = tester.getCenter(find.byType(StoryReelScreen));
        final gesture = await tester.startGesture(center);
        // Several smaller pumps rather than one big one: startGesture's
        // own pointer-down routing consumes some of the first pump
        // window before onTapDown actually fires and starts
        // _GestureLayer's 200ms hold timer, so the total wall-clock
        // budget here is deliberately generous past that threshold.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(player.isPlaying, isFalse);

        await gesture.up();
        await tester.pump();

        expect(player.isPlaying, isTrue);
      },
    );
  });

  group('swipe down dismisses', () {
    testWidgets('a confident downward drag pops the reel', (tester) async {
      final items = [_item(id: 'a', createdAt: DateTime.utc(2026, 9, 1))];
      final gateway = _FakeReelGateway(items: items);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProviderScope(
                    overrides: [
                      currentUserProvider.overrideWithValue(_signedInUser),
                      storyReadGatewayProvider.overrideWithValue(gateway),
                    ],
                    child: StoryReelScreen(
                      relationshipId: _relationshipId,
                      authorId: _partnerId,
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(StoryReelScreen), findsOneWidget);

      final center = tester.getCenter(find.byType(StoryReelScreen));
      await tester.dragFrom(center, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.byType(StoryReelScreen), findsNothing);
    });
  });

  group('an image holds for 5 seconds, a video runs its length', () {
    testWidgets('an image advances to the next item after exactly the hold '
        'duration, not before', (tester) async {
      final items = [
        _item(id: 'img', createdAt: DateTime.utc(2026, 9, 1)),
        _item(id: 'next', createdAt: DateTime.utc(2026, 9, 2)),
      ];
      final gateway = _FakeReelGateway(items: items);
      const hold = Duration(seconds: 5);

      await tester.pumpWidget(
        _harness(gateway: gateway, imageHoldDuration: hold),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.markViewedCalls, ['img']);

      // Just under the hold: still on the first item.
      await tester.pump(hold - const Duration(milliseconds: 200));
      expect(gateway.markViewedCalls, ['img']);

      // Cross the hold: advances to 'next' and marks it viewed.
      await tester.pump(const Duration(milliseconds: 300));
      expect(gateway.markViewedCalls, ['img', 'next']);
    });

    testWidgets(
      "a video's advance is driven by its own length, not the image hold "
      'duration',
      (tester) async {
        final items = [
          _item(
            id: 'v',
            createdAt: DateTime.utc(2026, 9, 1),
            mediaType: 'video',
          ),
          _item(id: 'after', createdAt: DateTime.utc(2026, 9, 2)),
        ];
        final gateway = _FakeReelGateway(items: items);
        final playerFactory = _FakePlayerFactory();

        await tester.pumpWidget(
          _harness(
            gateway: gateway,
            videoPlayerFactory: playerFactory.factory,
            // A long image hold, so if the reel mistakenly used it for
            // the VIDEO item instead of the player's own end signal,
            // this test would time out waiting rather than false-pass.
            imageHoldDuration: const Duration(seconds: 30),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(gateway.markViewedCalls, ['v']);

        final player = playerFactory.players.single;
        // The video's own natural end (4s, well under the 30s image
        // hold configured above) advances the reel via onEnded.
        player.complete();
        // Several pumps: the broadcast stream's onEnded delivery, the
        // signed-url fetch for the NEXT item, and mark_story_viewed are
        // each a separate async gap.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(gateway.markViewedCalls, ['v', 'after']);
      },
    );
  });

  group('a view is marked only AFTER a successful render', () {
    testWidgets('markViewed is NOT called merely on open, before the item '
        'has rendered', (tester) async {
      final items = [_item(id: 'a', createdAt: DateTime.utc(2026, 9, 1))];
      final gateway = _FakeReelGateway(items: items)
        ..gatedKey = 'story-media/a.jpg'
        ..signUrlGate = Completer<void>();

      await tester.pumpWidget(_harness(gateway: gateway));
      await tester.pump(); // build
      await tester.pump(); // post-frame callback kicks off _startItem,
      // which is now blocked awaiting gateway.signMediaUrl — the item
      // has NOT rendered yet. This is the render boundary the spec
      // cares about: opening the screen must not itself mark a view.
      await tester.pump(const Duration(milliseconds: 50));

      expect(gateway.markViewedCalls, isEmpty);

      // Release the gate: the signed URL resolves, the item renders,
      // and only now does markViewed fire.
      gateway.signUrlGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(gateway.markViewedCalls, ['a']);
    });

    testWidgets(
      'a failed signed-url fetch (no render) never calls markViewed',
      (tester) async {
        final items = [_item(id: 'a', createdAt: DateTime.utc(2026, 9, 1))];
        final gateway = _FakeReelGateway(items: items)
          ..signUrlFailuresFor.add('story-media/a.jpg');

        await tester.pumpWidget(_harness(gateway: gateway));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(gateway.markViewedCalls, isEmpty);
      },
    );

    testWidgets('the author previewing their own reel never calls '
        'markViewed, even after rendering', (tester) async {
      final items = [
        _item(id: 'a', createdAt: DateTime.utc(2026, 9, 1), authorId: _myId),
      ];
      final gateway = _FakeReelGateway(items: items);

      await tester.pumpWidget(_harness(gateway: gateway, isOwnReel: true));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      expect(gateway.markViewedCalls, isEmpty);
    });
  });

  group('backgrounding mid-item pauses rather than skipping', () {
    testWidgets(
      'a video does not advance while the app is backgrounded, and stays '
      'on the same item once foregrounded again',
      (tester) async {
        final items = [
          _item(
            id: 'v',
            createdAt: DateTime.utc(2026, 9, 1),
            mediaType: 'video',
          ),
          _item(id: 'after', createdAt: DateTime.utc(2026, 9, 2)),
        ];
        final gateway = _FakeReelGateway(items: items);
        final playerFactory = _FakePlayerFactory();

        await tester.pumpWidget(
          _harness(
            gateway: gateway,
            videoPlayerFactory: playerFactory.factory,
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final player = playerFactory.players.single;
        expect(player.isPlaying, isTrue);
        expect(gateway.markViewedCalls, ['v']);

        // Background the app. The real OS sequence is resumed ->
        // inactive -> paused (AppLifecycleListener asserts valid
        // transitions), so this drives both steps rather than jumping
        // straight to paused.
        final binding = TestWidgetsFlutterBinding.instance;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        expect(player.isPlaying, isFalse);

        // Time passes while backgrounded — nothing advances. Force the
        // FAKE's position past its own duration regardless of playing
        // state (fix round 1, F9 — see forceAdvancePastEnd's own doc
        // comment for why plain `advance()` here would have tested the
        // fake instead of the reel), then pump: if the reel's own
        // `_paused` guard in `_startTicker` were ever removed, this
        // would now observe an advance to 'after' that the old
        // `advance()`-based version could never have caught.
        player.forceAdvancePastEnd();
        await tester.pump(const Duration(seconds: 2));

        expect(gateway.markViewedCalls, ['v']);
        expect(find.byType(StoryReelScreen), findsOneWidget);

        // Fix round 1, F1: foregrounding again RESUMES playback. The
        // reel must not stay frozen after a routine backgrounding (an
        // `inactive` blip from Control Centre, an incoming-call
        // banner) — spec §5.2's table names "Lifecycle pause/RESUME" as
        // one requirement, and there was previously no gesture anywhere
        // that could clear a lifecycle pause once set (a plain tap
        // navigates instead of resuming), which froze the reel until
        // the user happened to long-press-and-release. Real sequence
        // back to resumed passes through hidden/inactive in reverse.
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        expect(player.isPlaying, isTrue);
        expect(gateway.markViewedCalls, ['v']);
      },
    );

    testWidgets(
      'holding through a backgrounding keeps the reel paused on resume — '
      'a lifecycle resume must not override a hold still in progress',
      (tester) async {
        final items = [
          _item(
            id: 'v',
            createdAt: DateTime.utc(2026, 9, 1),
            mediaType: 'video',
          ),
        ];
        final gateway = _FakeReelGateway(items: items);
        final playerFactory = _FakePlayerFactory();

        await tester.pumpWidget(
          _harness(
            gateway: gateway,
            videoPlayerFactory: playerFactory.factory,
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final player = playerFactory.players.single;

        // Start a hold, then background WHILE still holding (e.g. a
        // notification banner drags the finger's context away, or the
        // hold simply outlasts an app switch).
        final center = tester.getCenter(find.byType(StoryReelScreen));
        final gesture = await tester.startGesture(center);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(player.isPlaying, isFalse);

        final binding = TestWidgetsFlutterBinding.instance;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        // Foreground again WITHOUT releasing the hold yet.
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        // Still paused: the hold is still in effect and must win over
        // the lifecycle resume (fix round 1, F1's _heldPaused/
        // _lifecyclePaused split).
        expect(player.isPlaying, isFalse);

        // Now release the hold: THIS is what resumes it.
        await gesture.up();
        await tester.pump();
        expect(player.isPlaying, isTrue);
      },
    );
  });

  group('fix round 1, F4: progress bars render across the top', () {
    testWidgets(
      'the progress bars sit in the top quarter of the screen, not at '
      'screen centre',
      (tester) async {
        final items = [
          _item(id: 'a', createdAt: DateTime.utc(2026, 9, 1)),
          _item(id: 'b', createdAt: DateTime.utc(2026, 9, 2)),
        ];
        final gateway = _FakeReelGateway(items: items);

        await tester.pumpWidget(_harness(gateway: gateway));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final screenSize = tester.getSize(find.byType(StoryReelScreen));
        final barsRect = tester.getRect(find.byType(StoryProgressBars));

        // Fix round 1, F4: a bare SafeArea (non-Positioned) inside a
        // StackFit.expand Stack used to stretch to the full screen
        // height, and StoryProgressBars' Row (only 3dp tall) centred
        // itself inside that stretched box — landing at y ≈ screen
        // mid-height instead of "across the top" (spec §5.2's first
        // sentence). Asserting the bars sit in the top quarter is a
        // geometry check the previous suite had none of; it fails
        // immediately if the centring regresses.
        expect(
          barsRect.top,
          lessThan(screenSize.height / 4),
          reason:
              'progress bars must render near the top of the screen, '
              'not centred — got top=${barsRect.top} on a '
              '${screenSize.height}-tall screen',
        );
      },
    );
  });

  group('fix round 1, F5: one signed URL minted per image item', () {
    testWidgets(
      'an image item mints exactly ONE signed URL, not two',
      (tester) async {
        final items = [_item(id: 'a', createdAt: DateTime.utc(2026, 9, 1))];
        final gateway = _FakeReelGateway(items: items);

        await tester.pumpWidget(_harness(gateway: gateway));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Fix round 1, F5: _startItemAsync used to mint one URL (only
        // to check non-null, then discard it for an image), and
        // _MediaView independently minted a SECOND one via
        // storyMediaSignedUrlProvider — one wasted create_signed_url
        // round-trip per image. Now _MediaView renders the URL
        // _startItemAsync already confirmed, so this must be exactly
        // one call for the one image item on screen.
        expect(gateway.signUrlCallsFor('story-media/a.jpg'), 1);

        // The rendered Image widget's URL must be the SAME one that
        // gated `_rendered`/markViewed — not a second, independently
        // minted (and possibly disagreeing) URL.
        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as NetworkImage;
        expect(provider.url, 'https://signed.example/story-media/a.jpg');
      },
    );
  });
}
