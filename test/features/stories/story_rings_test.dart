// Tests for the two story rings on the conversations screen (Plan C,
// Task 3, spec §5.1/§8; task-3-brief.md).
//
// The single most important behaviour under test: `get_story_ring_summary`
// OMITS an author with zero active stories entirely. The absence of a row
// is NOT "do not draw my ring" — the caller draws its own ring from its
// own identity and uses the summary map only to FILL it. Every "my ring"
// test below drives this through `storyRingSummaryProvider` returning a
// map that does NOT contain the current user's id at all (never a
// null/empty entry), matching exactly what the real RPC does — see
// story_read_repository.dart's `StoryRingSummary` doc comment and
// story_providers.dart's `storyRingSummaryProvider` doc comment, both of
// which this test suite assumes rather than re-derives.
//
// Following this feature's house pattern (story_read_repository_test.dart,
// story_outbox_controller_test.dart): never mock SupabaseClient or the
// Riverpod providers' internals — override `storyReadGatewayProvider` with
// a fake `StoryReadGateway`, and for the outbox side override
// `storyOutboxStoreProvider` (a real `StoryOutboxStore.forTesting` seeded
// directly with the record under test) plus `storyGatewayProvider` (a
// gateway whose calls hang forever, so the REAL `StoryOutboxController`
// runs unmodified but never advances a seeded record past the state it
// was given). This keeps the test boundary AT the store/gateway
// interfaces, below which nothing in this file's tests can silently pass
// by accident (the previous task's warning about faking too high a seam
// — faking `storyOutboxProvider` itself, one level higher, would leave
// the real controller's read-and-project logic unexercised).
//
// No real-clock waits anywhere: `storyRingSummaryProvider`'s Future
// resolves synchronously off a fake gateway, and the one animated widget
// in this tree (`_PendingRing`'s indeterminate spinner) is driven with a
// bounded number of `tester.pump()` calls rather than `pumpAndSettle()`,
// which would never return for a `..repeat()` animation controller.

import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/stories/presentation/widgets/story_rings_row.dart';
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

/// A gateway whose ring-summary script is fixed at construction — no
/// mutable "call count" behaviour is needed here since these are single
/// snapshot renders, not refetch tests (Task 2 already covers refetch).
class _FakeRingGateway implements StoryReadGateway {
  _FakeRingGateway({
    List<StoryRingSummary> summary = const [],
    this.noThumbnails = false,
  }) : _summary = summary;

  final List<StoryRingSummary> _summary;
  final Map<String, String?> signedUrlsByKey = {};

  /// When true, [signMediaUrl] always returns null — used by the golden
  /// tests so `_Thumbnail` falls back to a plain neutral fill instead of
  /// routing through `CachedNetworkImage`/`flutter_cache_manager`, which
  /// needs `path_provider` platform channels this test environment does
  /// not provide. The RING GEOMETRY (segments, badge, layout) is what
  /// Step 4 needs eyeballed — the thumbnail bitmap itself is not this
  /// widget's concern, `CachedNetworkImage` is a well-established
  /// third-party widget.
  final bool noThumbnails;

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => List.of(_summary);

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    if (noThumbnails) return null;
    return signedUrlsByKey[storageKey] ?? 'https://signed.example/$storageKey';
  }

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

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
  Future<void> markViewed({required String storyItemId}) async {}

  @override
  Future<void> deleteItem({required String storyItemId}) async {}

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream<void>.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

/// A `StoryGateway` whose every call hangs forever. These tests seed the
/// outbox store directly with a record already in the exact state under
/// test (e.g. `uploadingThumbnail`) and only need `storyOutboxProvider`'s
/// INITIAL read of that persisted state — not the state machine actually
/// advancing it (that is story_outbox_controller_test.dart's job, and
/// re-fed here would just race the widget pump). A never-completing
/// gateway freezes `StoryOutboxController._drive` at whatever async step
/// it is in without ever persisting a different state, so what the
/// widget reads stays exactly what was seeded.
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

StoryOutboxRecord _pendingRecord({
  String relationshipId = _relationshipId,
  StoryOutboxState state = StoryOutboxState.uploadingMedia,
  String localThumbnailPath = '',
}) {
  return StoryOutboxRecord(
    clientStoryId: 'pending-1',
    relationshipId: relationshipId,
    localMediaPath: '/tmp/does-not-exist-media.jpg',
    localThumbnailPath: localThumbnailPath,
    mediaType: CapturedMediaType.image,
    mimeType: 'image/jpeg',
    width: 1080,
    height: 1920,
    utcOffsetMinutes: 0,
    state: state,
    createdAt: DateTime.utc(2026, 9, 12, 8),
  );
}

