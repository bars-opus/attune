// E (03 M4, 04 #6, 06 #16, 05 #6) + L5: ring and calendar thumbnails are
// cached under their storage key (a re-signed URL never re-downloads),
// fall back to the copy already on disk when signing fails, and decode at
// the size they are shown.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

const _key = 'story-media/partner-1-thumb.jpg';
final _day = DateTime(2026, 6, 15);

Widget _calendarHost(RingGateway gateway, Widget child) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(ringUser),
    storyReadGatewayProvider.overrideWithValue(gateway),
    chatImageCacheProvider.overrideWithValue(NoopImageCache()),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  tearDown(() => debugStoryCachedThumbnail = storyCachedThumbnailOnDisk);

  testWidgets(
    'the partner ring keys its image by storage key, at display size',
    (tester) async {
      await pumpRings(tester, RingGateway(summary: [ringRow(key: _key)]));
      final image = tester.widget<CachedNetworkImage>(
        find.descendant(
          of: find.byKey(const ValueKey('story-ring-partner')),
          matching: find.byType(CachedNetworkImage),
        ),
      );
      expect(image.cacheKey, _key);
      expect(image.useOldImageOnUrlChange, isTrue);
      expect(
        image.memCacheWidth,
        storyThumbnailDecodeWidth(
          kStoryRingThumbnailDiameter,
          tester.view.devicePixelRatio,
        ),
      );
    },
  );

  testWidgets('when signing fails, the ring shows the copy already on disk', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ring-thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/t.jpg')..writeAsBytesSync([0]);
    debugStoryCachedThumbnail = (key) async => key == _key ? file : null;
    final gateway = RingGateway(summary: [ringRow(key: _key)])
      ..urls[_key] = null;
    await pumpRings(tester, gateway);
    await tester.pump();
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('story-ring-partner')),
        matching: find.byType(Image),
      ),
    );
    final provider = image.image as ResizeImage;
    expect((provider.imageProvider as FileImage).file.path, file.path);
  });

  testWidgets('a calendar date avatar keys its image by storage key', (
    tester,
  ) async {
    final gateway =
        RingGateway()
          ..dayCounts = [
            StoryDayCount(
              occurredOn: _day,
              itemCount: 1,
              authorId: ringPartner,
              newestThumbnailKey: _key,
              newestCreatedAt: _day,
            ),
          ];
    await tester.pumpWidget(
      _calendarHost(
        gateway,
        CalendarDayIndicators(
          relationshipId: ringRel,
          date: _day,
          eventTypes: const [],
          reminderTypes: const [],
          hasUpcoming: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, _key);
    expect(
      image.memCacheWidth,
      storyThumbnailDecodeWidth(
        kCalendarStoryAvatarDiameter,
        tester.view.devicePixelRatio,
      ),
    );
  });

  testWidgets("a day sheet ring keys its image by the newest story's key", (
    tester,
  ) async {
    final gateway =
        RingGateway()
          ..dayItems = [
            StoryItem(
              id: 's1',
              clientStoryId: 'c1',
              relationshipId: ringRel,
              authorId: ringPartner,
              mediaType: 'image',
              mediaKey: 'story-media/s1.jpg',
              thumbnailKey: _key,
              mediaWidth: 1080,
              mediaHeight: 1920,
              occurredOn: _day,
              createdAt: _day,
              expiresAt: _day.add(const Duration(hours: 24)),
              hasBeenViewed: false,
            ),
          ];
    await tester.pumpWidget(
      _calendarHost(
        gateway,
        CalendarDaySheet(
          relationshipId: ringRel,
          date: _day,
          events: const [],
          reminders: const [],
          planningEntries: const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, _key);
  });
  // Fix round 1, review #1: BoxFit.cover fills the circle from the short
  // edge, so a landscape thumbnail must decode at least the circle's pixel
  // size on its SHORT edge, not only on its width.
  testWidgets(
    'a landscape thumbnail decodes sharp: its short edge covers the circle '
    '(batch-2 review #1)',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('ring-thumb-wide');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/wide.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 400, 225),
          Paint()..color = const Color(0xFF3366CC),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 225);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        file.writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
      debugStoryCachedThumbnail = (key) async => key == _key ? file : null;
      final gateway = RingGateway(summary: [ringRow(key: _key)])
        ..urls[_key] = null;
      final ring = find.byKey(const ValueKey('story-ring-partner'));
      final raw = find.descendant(of: ring, matching: find.byType(RawImage));
      ui.Image? decoded() =>
          raw.evaluate().isEmpty ? null : tester.widget<RawImage>(raw).image;
      // Real time: the file read and the decode are real I/O.
      await tester.runAsync(() async {
        await pumpRings(tester, gateway);
        for (var i = 0; i < 40 && decoded() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      final image = decoded();
      expect(image, isNotNull);
      expect(
        image!.height,
        greaterThanOrEqualTo((kStoryRingThumbnailDiameter * 3).round()),
      );
    },
  );

  // Fix round 1, review #4: on a cold start the copy on disk paints first;
  // when the signed URL lands, that copy stays up (as the network image's
  // placeholder) instead of blinking to the neutral fill. The fade itself
  // is a device check.
  testWidgets(
    'when the URL lands after the disk copy painted, the disk copy stays '
    'until the network image is ready (batch-2 review #4)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('ring-thumb-cold');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/t.jpg')..writeAsBytesSync([0]);
      debugStoryCachedThumbnail = (key) async => key == _key ? file : null;
      final gateway = _GatedSignGateway(summary: [ringRow(key: _key)]);
      await pumpRings(tester, gateway);
      await tester.pump();
      final ring = find.byKey(const ValueKey('story-ring-partner'));
      bool showsDiskCopy() =>
          find
              .descendant(
                of: ring,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Image &&
                      w.image is ResizeImage &&
                      (w.image as ResizeImage).imageProvider is FileImage,
                ),
              )
              .evaluate()
              .isNotEmpty;
      expect(showsDiskCopy(), isTrue, reason: 'cold start: disk copy first');
      gateway.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(of: ring, matching: find.byType(CachedNetworkImage)),
        findsOneWidget,
      );
      expect(
        showsDiskCopy(),
        isTrue,
        reason: 'the disk copy stays up while the network image loads',
      );
    },
  );
}

class _GatedSignGateway extends RingGateway {
  _GatedSignGateway({super.summary});
  final gate = Completer<void>();

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    await gate.future;
    return super.signMediaUrl(storageKey);
  }
}
