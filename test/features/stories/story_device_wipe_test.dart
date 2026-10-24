// 05 #6: story thumbnails, signed URLs and the last-known rings leave the
// phone on sign-out, account switch, quick exit and a relationship's pause,
// end or archive.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:attune/features/stories/presentation/state/story_ring_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ring_test_kit.dart';

final _refProvider = Provider<Ref>((ref) => ref);

class _ThrowingImages implements ChatImageCache {
  @override
  Future<void> clear() async => throw StateError('store gone');
  @override
  Future<void> removeKeys(Iterable<String> keys) async {}
}

void main() {
  test(
    'clearing forgets URLs, empties the image cache and the snapshot',
    () async {
      final urls = StorySignedUrlCache()..put('k', 'u');
      addTearDown(urls.dispose);
      final images = NoopImageCache();
      final lastKnown =
          MemoryStoryRingLastKnownStore()
            ..value = StoryRingSnapshot(
              userId: ringMe,
              relationshipId: ringRel,
              savedAt: DateTime.now(),
              rows: const [],
            );
      await clearStoryDeviceCaches(images: images, lastKnown: lastKnown);
      expect(urls.fresh('k'), isNull);
      expect(images.clears, 1);
      expect(lastKnown.value, isNull);
    },
  );

  test('without images, and a failing image step skips nothing', () async {
    final images = NoopImageCache();
    final lastKnown =
        MemoryStoryRingLastKnownStore()
          ..value = StoryRingSnapshot(
            userId: ringMe,
            relationshipId: ringRel,
            savedAt: DateTime.now(),
            rows: const [],
          );
    await clearStoryDeviceCaches(
      includeImages: false,
      images: images,
      lastKnown: lastKnown,
    );
    expect(images.clears, 0);
    expect(lastKnown.value, isNull);
    lastKnown.value = StoryRingSnapshot(
      userId: ringMe,
      relationshipId: ringRel,
      savedAt: DateTime.now(),
      rows: const [],
    );
    await clearStoryDeviceCaches(
      images: _ThrowingImages(),
      lastKnown: lastKnown,
    );
    expect(lastKnown.value, isNull);
  });

  test('sign-out and account switch run the cache step', () async {
    final dir = await Directory.systemTemp.createTemp('wipe');
    addTearDown(() => dir.delete(recursive: true));
    var clears = 0;
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyOutboxStoreProvider.overrideWithValue(
          StoryOutboxStore.forTesting(stub.createStoryOutboxBackend()),
        ),
        storyMediaVaultProvider.overrideWithValue(
          StoryMediaVault(supportDirectory: () async => dir),
        ),
      ],
    );
    addTearDown(container.dispose);
    final wiper = StoryOutboxWiper(
      container.read(_refProvider),
      clearCaches: () async => clears++,
    );
    await wiper.wipeAll();
    await wiper.wipeExcept(ringMe);
    expect(clears, 2);
  });

  testWidgets('quick exit clears the story caches', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    var cleared = 0;
    QuickExitService.clearStories = () async => cleared++;
    QuickExitService.exitOverride = () async {};
    addTearDown(() {
      QuickExitService.clearStories = clearStoryDeviceCaches;
      QuickExitService.exitOverride = null;
    });
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
        GoRoute(
          path: '/neutralScreen',
          name: 'neutralScreen',
          builder: (_, __) => const Text('DECOY'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.runAsync(() async {
      final exiting = QuickExitService.executeWithRouter(router);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cleared, 1);
      await exiting;
    });
    await tester.pumpAndSettle();
    // Review #2: once more after the 300 ms wait, when the old screen is
    // gone, for anything it saved or downloaded meanwhile.
    expect(cleared, 2);
  });

  // Review #3: the real default, end to end.
  testWidgets('quick exit runs the real story wipe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      SecureStoryRingLastKnownStore.storageKey: '{}',
    });
    QuickExitService.exitOverride = () async {};
    addTearDown(() => QuickExitService.exitOverride = null);
    final urls = StorySignedUrlCache()..put('k', 'u');
    addTearDown(urls.dispose);
    final decoded = PaintingBinding.instance.imageCache;
    decoded.putIfAbsent(
      'story-thumb',
      () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
    );
    final epoch = SecureStoryRingLastKnownStore().epoch;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
        GoRoute(
          path: '/neutralScreen',
          name: 'neutralScreen',
          builder: (_, __) => const Text('DECOY'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.runAsync(() async {
      await QuickExitService.executeWithRouter(router);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    final keychain = await tester.runAsync(
      () => const FlutterSecureStorage().read(
        key: SecureStoryRingLastKnownStore.storageKey,
      ),
    );
    expect(keychain, isNull);
    expect(SecureStoryRingLastKnownStore().epoch, greaterThan(epoch));
    expect(urls.fresh('k'), isNull);
    expect(decoded.pendingImageCount, 0);
  });

  // Review #3: the provider the lifecycle watcher really calls.
  testWidgets("a relationship's change clears the live story state", (
    tester,
  ) async {
    final lastKnown =
        MemoryStoryRingLastKnownStore()..value = _snapshot(ringMe);
    final images = NoopImageCache();
    final container = ringContainer(
      RingGateway(),
      images: images,
      lastKnown: lastKnown,
    );
    final urls = container.read(storySignedUrlCacheProvider)..put('k', 'u');
    await tester.runAsync(
      () => container.read(lifecycleClearSurfacesProvider)(),
    );
    expect(lastKnown.value, isNull);
    expect(images.clears, 1);
    expect(urls.fresh('k'), isNull);
    container.dispose();
  });

  // Batch-5 fix round 1 carry: the month counts' memo (past-day thumbnail
  // keys) is forgotten with the rest of the live story state.
  testWidgets("a relationship's change forgets the month counts' memo", (
    tester,
  ) async {
    final container = ringContainer(RingGateway());
    final memo = container.read(storyDayCountsMemoProvider);
    memo[StoryDayRangeKey.month(
      relationshipId: ringRel,
      day: DateTime(2026, 6, 1),
    )] = [
      StoryDayCount(
        occurredOn: DateTime(2026, 6, 3),
        itemCount: 1,
        authorId: ringPartner,
        newestThumbnailKey: 'k',
      ),
    ];
    await tester.runAsync(
      () => container.read(lifecycleClearSurfacesProvider)(),
    );
    expect(container.read(storyDayCountsMemoProvider), isEmpty);
    container.dispose();
  });

  // Final review M-2: nothing still on screen keeps a URL (or a ring or a
  // month) from before the wipe, so nothing downloads a wiped thumbnail.
  testWidgets("a relationship's change re-reads the mounted rings, URLs and "
      'month counts', (tester) async {
    final gateway = RingGateway(summary: [ringRow(key: 'k')]);
    final container = ringContainer(gateway);
    final month = StoryDayRangeKey.month(
      relationshipId: ringRel,
      day: DateTime(2026, 10, 1),
    );
    final url = container.listen(storyMediaSignedUrlProvider('k'), (_, __) {});
    final rings = container.listen(
      storyRingSummaryProvider(ringRel),
      (_, __) {},
    );
    final counts = container.listen(
      storyDayCountsProvider(month),
      (_, __) {},
    );
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(gateway.signCalls, ['k']);
    expect(gateway.summaryCalls, 1);
    expect(gateway.dayCountCalls, 1);
    // The relationship closed: the server signs nothing for it now.
    gateway.urls['k'] = null;

    await tester.runAsync(
      () => container.read(lifecycleClearSurfacesProvider)(),
    );
    expect(
      container.read(storyMediaSignedUrlProvider('k')).valueOrNull,
      isNull,
    );
    // The re-reads were scheduled inside runAsync's real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(gateway.signCalls, ['k', 'k']);
    expect(gateway.summaryCalls, 2);
    expect(gateway.dayCountCalls, 2);
    expect(
      container.read(storyMediaSignedUrlProvider('k')).valueOrNull,
      isNull,
    );
    url.close();
    rings.close();
    counts.close();
    await tester.pump(Duration.zero);
    container.dispose();
  });

  // Review #2: sign-out wipes before the session ends; a ring read in that
  // window must not write this account's rings back.
  testWidgets('after a sign-out wipe, no snapshot is saved until a sign-in', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('wipe'),
    );
    addTearDown(() => dir!.delete(recursive: true));
    final lastKnown = MemoryStoryRingLastKnownStore();
    final gateway = RingGateway(summary: [ringRow()]);
    final c = ringContainer(
      gateway,
      lastKnown: lastKnown,
      overrides: [
        storyOutboxStoreProvider.overrideWithValue(
          StoryOutboxStore.forTesting(stub.createStoryOutboxBackend()),
        ),
        storyMediaVaultProvider.overrideWithValue(
          StoryMediaVault(supportDirectory: () async => dir!),
        ),
      ],
    );
    final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(Duration.zero);
      }
    }

    await settle();
    expect(lastKnown.value, isNotNull);
    await tester.runAsync(() => c.read(storyOutboxWiperProvider).wipeAll());
    expect(lastKnown.value, isNull);
    gateway.emitSignal();
    await settle();
    expect(lastKnown.value, isNull);
    // The next sign-in (every sign-in runs wipeExcept) lifts it.
    await tester.runAsync(
      () => c.read(storyOutboxWiperProvider).wipeExcept(ringMe),
    );
    gateway.emitSignal();
    await settle();
    expect(lastKnown.value, isNotNull);
    sub.close();
    await tester.pump(Duration.zero);
    c.dispose();
  });

  test(
    "a relationship's change clears Together and stories, each on its own",
    () async {
      final calls = <String>[];
      await clearLifecycleDeviceSurfaces(
        together: () async {
          calls.add('together');
          throw StateError('widget gone');
        },
        stories: () async => calls.add('stories'),
      );
      expect(calls, ['together', 'stories']);
    },
  );

  // Carried from batch 2: decoded thumbnails live in process memory too.
  testWidgets('with images, the decoded image cache is emptied too', (
    tester,
  ) async {
    final decoded = PaintingBinding.instance.imageCache;
    decoded.putIfAbsent(
      'story-thumb',
      () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
    );
    expect(decoded.pendingImageCount, 1);
    await clearStoryDeviceCaches(
      includeImages: false,
      images: NoopImageCache(),
    );
    expect(decoded.pendingImageCount, 1);
    await clearStoryDeviceCaches(images: NoopImageCache());
    expect(decoded.pendingImageCount, 0);
  });

  // Carried from batch 3 (review #1): quick exit has no container, so it
  // clears through a new store; a read in flight on the live one must
  // still see the wipe and not save again.
  test(
    'a clear through any secure store bumps every secure store\'s epoch',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final live = SecureStoryRingLastKnownStore();
      final before = live.epoch;
      await SecureStoryRingLastKnownStore().clear();
      expect(live.epoch, before + 1);
    },
  );

  // Carried from batch 3: with a container in hand, the live rings' memory
  // goes too.
  test('with a container, the live rings state is forgotten', () async {
    final lastKnown =
        MemoryStoryRingLastKnownStore()..value = _snapshot(ringMe);
    final container = ringContainer(RingGateway(), lastKnown: lastKnown);
    final shown = container.listen(
      storyRingLastKnownProvider(ringRel),
      (_, __) {},
    );
    expect(
      await container.read(storyRingLastKnownProvider(ringRel).future),
      isNotNull,
    );
    final coalescer = container.read(storyRingFetchCoalescerProvider)
      ..remember(ringRel, {ringPartner: ringRow()});
    final urls = container.read(storySignedUrlCacheProvider)..put('k', 'u');
    container
        .read(storyPostedHoldsProvider.notifier)
        .hold(
          StoryPostedHold(
            relationshipId: ringRel,
            clientStoryId: 'c1',
            heldAt: DateTime.now(),
          ),
        );
    await clearStoryDeviceState(
      container.read(_refProvider),
      includeImages: false,
    );
    expect(lastKnown.value, isNull);
    expect(lastKnown.epoch, 1);
    expect(coalescer.previous(ringRel), isNull);
    expect(urls.fresh('k'), isNull);
    expect(
      await container.read(storyRingLastKnownProvider(ringRel).future),
      isNull,
    );
    // Batch-4 review nit 8: the posted holds (in-memory thumbnails) too.
    expect(container.read(storyPostedHoldsProvider), isEmpty);
    shown.close();
    container.dispose();
  });

  test(
    'sign-out empties the live snapshot; an account switch keeps its own',
    () async {
      final dir = await Directory.systemTemp.createTemp('wipe');
      addTearDown(() => dir.delete(recursive: true));
      final lastKnown =
          MemoryStoryRingLastKnownStore()..value = _snapshot(ringMe);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(ringUser),
          storyOutboxStoreProvider.overrideWithValue(
            StoryOutboxStore.forTesting(stub.createStoryOutboxBackend()),
          ),
          storyMediaVaultProvider.overrideWithValue(
            StoryMediaVault(supportDirectory: () async => dir),
          ),
          storyRingLastKnownStoreProvider.overrideWithValue(lastKnown),
        ],
      );
      addTearDown(container.dispose);
      final wiper = StoryOutboxWiper(container.read(_refProvider));
      // Every sign-in runs wipeExcept, cold starts included: this account's
      // offline rings (03 M3) must survive it.
      await wiper.wipeExcept(ringMe);
      expect(lastKnown.value, isNotNull);
      expect(lastKnown.epoch, 0);
      await wiper.wipeExcept('someone-else');
      expect(lastKnown.value, isNull);
      lastKnown.value = _snapshot(ringMe);
      await wiper.wipeAll();
      expect(lastKnown.value, isNull);
    },
  );
}

StoryRingSnapshot _snapshot(String userId) => StoryRingSnapshot(
  userId: userId,
  relationshipId: ringRel,
  savedAt: DateTime.now(),
  rows: [ringRow()],
);