StoryRingSummary _summary({
  required String authorId,
  required int activeCount,
  required int unviewedCount,
  String thumbnailKey = 'story-media/newest-thumb.jpg',
}) {
  return StoryRingSummary(
    authorId: authorId,
    activeCount: activeCount,
    unviewedCount: unviewedCount,
    newestThumbnailKey: thumbnailKey,
    newestCreatedAt: DateTime.utc(2026, 9, 12, 7),
  );
}

/// Builds the widget tree AND pre-seeds the outbox store with [outbox]
/// records before the `ProviderScope` (and therefore
/// `StoryOutboxController`'s constructor, which reads the store on
/// construction) ever exists — so the controller's very first `flush()`
/// already sees exactly the persisted records under test. Every gateway
/// call the controller could make hangs forever (`_HangingStoryGateway`),
/// so nothing here advances a seeded record past the state it was given.
Future<Widget> _harness({
  required List<StoryRingSummary> summary,
  List<StoryOutboxRecord> outbox = const [],
  ThemeData? theme,
  bool noThumbnails = false,
}) async {
  final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
  for (final record in outbox) {
    await store.put(_myId, record);
  }

  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(_signedInUser),
      storyReadGatewayProvider.overrideWithValue(
        _FakeRingGateway(summary: summary, noThumbnails: noThumbnails),
      ),
      storyOutboxStoreProvider.overrideWithValue(store),
      storyGatewayProvider.overrideWithValue(_HangingStoryGateway()),
    ],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: theme?.colorScheme.surface,
        body: StoryRingsRow(
          relationshipId: _relationshipId,
          partnerId: _partnerId,
          partnerName: 'Alex',
        ),
      ),
    ),
  );
}

/// Finds the [StoryRing] with the given key, or null if absent from the
/// tree entirely — distinct from "present but invisible."
StoryRing? _ringByKey(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<StoryRing>(finder);
}

