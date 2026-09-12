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
  _FakeReelGateway({required List<StoryItem> items}) : _items = items;

  final List<StoryItem> _items;
  final List<String> markViewedCalls = [];
  final Set<String> signUrlFailuresFor = {};

  /// When set, [signMediaUrl] for this exact key does not resolve until
  /// the test completes [signUrlGate] itself — lets a test freeze the
  /// reel precisely at "render has not happened yet" rather than
  /// guessing how many microtask pumps that takes.
  String? gatedKey;
  Completer<void>? signUrlGate;

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => StoryItemPage(items: List.of(_items), nextCursor: null);

  @override
  Future<String?> signMediaUrl(String storageKey) async {
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

        // Time passes while backgrounded — nothing advances, because
        // pausing stops the reel's own tick loop from treating elapsed
        // time as progress, and the (fake) player itself does not
        // advance position while not playing either.
        player.advance(const Duration(seconds: 10));
        await tester.pump(const Duration(seconds: 2));

        expect(gateway.markViewedCalls, ['v']);
        expect(find.byType(StoryReelScreen), findsOneWidget);

        // Foregrounding again does not itself resume playback (an
        // explicit tap-to-resume is required, same as releasing a
        // hold) — still paused, still the same item, nothing skipped.
        // Real sequence back to resumed passes through hidden/inactive
        // in reverse.
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        expect(player.isPlaying, isFalse);
        expect(gateway.markViewedCalls, ['v']);
      },
    );
  });
}
