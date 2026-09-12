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
import 'dart:ui' as ui;

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
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => null;

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
  VoidCallback? onOpenMine,
  VoidCallback? onCapture,
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
          onOpenMine: onOpenMine,
          onCapture: onCapture,
        ),
      ),
    ),
  );
}

/// Finds the [StoryRing] rendered under the given key, or null if absent
/// from the tree entirely — distinct from "present but invisible."
///
/// The key is attached to whichever widget `StoryRingsRow` places at
/// that ring's slot — sometimes a bare [StoryRing] (mine-empty, mine-
/// pending, mine-with-stories-but-summary-still-loading), sometimes the
/// private `_MineRing`/`_PartnerRing` wrapper that watches
/// `storyMediaSignedUrlProvider` and builds a [StoryRing] itself
/// (finding F1 — my ring needed the same signed-URL wiring the partner's
/// already had, so it moved behind the same kind of wrapper). Looking
/// for "the StoryRing at or below this keyed element" rather than
/// "the StoryRing that IS this keyed element" keeps this helper (and
/// every test using it) agnostic to which of those two shapes is
/// currently in the tree.
StoryRing? _ringByKey(WidgetTester tester, String key) {
  final keyedFinder = find.byKey(ValueKey(key));
  if (keyedFinder.evaluate().isEmpty) return null;
  final keyedWidget = tester.widget(keyedFinder);
  if (keyedWidget is StoryRing) return keyedWidget;

  final ringFinder = find.descendant(
    of: keyedFinder,
    matching: find.byType(StoryRing),
  );
  if (ringFinder.evaluate().isEmpty) return null;
  return tester.widget<StoryRing>(ringFinder);
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

        // The test name has claimed "shows a + badge" since this test
        // was written, but nothing below actually asserted it — the
        // review's mutation 3 (removing the `+` from the my-with-stories
        // ring entirely) proved this: all behavioural tests kept
        // passing and only the goldens caught it. This assertion closes
        // that gap: it fails on its own if the badge is ever removed
        // again, without depending on a bitmap.
        expect(
          find.bySemanticsLabel('Add to your story'),
          findsOneWidget,
          reason:
              'the + badge must still be present (and reachable/labelled '
              'for a11y) on a my-ring that already has stories, not only '
              'on the empty one — spec §5.1 state 2',
        );
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

    testWidgets(
      'MY ring is also backed by CachedNetworkImage once I have stories '
      'and no pending capture is in flight (review finding F1)',
      (tester) async {
        // This is the exact regression the review caught: my ring took
        // `localThumbnailPath` (pending-only) but never `thumbnailUrl`,
        // and never watched `storyMediaSignedUrlProvider` — so once a
        // post finalized and the pending record cleared, my ring stayed
        // a flat grey disc forever while the partner's ring, right next
        // to it, showed a real photo. Unlike the golden (which forces
        // `noThumbnails: true` for reasons unrelated to this bug — see
        // `_FakeRingGateway.noThumbnails`'s doc comment), this test
        // leaves thumbnails ON, so it fails on its own if the wiring
        // regresses, without depending on a bitmap at all.
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(
                authorId: _myId,
                activeCount: 3,
                unviewedCount: 3,
                thumbnailKey: 'story-media/mine-thumb.jpg',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final ringFinder = find.byKey(const ValueKey('story-ring-mine'));
        expect(ringFinder, findsOneWidget);
        expect(
          find.descendant(
            of: ringFinder,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'CachedNetworkImage',
            ),
          ),
          findsOneWidget,
          reason:
              'my own ring must render a thumbnail once I have stories, '
              'exactly like the partner\'s ring does — spec §5.1 state 2',
        );

        final mine = _ringByKey(tester, 'story-ring-mine')!;
        expect(
          mine.thumbnailUrl,
          isNotNull,
          reason: 'StoryRing.thumbnailUrl must actually be populated for '
              'my own ring, not just localThumbnailPath (pending-only)',
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

    testWidgets(
      'faded segments are ACTUALLY PAINTED at a lower alpha than bright '
      'segments — sampled from real pixels, not just counted (test-'
      'quality gap flagged by review)',
      (tester) async {
        // The two tests above only ever assert `segmentCount`/
        // `unviewedCount` — integers — never a colour. The review proved
        // (mutation 4: removing the fade entirely, i.e. always painting
        // with `brightColor` regardless of viewed/unviewed) that both
        // tests keep passing with fading completely gone; only the
        // checked-in golden bitmaps caught it.
        //
        // A first attempt at this test read the painter's
        // `brightColor`/`fadedColor` CONSTRUCTOR fields directly — but
        // those are still both non-null and different even when the
        // paint LOOP ignores `fadedColor` entirely (mutation 4 changes
        // which field gets used per segment, not the fields themselves).
        // That version of this test did not actually catch mutation 4.
        // This version renders the real painter to an offscreen image
        // and samples actual pixels at a bright-segment angle and a
        // faded-segment angle, which is what mutation 4 actually changes
        // and therefore what must be asserted on directly.
        await tester.pumpWidget(
          await _harness(
            // This test never looks at the thumbnail image, only the
            // segmented-ring painter — noThumbnails avoids routing
            // through CachedNetworkImage/flutter_cache_manager, which
            // needs path_provider platform channels this test
            // environment does not provide (same reason the goldens use
            // it; see _FakeRingGateway.noThumbnails's doc comment).
            noThumbnails: true,
            summary: [
              _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
              // 1 of 4 active items unviewed: index 0 (top of the ring,
              // clockwise from -pi/2) is bright; the rest, including
              // index 2 (directly opposite, unambiguously past the first
              // segment+gap), are faded.
              _summary(authorId: _partnerId, activeCount: 4, unviewedCount: 1),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final painter = _findSegmentedCustomPainter(
          tester,
          'story-ring-partner',
        );
        expect(painter, isNotNull);

        const size = Size(69, 69);
        // picture.toImage()/image.toByteData() are genuinely async (a
        // real engine round-trip, not just a Future.value) — they never
        // complete inside testWidgets' fake-async zone. tester.runAsync
        // steps outside that zone for exactly this kind of real I/O.
        final byteData = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          painter!.paint(canvas, size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            size.width.ceil(),
            size.height.ceil(),
          );
          return image.toByteData(format: ui.ImageByteFormat.rawRgba);
        });
        expect(byteData, isNotNull);

        Color pixelAt(int x, int y) {
          final offset = (y * size.width.ceil() + x) * 4;
          final bytes = byteData!.buffer.asUint8List();
          return Color.fromARGB(
            bytes[offset + 3],
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
          );
        }

        // Bright segment: top-center of the ring (the arc starts at
        // -pi/2, i.e. straight up), where segment 0 (unviewed, bright)
        // is drawn.
        final brightPixel = pixelAt(size.width ~/ 2, 2);
        // Faded segment: bottom-center of the ring (angle +pi/2 from
        // center, i.e. straight down), well inside a later, faded
        // segment given 4 segments with ~0.12 rad gaps.
        final fadedPixel = pixelAt(size.width ~/ 2, size.height.toInt() - 3);

        expect(
          brightPixel.a,
          greaterThan(0),
          reason: 'sanity check: the bright-segment sample point must '
              'actually land on painted stroke, not the transparent gap '
              'between arcs',
        );
        expect(
          fadedPixel.a,
          greaterThan(0),
          reason: 'sanity check: the faded-segment sample point must '
              'actually land on painted stroke',
        );
        expect(
          fadedPixel.a,
          lessThan(brightPixel.a),
          reason:
              'a viewed (faded) segment must be painted with visibly '
              'lower alpha than an unviewed (bright) one — sampled from '
              'the actual rendered pixels, so this fails if the paint '
              'loop stops distinguishing them even though the painter\'s '
              'brightColor/fadedColor constructor fields are unchanged',
        );
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

    testWidgets(
      'a failedPermanent outbox record does not hide a real segmented '
      'ring behind a fake "posting" tile (review finding F2)',
      (tester) async {
        // flush() (story_outbox_controller.dart) skips failedPermanent
        // records but never removes them from the store, so a dead
        // record can sit in the list forever. The old code treated ANY
        // record for this relationship as "pending" and the pending
        // branch outranks hasStories — so 4 real, already-posted stories
        // plus 1 dead record used to render as a permanently-stuck
        // "posting" ring, hiding the real segmented arc across restarts.
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 4, unviewedCount: 4),
            ],
            outbox: [_pendingRecord(state: StoryOutboxState.failedPermanent)],
          ),
        );
        await tester.pumpAndSettle();

        final mine = _ringByKey(tester, 'story-ring-mine')!;
        expect(
          mine.pendingProgress,
          isNull,
          reason:
              'a failedPermanent record must never be treated as the '
              'pending item — it must not suppress the real ring',
        );
        expect(
          mine.hasStories,
          isTrue,
          reason: 'the 4 real stories must still show a segmented ring',
        );
        expect(mine.segmentCount, 4);
      },
    );

    testWidgets(
      'two queued captures: the ring reflects the NEWEST, not the first '
      'one in store order (review finding F5)',
      (tester) async {
        // StoryOutboxStore.readAll returns oldest-first
        // (story_outbox_backend_io.dart: `ORDER BY created_at ASC`). The
        // old code did `break` on the first match, i.e. the oldest.
        final older = _pendingRecord(
          state: StoryOutboxState.uploadingMedia,
          localThumbnailPath: '/tmp/OLD.jpg',
        );
        final newer = StoryOutboxRecord(
          clientStoryId: 'pending-2',
          relationshipId: _relationshipId,
          localMediaPath: '/tmp/does-not-exist-media-2.jpg',
          localThumbnailPath: '/tmp/NEW.jpg',
          mediaType: CapturedMediaType.image,
          mimeType: 'image/jpeg',
          width: 1080,
          height: 1920,
          utcOffsetMinutes: 0,
          state: StoryOutboxState.uploadingThumbnail,
          createdAt: DateTime.utc(2026, 9, 12, 9),
        );

        await tester.pumpWidget(
          await _harness(summary: const [], outbox: [older, newer]),
        );
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        final mine = _ringByKey(tester, 'story-ring-mine')!;
        expect(
          mine.localThumbnailPath,
          '/tmp/NEW.jpg',
          reason:
              'the ring must show the NEWEST queued capture\'s thumbnail '
              'and progress, not the oldest',
        );
        expect(mine.pendingProgress, closeTo(0.7, 0.0001));
      },
    );
  });

  group('unviewed count is clamped against a stale server aggregate '
      '(review finding F4)', () {
    testWidgets(
      'unviewedCount greater than activeCount does not crash the '
      'partner ring', (tester) async {
        // activeCount and unviewedCount are independently-computed
        // server aggregates (get_story_ring_summary) that can diverge —
        // a story expiring or being deleted between the two counts being
        // taken, or view-ledger lag. StoryRing's own constructor assert
        // is correct as a widget-contract invariant; this proves the
        // CALLER clamps before it ever reaches that assert, rather than
        // hard-crashing the widget on a server-side timing issue.
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 0, unviewedCount: 0),
              _summary(authorId: _partnerId, activeCount: 2, unviewedCount: 5),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final partner = _ringByKey(tester, 'story-ring-partner');
        expect(partner, isNotNull);
        expect(partner!.unviewedCount, lessThanOrEqualTo(partner.segmentCount));
      },
    );
  });

  group('the + badge has its own semantics node and a real tap target '
      '(review finding F3)', () {
    testWidgets(
      'my-with-stories ring: the + badge\'s semantics node has its OWN '
      'bounds, not the full 69dp ring\'s — proof it is a real boundary, '
      'not just a label',
      (tester) async {
        // Both labels being independently findable (via bySemanticsLabel)
        // is necessary but NOT sufficient — verified directly (via a
        // dumped semantics tree) that WITHOUT `_PlusBadge`'s own
        // `Semantics(container: true, ...)`, the + badge's actionable
        // semantics node still gets its OWN label, but its rect is the
        // full 69x69 ring, not its own ~48x48 hit box — i.e. a screen
        // reader is told the + occupies the entire ring's footprint,
        // which is the actual accessibility defect the review's finding
        // F3 describes (not a literal label-concatenation in this
        // Flutter version, but the same underlying "the badge doesn't
        // have its own boundary" bug, observable via node geometry).
        final handle = tester.ensureSemantics();

        var openMineCalls = 0;
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 2, unviewedCount: 2),
            ],
            onOpenMine: () => openMineCalls++,
          ),
        );
        await tester.pumpAndSettle();

        final ringLabel = find.bySemanticsLabel('Your story, 2 items');
        final plusLabel = find.bySemanticsLabel('Add to your story');
        expect(ringLabel, findsOneWidget);
        expect(plusLabel, findsOneWidget);

        final plusElement = plusLabel.evaluate().single;
        final plusRenderObject = plusElement.findRenderObject()!;
        final plusSemantics = plusRenderObject.debugSemantics!;
        expect(
          plusSemantics.rect.width,
          lessThan(60),
          reason:
              'the + badge\'s own semantics node must be scoped to its '
              'own hit area, not inherit the full ~69dp ring\'s bounds — '
              'that inheritance is what the review\'s finding F3 actually '
              'reported as a defect',
        );

        // Routing proof, mirroring the review's probe: tapping the RING
        // label (not the badge) must fire onOpenMine, never the capture
        // callback.
        await tester.tap(ringLabel);
        await tester.pumpAndSettle();
        expect(openMineCalls, 1);

        handle.dispose();
      },
    );

    testWidgets(
      'the + badge hit target is at least 44dp on a side on the '
      'mine-with-stories ring (the corner-badge case; mine-empty uses '
      'the same _PlusBadge widget with `centered: true`, sharing this '
      'code path)',
      (tester) async {
        final handle = tester.ensureSemantics();

        var captureCalls = 0;
        await tester.pumpWidget(
          await _harness(
            summary: [
              _summary(authorId: _myId, activeCount: 2, unviewedCount: 2),
            ],
            onCapture: () => captureCalls++,
          ),
        );
        await tester.pumpAndSettle();

        // The + badge's widget tree is Semantics(label: '+') -> a plain
        // GestureDetector -> the (larger) invisible hit box -> the small
        // visible circle. GestureDetector is a DESCENDANT of the
        // Semantics node here, not an ancestor.
        final plusSemanticsFinder = find.bySemanticsLabel('Add to your story');
        final gestureFinder = find
            .descendant(
              of: plusSemanticsFinder,
              matching: find.byType(GestureDetector),
            )
            .first;
        final plusGesture = tester.widget<GestureDetector>(gestureFinder);
        final renderBox = tester.renderObject(gestureFinder) as RenderBox;
        expect(plusGesture.onTap, isNotNull);
        expect(captureCalls, 0);
        plusGesture.onTap!();
        expect(
          captureCalls,
          1,
          reason: 'the resolved onTap must actually be the capture '
              'callback',
        );
        expect(
          renderBox.size.width,
          greaterThanOrEqualTo(44),
          reason: 'the + badge tap target must be at least 44dp wide — '
              'the visible circle itself is 20-28dp, well under that, so '
              'this must come from a larger invisible hit area',
        );
        expect(renderBox.size.height, greaterThanOrEqualTo(44));

        handle.dispose();
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
  final painter = _findSegmentedCustomPainter(tester, ringKey);
  if (painter == null) return null;
  final dynamic p = painter;
  return _TestPainterInfo(
    segmentCount: p.segmentCount as int,
    unviewedCount: p.unviewedCount as int,
    solid: p.solid as bool,
    brightColor: p.brightColor as Color,
    fadedColor: p.fadedColor as Color,
  );
}

/// Returns the actual `_SegmentedRingPainter` instance (not a copied-out
/// DTO), for tests that need to invoke its `paint()` directly — e.g. to
/// sample the pixels it actually draws, rather than trusting that the
/// constructor's `brightColor`/`fadedColor` fields are what ends up on
/// the canvas for a given segment (they are inputs to the painter, not
/// proof of what the paint LOOP does with them per-segment).
CustomPainter? _findSegmentedCustomPainter(
  WidgetTester tester,
  String ringKey,
) {
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
      return painter;
    }
  }
  return null;
}

class _TestPainterInfo {
  _TestPainterInfo({
    required this.segmentCount,
    required this.unviewedCount,
    required this.solid,
    required this.brightColor,
    required this.fadedColor,
  });

  final int segmentCount;
  final int unviewedCount;
  final bool solid;
  final Color brightColor;
  final Color fadedColor;
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