void main() {
  group('goldens (Step 4 — rendered and looked at)', _goldenMain);

  group('my ring is drawn unconditionally', () {
    testWidgets(
      'my empty ring still renders, with a +, when the RPC returns NO row '
      'for me',
      (tester) async {
        // The summary map does not contain _myId AT ALL — this is exactly
        // what get_story_ring_summary does for an author with zero active
        // stories (never a null/empty entry). Only the partner has a row.
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _partnerId, activeCount: 2, unviewedCount: 1),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final mine = _ringByKey(tester, 'story-ring-mine');
        expect(
          mine,
          isNotNull,
          reason:
              'my ring must be in the tree even though my id is absent '
              'from the ring-summary map',
        );
        expect(mine!.hasStories, isFalse);
        expect(mine.isMine, isTrue);

        // The + must actually be reachable and labelled, not just implied
        // by hasStories being false.
        expect(
          find.bySemanticsLabel('Add to your story'),
          findsOneWidget,
          reason: 'the + must be present and labelled for a11y',
        );
      },
    );

    testWidgets(
      'my ring fills with the newest thumbnail and shows a + badge when '
      'the RPC DOES return a row for me',
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 4, unviewedCount: 4),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final mine = _ringByKey(tester, 'story-ring-mine');
        expect(mine, isNotNull);
        expect(mine!.hasStories, isTrue);
        expect(mine.segmentCount, 4);
      },
    );
  });

  group('partner ring: empty renders nothing at all', () {
    testWidgets(
      'an empty partner ring renders NOTHING — no StoryRing, no '
      'placeholder box',
      (tester) async {
        // Partner is absent from the summary map too (zero active
        // stories) — mine is present so we can be sure the row itself
        // rendered at all.
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 1, unviewedCount: 0),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(_ringByKey(tester, 'story-ring-mine'), isNotNull);
        expect(
          find.byKey(const ValueKey('story-ring-partner')),
          findsNothing,
          reason:
              'an empty partner ring must not exist in the tree at all — '
              'not hidden, not zero-opacity, simply absent',
        );
        // No stray semantics label referencing the partner either — a
        // "greyed ring" implementation might still leave a semantics
        // node behind even with a transparent paint.
        expect(find.textContaining('Alex'), findsNothing);
      },
    );

    testWidgets(
      "partner's ring renders (thumbnail + ring) when they have stories",
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
              _summary(
                authorId: _partnerId,
                activeCount: 3,
                unviewedCount: 2,
                thumbnailKey: 'story-media/partner-thumb.jpg',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final partner = _ringByKey(tester, 'story-ring-partner');
        expect(partner, isNotNull);
        expect(partner!.isMine, isFalse);
        expect(partner.hasStories, isTrue);
        expect(partner.segmentCount, 3);
      },
    );
  });

  group('thumbnail, never an avatar', () {
    testWidgets(
      'the ring is backed by CachedNetworkImage (thumbnail pipeline), not '
      'the conversation avatar widget',
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
              _summary(
                authorId: _partnerId,
                activeCount: 1,
                unviewedCount: 1,
                thumbnailKey: 'story-media/partner-thumb.jpg',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // A thumbnail image widget must exist inside the partner ring's
        // subtree, driven by the signed URL — never an avatar/initials
        // widget (InfoRowWidget's avatar slot, CircleAvatar with
        // initials, etc.).
        final ringFinder = find.byKey(const ValueKey('story-ring-partner'));
        expect(ringFinder, findsOneWidget);
        expect(
          find.descendant(
            of: ringFinder,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'CachedNetworkImage',
            ),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('segmented arc caps at 12', () {
    testWidgets('11 active items: not solid, segment count is 11', (
      tester,
    ) async {
      await tester.pumpWidget(
        await _harness(
          summary: [
            _summary(authorId: _myId, activeCount: 11, unviewedCount: 11),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final mine = _ringByKey(tester, 'story-ring-mine')!;
      expect(mine.segmentCount, 11);
      final painter = _findSegmentedPainter(tester, 'story-ring-mine');
      expect(painter, isNotNull);
      expect(painter!.solid, isFalse);
      expect(painter.segmentCount, 11);
    });

    testWidgets('12 active items: still segmented, exactly at the cap', (
      tester,
    ) async {
      await tester.pumpWidget(
        await _harness(
          summary: [
            _summary(authorId: _myId, activeCount: 12, unviewedCount: 12),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final painter = _findSegmentedPainter(tester, 'story-ring-mine');
      expect(painter, isNotNull);
      expect(painter!.solid, isFalse);
      expect(painter.segmentCount, 12);
    });

    testWidgets('13 active items: drawn solid, capped at 12 segments', (
      tester,
    ) async {
      await tester.pumpWidget(
        await _harness(
          summary: [
            _summary(authorId: _myId, activeCount: 13, unviewedCount: 13),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final painter = _findSegmentedPainter(tester, 'story-ring-mine');
      expect(painter, isNotNull);
      expect(
        painter!.solid,
        isTrue,
        reason: 'beyond 12 active items the ring must draw as one solid '
            'stroke, not 13 hairline arcs',
      );
      expect(
        painter.segmentCount,
        12,
        reason: 'the painter must never be asked to draw more than the '
            'cap even when the underlying count is higher',
      );
    });
  });

  group('viewed segments are faded, not skipped', () {
    testWidgets(
      'partner ring with 4 active items and 1 unviewed still paints 4 '
      'segments total — 1 bright, 3 faded, none omitted',
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
              _summary(authorId: _partnerId, activeCount: 4, unviewedCount: 1),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final painter = _findSegmentedPainter(tester, 'story-ring-partner');
        expect(painter, isNotNull);
        expect(
          painter!.segmentCount,
          4,
          reason:
              'all 4 active items must still occupy a segment slot even '
              'though only 1 is unviewed — a viewed segment is faded, '
              'never dropped from the count',
        );
        expect(painter.unviewedCount, 1);
      },
    );

    testWidgets(
      'fully viewed (0 unviewed of 3): all 3 segments still present, all '
      'faded',
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
              _summary(authorId: _partnerId, activeCount: 3, unviewedCount: 0),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final painter = _findSegmentedPainter(tester, 'story-ring-partner');
        expect(painter, isNotNull);
        expect(painter!.segmentCount, 3);
        expect(painter.unviewedCount, 0);
      },
    );
  });

  group('pending outbox item shows progress on my ring', () {
    testWidgets(
      'a queued/uploading outbox record for this relationship renders a '
      'progress ring on MY tile, not the partner\'s',
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: const [],
            outbox: [
              _pendingRecord(state: StoryOutboxState.uploadingThumbnail),
            ],
          ),
        );
        // Deliberately NOT pumpAndSettle: _PendingRing's AnimationController
        // repeats forever when reduce-motion is off, so settling would hang.
        // A handful of fixed pumps is enough to prove the widget renders
        // and does not throw, with no real-clock wait involved.
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        final mine = _ringByKey(tester, 'story-ring-mine')!;
        expect(mine.hasStories, isTrue);
        expect(mine.pendingProgress, isNotNull);
        expect(mine.pendingProgress, closeTo(0.7, 0.0001));
        expect(find.byKey(const ValueKey('story-ring-partner')), findsNothing);
      },
    );

    testWidgets(
      'a pending record for a DIFFERENT relationship does not affect this '
      'ring',
      (tester) async {
        await tester.pumpWidget(
          await _harness(
            summary: const [],
            outbox: [
              _pendingRecord(
                relationshipId: 'some-other-relationship',
                state: StoryOutboxState.uploadingMedia,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final mine = _ringByKey(tester, 'story-ring-mine')!;
        expect(
          mine.pendingProgress,
          isNull,
          reason:
              'the outbox is per-user, not per-relationship — a pending '
              'item for another relationship must not bleed into this '
              'screen\'s ring',
        );
        expect(mine.hasStories, isFalse);
      },
    );
  });

  group('reduce motion', () {
    testWidgets(
      'a pending ring under reduce-motion renders without an active '
      'AnimationController (no ticking, no repeat)',
      (tester) async {
        tester.view.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.view.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        await tester.pumpWidget(
          await _harness(
            summary: const [],
            outbox: [_pendingRecord(state: StoryOutboxState.finalizing)],
          ),
        );
        // Safe to fully settle here specifically BECAUSE reduce-motion
        // replaces the repeating controller with a static paint.
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('story-ring-mine')), findsOneWidget);
      },
    );
  });
}

/// Reaches into the widget tree to find the `_SegmentedRingPainter` for
/// the ring keyed by [key], via its enclosing `CustomPaint`. Using the
/// painter directly (rather than only checking `StoryRing.segmentCount`)
/// is what actually proves the CAP and the solid-fallback are applied,
/// since `StoryRing.segmentCount` intentionally stores the UNCAPPED
/// value it was given.
_TestPainterInfo? _findSegmentedPainter(WidgetTester tester, String ringKey) {
  final ringFinder = find.byKey(ValueKey(ringKey));
  final customPaints = find.descendant(
    of: ringFinder,
    matching: find.byWidgetPredicate((w) => w is CustomPaint),
  );
  for (final element in customPaints.evaluate()) {
    final widget = element.widget as CustomPaint;
    final painter = widget.painter;
    if (painter != null &&
        painter.runtimeType.toString() == '_SegmentedRingPainter') {
      // Reflection-free extraction: read the fields back via toString is
      // fragile, so instead the painter type exposes them as public
      // final fields already (segmentCount/unviewedCount/solid) — access
      // via dynamic since the type is private to story_ring.dart.
      final dynamic p = painter;
      return _TestPainterInfo(
        segmentCount: p.segmentCount as int,
        unviewedCount: p.unviewedCount as int,
        solid: p.solid as bool,
      );
    }
  }
  return null;
}

class _TestPainterInfo {
  _TestPainterInfo({
    required this.segmentCount,
    required this.unviewedCount,
    required this.solid,
  });

  final int segmentCount;
  final int unviewedCount;
  final bool solid;
}

/// Rendered and looked at (brief Step 4): a passing widget test proves
/// the tree shape, not whether the ring actually reads as a ring at a
/// glance. Both themes, mine partially-viewed + partner's ring, so the
/// bright/faded segment split and the + badge are both visible in the
/// same frame.
void _goldenMain() {
  Future<Widget> rowFixture(ThemeData theme) => _harness(
    theme: theme,
    noThumbnails: true,
    summary: [
      _summary(
        authorId: _myId,
        activeCount: 5,
        unviewedCount: 5,
        thumbnailKey: 'story-media/mine-thumb.jpg',
      ),
      _summary(
        authorId: _partnerId,
        activeCount: 6,
        unviewedCount: 2,
        thumbnailKey: 'story-media/partner-thumb.jpg',
      ),
    ],
  );

  testWidgets('story rings row, light theme', (tester) async {
    await tester.pumpWidget(await rowFixture(AppTheme.lightTheme));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StoryRingsRow),
      matchesGoldenFile('goldens/story_rings_light.png'),
    );
  });

  testWidgets('story rings row, dark theme', (tester) async {
    await tester.pumpWidget(await rowFixture(AppTheme.darkTheme));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StoryRingsRow),
      matchesGoldenFile('goldens/story_rings_dark.png'),
    );
  });
}
