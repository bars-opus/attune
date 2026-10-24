// 03 M1: between finalize and the next ring summary, my ring keeps showing
// the story I just posted instead of flashing back to `+`. 03 L1: tapping
// a ring whose only story is still posting says so instead of opening an
// empty reel.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/outbox_fakes.dart';
import 'support/ring_test_kit.dart';

void main() {
  test('a story that posts leaves a hold carrying its thumbnail', () async {
    final dir = await Directory.systemTemp.createTemp('hold');
    addTearDown(() => dir.delete(recursive: true));
    final h = outboxHarness();
    addTearDown(h.container.dispose);
    await h.store.put(outboxUserId, outboxRecord(dir));
    await forceOnce(h);
    final hold = h.container.read(storyPostedHoldsProvider).single;
    expect(hold.clientStoryId, 'cid-1');
    expect(hold.relationshipId, 'rel-1');
    expect(hold.thumbnailBytes, [4, 5]);
  });

  testWidgets(
    'a hold is released only by a read issued after it, or by the cap',
    (tester) async {
      final holds = StoryPostedHolds();
      final heldAt = clock.now();
      holds.hold(
        StoryPostedHold(
          relationshipId: 'r',
          clientStoryId: 'c',
          heldAt: heldAt,
        ),
      );
      holds.releaseFetchedSince(
        'r',
        heldAt.subtract(const Duration(seconds: 1)),
      );
      expect(holds.state, hasLength(1));
      holds.releaseFetchedSince('other', heldAt);
      expect(holds.state, hasLength(1));
      holds.releaseFetchedSince('r', heldAt);
      expect(holds.state, isEmpty);
      holds.hold(
        StoryPostedHold(
          relationshipId: 'r',
          clientStoryId: 'd',
          heldAt: clock.now(),
        ),
      );
      await tester.pump(kStoryPostedHoldCap);
      expect(holds.state, isEmpty);
      holds.dispose();
    },
  );

  testWidgets('my ring keeps the posted story until the summary has it', (
    tester,
  ) async {
    final gateway = RingGateway();
    final holds = StoryPostedHolds();
    await pumpRings(
      tester,
      gateway,
      overrides: [storyPostedHoldsProvider.overrideWith((_) => holds)],
    );
    holds.hold(
      StoryPostedHold(
        relationshipId: ringRel,
        clientStoryId: 'c1',
        heldAt: clock.now(),
        thumbnailBytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await tester.pump();
    expect(mineRing(tester).hasStories, isTrue);
    expect(mineRing(tester).segmentCount, 1);
    expect(mineRing(tester).localThumbnailBytes, isNotNull);

    gateway.summary = [ringRow(author: ringMe, active: 1, unviewed: 0)];
    gateway.emitSignal();
    await tester.pump();
    await tester.pump();
    expect(holds.state, isEmpty);
    expect(mineRing(tester).segmentCount, 1);
    // The newest key signs once the summary's ring is up.
    await tester.pump();
    expect(mineRing(tester).thumbnailUrl, isNotNull);
  });

  testWidgets('tapping a ring that is only posting says so (03 L1)', (
    tester,
  ) async {
    var opened = 0;
    await pumpRings(
      tester,
      RingGateway(),
      onOpenMine: () => opened++,
      outbox: [
        StoryOutboxRecord(
          clientStoryId: 'p1',
          relationshipId: ringRel,
          localMediaPath: '/tmp/none-media.jpg',
          localThumbnailPath: '',
          mediaType: CapturedMediaType.image,
          mimeType: 'image/jpeg',
          width: 1080,
          height: 1920,
          utcOffsetMinutes: 0,
          state: StoryOutboxState.uploadingMedia,
          createdAt: DateTime.utc(2026, 10, 24, 8),
        ),
      ],
    );
    await tester.pump();
    final corner = tester.getTopLeft(
      find.byKey(const ValueKey('story-ring-mine')),
    );
    await tester.tapAt(corner + const Offset(34.5, 34.5));
    await tester.pump();
    expect(opened, 0);
    expect(
      find.text("Still posting. It'll be here in a moment."),
      findsOneWidget,
    );
  });

  // Batch-4 review nit 7: a story already posted (held) is there to open,
  // even while the next one is still posting.
  testWidgets('a held story opens while the next one posts', (tester) async {
    var opened = 0;
    final holds = StoryPostedHolds();
    await pumpRings(
      tester,
      RingGateway(),
      onOpenMine: () => opened++,
      overrides: [storyPostedHoldsProvider.overrideWith((_) => holds)],
      outbox: [
        StoryOutboxRecord(
          clientStoryId: 'p2',
          relationshipId: ringRel,
          localMediaPath: '/tmp/none-media.jpg',
          localThumbnailPath: '',
          mediaType: CapturedMediaType.image,
          mimeType: 'image/jpeg',
          width: 1080,
          height: 1920,
          utcOffsetMinutes: 0,
          state: StoryOutboxState.uploadingMedia,
          createdAt: DateTime.utc(2026, 10, 24, 8),
        ),
      ],
    );
    holds.hold(
      StoryPostedHold(
        relationshipId: ringRel,
        clientStoryId: 'p1',
        heldAt: clock.now(),
      ),
    );
    await tester.pump();
    final corner = tester.getTopLeft(
      find.byKey(const ValueKey('story-ring-mine')),
    );
    await tester.tapAt(corner + const Offset(34.5, 34.5));
    await tester.pump();
    expect(opened, 1);
    expect(
      find.text("Still posting. It'll be here in a moment."),
      findsNothing,
    );
    await tester.pump(kStoryPostedHoldCap); // the cap timer runs out
  });

  // Batch-4 review nit 6: a hold whose bytes could not be read keeps the
  // previous story's photo rather than going grey.
  testWidgets('a hold without bytes keeps the previous photo', (tester) async {
    final holds = StoryPostedHolds();
    await pumpRings(
      tester,
      RingGateway(
        summary: [ringRow(author: ringMe, key: 'k-old', unviewed: 0)],
      ),
      overrides: [storyPostedHoldsProvider.overrideWith((_) => holds)],
    );
    holds.hold(
      StoryPostedHold(
        relationshipId: ringRel,
        clientStoryId: 'c1',
        heldAt: clock.now(),
      ),
    );
    await tester.pump();
    expect(mineRing(tester).segmentCount, 2);
    expect(mineRing(tester).thumbnailCacheKey, 'k-old');
    await tester.pump(kStoryPostedHoldCap); // the cap timer runs out
  });

  // Batch-4 review #1: the read that releases the hold switches my ring to
  // the summary's key, which the disk cache did not have yet; the photo
  // blinked to grey until signing and the download finished.
  test(
    'a story that posts seeds its thumbnail under its storage key',
    () async {
      final dir = await Directory.systemTemp.createTemp('hold');
      addTearDown(() => dir.delete(recursive: true));
      final seeded = <String, List<int>>{};
      final h = outboxHarness(
        extra: [
          storyThumbnailSeederProvider.overrideWithValue(
            (key, bytes) async => seeded[key] = bytes,
          ),
        ],
      );
      addTearDown(h.container.dispose);
      await h.store.put(outboxUserId, outboxRecord(dir));
      await forceOnce(h);
      final hold = h.container.read(storyPostedHoldsProvider).single;
      expect(hold.thumbnailStorageKey, startsWith('key-thumbnail-'));
      expect(seeded, {
        hold.thumbnailStorageKey: [4, 5],
      });
    },
  );

  testWidgets('a released hold keeps the photo until the disk copy is found', (
    tester,
  ) async {
    debugStoryCachedThumbnail = (_) => Completer<File?>().future;
    addTearDown(() => debugStoryCachedThumbnail = storyCachedThumbnailOnDisk);
    final gateway = _SlowSigning();
    final holds = StoryPostedHolds();
    await pumpRings(
      tester,
      gateway,
      overrides: [storyPostedHoldsProvider.overrideWith((_) => holds)],
    );
    holds.hold(
      StoryPostedHold(
        relationshipId: ringRel,
        clientStoryId: 'c1',
        heldAt: clock.now(),
        thumbnailBytes: Uint8List.fromList(_png),
        thumbnailStorageKey: 'k-new',
      ),
    );
    await tester.pump();
    gateway.summary = [ringRow(author: ringMe, key: 'k-new', unviewed: 0)];
    gateway.emitSignal();
    await tester.pump();
    await tester.pump();
    expect(holds.state, isEmpty);
    // The frame after the release: the summary's ring, on key k-new.
    await tester.pump();
    expect(mineRing(tester).thumbnailCacheKey, 'k-new');
    final mine = find.byKey(const ValueKey('story-ring-mine'));
    expect(
      find.descendant(of: mine, matching: find.byType(Image)),
      findsOneWidget,
    );
    final neutral =
        Theme.of(tester.element(mine)).colorScheme.surfaceContainerHighest;
    expect(
      find.descendant(
        of: mine,
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == neutral,
        ),
      ),
      findsNothing,
    );
  });
}

/// Signing never answers: the ring has only the disk and the hold.
class _SlowSigning extends RingGateway {
  @override
  Future<String?> signMediaUrl(String storageKey) =>
      Completer<String?>().future;
}

/// A 1x1 PNG.
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
