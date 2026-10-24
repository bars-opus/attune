// E + M5 (03 M4/M5, 04 #6, 07a E): one signed URL per storage key, reused
// for 540 s in memory and shared by the rings and the calendar; a failed
// signing retries on a backoff, only while Attune is on screen.
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

void main() {
  group('StorySignedUrlCache', () {
    test('a URL is reused for 540 s, then forgotten', () {
      var now = DateTime.utc(2026, 10, 24, 9);
      withClock(Clock(() => now), () {
        final cache = StorySignedUrlCache();
        cache.put('k', 'u1');
        now = now.add(const Duration(seconds: 539));
        expect(cache.fresh('k'), 'u1');
        now = now.add(const Duration(seconds: 1));
        expect(cache.fresh('k'), isNull);
        cache.dispose();
      });
    });

    test('a URL is never reused when the clock is set back (review #2)', () {
      var now = DateTime.utc(2026, 10, 24, 9);
      withClock(Clock(() => now), () {
        final cache = StorySignedUrlCache()..put('k', 'u1');
        now = now.subtract(const Duration(hours: 1));
        expect(cache.fresh('k'), isNull);
        cache.dispose();
      });
    });

    test('age counts from when the request started (review #2)', () {
      var now = DateTime.utc(2026, 10, 24, 9);
      withClock(Clock(() => now), () {
        final startedAt = now;
        now = now.add(const Duration(seconds: 100));
        final cache =
            StorySignedUrlCache()..put('k', 'u1', mintedAt: startedAt);
        now = startedAt.add(const Duration(seconds: 539));
        expect(cache.fresh('k'), 'u1');
        now = startedAt.add(kStoryUrlReuseWindow);
        expect(cache.fresh('k'), isNull);
        expect(storyUrlFreshFor(startedAt), isNull);
        cache.dispose();
      });
    });

    test('evict and clearEveryLiveCache forget URLs', () {
      final a =
          StorySignedUrlCache()
            ..put('k1', 'u1')
            ..put('k2', 'u2');
      final b = StorySignedUrlCache()..put('k3', 'u3');
      a.evict(['k1']);
      expect(a.fresh('k1'), isNull);
      expect(a.fresh('k2'), 'u2');
      StorySignedUrlCache.clearEveryLiveCache();
      expect(a.fresh('k2'), isNull);
      expect(b.fresh('k3'), isNull);
      a.dispose();
      b.dispose();
    });
  });

  group('storyMediaSignedUrlProvider', () {
    testWidgets('a key read twice within 540 s is signed once', (tester) async {
      final gateway = RingGateway();
      final c = ringContainer(gateway);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump(Duration.zero);
      c.invalidate(storyMediaSignedUrlProvider('k'));
      await tester.pump(Duration.zero);
      expect(gateway.signCalls, ['k']);
      expect(
        c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
        'https://signed.example/k',
      );
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets(
      'a slow signing reply does not stretch the reuse window (review #2)',
      (tester) async {
        final gateway = _SlowSignGateway();
        final c = ringContainer(gateway);
        final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
        await tester.pump(const Duration(seconds: 100));
        await tester.pump(Duration.zero);
        expect(gateway.started, 1);
        expect(
          c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
          'https://signed.example/k',
        );
        // 540 s after the request STARTED (it landed at 100 s), the mounted
        // key is already being signed again.
        await tester.pump(const Duration(seconds: 440));
        await tester.pump(Duration.zero);
        expect(gateway.started, 2);
        sub.close();
        await tester.pump(const Duration(seconds: 100));
        c.dispose();
      },
    );

    testWidgets(
      'a mounted key is re-signed when its URL is 540 s old, before the '
      '600 s TTL, and a reused URL keeps its own age (review #3)',
      (tester) async {
        final gateway = RingGateway();
        final c = ringContainer(gateway);
        var sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
        await tester.pump(Duration.zero);
        expect(gateway.signCalls, ['k']);
        // Unmounted at 300 s, remounted: the reused URL is 300 s old.
        await tester.pump(const Duration(seconds: 300));
        sub.close();
        await tester.pump(Duration.zero);
        sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
        await tester.pump(Duration.zero);
        expect(gateway.signCalls, ['k']);
        await tester.pump(const Duration(seconds: 239));
        expect(gateway.signCalls, ['k']);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(Duration.zero);
        expect(gateway.signCalls, ['k', 'k']);
        expect(
          c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
          'https://signed.example/k',
        );
        sub.close();
        await tester.pump(Duration.zero);
        c.dispose();
      },
    );

    testWidgets('a re-sign due while Attune is hidden waits for its return', (
      tester,
    ) async {
      final gateway = RingGateway();
      final c = ringContainer(gateway);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump(Duration.zero);
      visibilityOf(c).set(false);
      await tester.pump(const Duration(seconds: 600));
      expect(gateway.signCalls, ['k']);
      visibilityOf(c).set(true);
      await tester.pump(Duration.zero);
      expect(gateway.signCalls, ['k', 'k']);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets(
      'a key whose signing fails is retried on a backoff, then left alone '
      '(Review Focus 5)',
      (tester) async {
        final gateway = RingGateway()..urls['k'] = null;
        final c = ringContainer(gateway);
        final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
        await tester.pump(Duration.zero);
        expect(gateway.signCalls.length, 1);
        expect(c.read(storyMediaSignedUrlProvider('k')).hasError, isTrue);
        for (final seconds in [2, 4, 8, 16]) {
          await tester.pump(Duration(seconds: seconds));
          await tester.pump(Duration.zero);
        }
        expect(gateway.signCalls.length, 1 + kStorySignMaxAutoRetries);
        await tester.pump(const Duration(minutes: 10));
        expect(gateway.signCalls.length, 1 + kStorySignMaxAutoRetries);
        sub.close();
        await tester.pump(Duration.zero);
        c.dispose();
      },
    );

    testWidgets('a retry due while Attune is hidden waits until it is back', (
      tester,
    ) async {
      final gateway = RingGateway()..urls['k'] = null;
      final c = ringContainer(gateway);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump(Duration.zero);
      visibilityOf(c).set(false);
      gateway.urls['k'] = 'https://signed.example/k2';
      await tester.pump(const Duration(seconds: 3));
      expect(gateway.signCalls.length, 1);
      visibilityOf(c).set(true);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(gateway.signCalls.length, 2);
      expect(
        c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
        'https://signed.example/k2',
      );
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets('evicting a key signs it afresh and removes its bytes', (
      tester,
    ) async {
      final gateway = RingGateway();
      final images = NoopImageCache();
      final c = ringContainer(gateway, images: images);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump(Duration.zero);
      await c.read(storyMediaEvictorProvider).evict(['k', '']);
      c.invalidate(storyMediaSignedUrlProvider('k'));
      await tester.pump(Duration.zero);
      expect(gateway.signCalls, ['k', 'k']);
      expect(images.removed, ['k']);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    // Final review M-3: one clock read per reuse decision.
    testWidgets('a URL turning 540 s old between two clock reads is not an '
        'error (final review M-3)', (tester) async {
      final t0 = DateTime.utc(2026, 10, 24, 9);
      var ticking = false;
      var reads = 0;
      DateTime now() => ticking
          ? t0.add(
              Duration(seconds: 539, milliseconds: 999 + reads++),
            )
          : t0;
      await withClock(Clock(now), () async {
        final gateway = RingGateway();
        final c = ringContainer(gateway);
        c
            .read(storySignedUrlCacheProvider)
            .put('k', 'https://signed.example/old', mintedAt: t0);
        ticking = true;
        final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
        await tester.pump(Duration.zero);
        final value = c.read(storyMediaSignedUrlProvider('k'));
        expect(value.hasError, isFalse);
        expect(value.valueOrNull, 'https://signed.example/old');
        expect(gateway.signCalls, isEmpty);
        sub.close();
        await tester.pump(Duration.zero);
        c.dispose();
      });
    });
  });

  // Final review I-1: a thumbnail whose signing ran out of retries is not
  // grey for the rest of the session.
  group('a key out of retries recovers (final review I-1)', () {
    Future<void> exhaust(WidgetTester tester) async {
      for (final seconds in [2, 4, 8, 16]) {
        await tester.pump(Duration(seconds: seconds));
        await tester.pump(Duration.zero);
      }
    }

    int signsOf(RingGateway gateway, String key) =>
        gateway.signCalls.where((k) => k == key).length;

    StoryRing partnerRing(WidgetTester tester) => tester.widget<StoryRing>(
      find.byKey(const ValueKey('story-ring-partner')),
    );

    testWidgets('a good ring re-read naming it signs it again, and the '
        'partner ring gets its URL', (tester) async {
      const key = 'story-media/partner-thumb.jpg';
      final gateway = RingGateway(summary: [ringRow(key: key)])
        ..urls[key] = null;
      await pumpRings(tester, gateway);
      await exhaust(tester);
      expect(signsOf(gateway, key), 1 + kStorySignMaxAutoRetries);
      await tester.pump(const Duration(minutes: 5));
      expect(signsOf(gateway, key), 1 + kStorySignMaxAutoRetries);

      gateway.urls.remove(key);
      gateway.emitSignal();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(gateway.summaryCalls, 2);
      expect(signsOf(gateway, key), 2 + kStorySignMaxAutoRetries);
      expect(partnerRing(tester).thumbnailUrl, 'https://signed.example/$key');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it signs once more each time Attune comes back on screen', (
      tester,
    ) async {
      final gateway = RingGateway()..urls['k'] = null;
      final c = ringContainer(gateway);
      final sub = c.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
      await tester.pump(Duration.zero);
      await exhaust(tester);
      expect(gateway.signCalls.length, 1 + kStorySignMaxAutoRetries);

      visibilityOf(c).set(false);
      await tester.pump(Duration.zero);
      visibilityOf(c).set(true);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(gateway.signCalls.length, 2 + kStorySignMaxAutoRetries);
      // Still failing: one attempt per return, no new backoff run.
      await tester.pump(const Duration(minutes: 5));
      expect(gateway.signCalls.length, 2 + kStorySignMaxAutoRetries);

      gateway.urls.remove('k');
      visibilityOf(c).set(false);
      await tester.pump(Duration.zero);
      visibilityOf(c).set(true);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(gateway.signCalls.length, 3 + kStorySignMaxAutoRetries);
      expect(
        c.read(storyMediaSignedUrlProvider('k')).valueOrNull,
        'https://signed.example/k',
      );
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets('Retry on the rings notice signs the ring keys again', (
      tester,
    ) async {
      const key = 'story-media/partner-thumb.jpg';
      final gateway = RingGateway()
        ..summaryError = StateError('offline')
        ..urls[key] = null;
      await pumpRings(
        tester,
        gateway,
        lastKnown: MemoryStoryRingLastKnownStore()
          ..value = StoryRingSnapshot(
            userId: ringMe,
            relationshipId: ringRel,
            savedAt: clock.now().subtract(const Duration(minutes: 5)),
            rows: [ringRow(key: key)],
          ),
      );
      await tester.pump();
      await exhaust(tester);
      expect(signsOf(gateway, key), 1 + kStorySignMaxAutoRetries);

      gateway.urls.remove(key);
      await tester.tap(find.text('Retry'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(signsOf(gateway, key), 2 + kStorySignMaxAutoRetries);
      expect(partnerRing(tester).thumbnailUrl, 'https://signed.example/$key');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a good month re-read signs a calendar avatar key again', (
      tester,
    ) async {
      const key = 'story-media/day-thumb.jpg';
      final day = DateTime(2026, 10, 3);
      final gateway = RingGateway()
        ..urls[key] = null
        ..dayCounts = [
          StoryDayCount(
            occurredOn: day,
            itemCount: 1,
            authorId: ringPartner,
            newestThumbnailKey: key,
            newestCreatedAt: day,
          ),
        ];
      final c = ringContainer(gateway);
      final month = StoryDayRangeKey.month(relationshipId: ringRel, day: day);
      final counts = c.listen(storyDayCountsProvider(month), (_, __) {});
      final url = c.listen(storyMediaSignedUrlProvider(key), (_, __) {});
      await tester.pump(Duration.zero);
      await exhaust(tester);
      expect(signsOf(gateway, key), 1 + kStorySignMaxAutoRetries);

      gateway.urls.remove(key);
      gateway.emitSignal();
      for (var i = 0; i < 4; i++) {
        await tester.pump(Duration.zero);
      }
      expect(gateway.dayCountCalls, 2);
      expect(signsOf(gateway, key), 2 + kStorySignMaxAutoRetries);
      expect(
        c.read(storyMediaSignedUrlProvider(key)).valueOrNull,
        'https://signed.example/$key',
      );
      counts.close();
      url.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });
  });
}

/// Signing takes 100 s, as a reply on a bad network can.
class _SlowSignGateway extends RingGateway {
  int started = 0;

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    started++;
    await Future<void>.delayed(const Duration(seconds: 100));
    return super.signMediaUrl(storageKey);
  }
}
