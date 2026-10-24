/// What stories keep on this phone outside the outbox (05 #6): signed URLs
/// in memory, thumbnails in the shared image cache (on disk, and decoded in
/// Flutter's in-memory image cache), and the last-known rings snapshot.
/// Quick exit and a relationship's pause, end or archive clear all of them;
/// by owner ruling the whole shared image cache goes, so chat and map
/// photos re-download once. Sign-out passes `includeImages: false`, because
/// it already empties both image caches (auth_provider.dart wipeImages).
/// Never throws; each part on its own.
library;

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:attune/features/stories/presentation/state/story_ring_refresh.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> clearStoryDeviceCaches({
  bool includeImages = true,
  ChatImageCache? images,
  StoryRingLastKnownStore? lastKnown,
}) async {
  StorySignedUrlCache.clearEveryLiveCache();
  if (includeImages) _clearDecodedImages();
  await Future.wait([
    if (includeImages) _quietly(() => (images ?? ChatImageCache()).clear()),
    _quietly(() => (lastKnown ?? SecureStoryRingLastKnownStore()).clear()),
  ]);
}

/// [clearStoryDeviceCaches] with a container in hand (sign-out, a
/// relationship's change): the live snapshot store, so its epoch stops a
/// ring read in flight from saving again, and the live rings' memory, so
/// nothing painted or diffed later comes from before the wipe.
///
/// [signingOut]: no snapshot of the signed-in account is written again
/// until the next sign-in (batch-4 review #2).
Future<void> clearStoryDeviceState(
  Ref ref, {
  bool includeImages = true,
  bool signingOut = false,
}) async {
  if (signingOut) {
    _quietlySync(() {
      // Only a live one has a user whose rings could be read meanwhile.
      if (!ref.exists(currentUserProvider)) return;
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        ref.read(storyRingLastKnownStoreProvider).blockWritesFor(userId);
      }
    });
  }
  // Only a live one has rings to forget; building one here would sign in
  // to nothing.
  _quietlySync(() {
    if (ref.exists(storyRingFetchCoalescerProvider)) {
      ref.read(storyRingFetchCoalescerProvider).forgetRings();
    }
  });
  // The month counts last read (past-day thumbnail keys, 05 #6).
  _quietlySync(() {
    if (ref.exists(storyDayCountsMemoProvider)) {
      ref.read(storyDayCountsMemoProvider).clear();
    }
  });
  if (!signingOut) {
    // Final review M-2: what is still on screen re-reads, so no mounted
    // ring, URL or month count from before the wipe hands an image loader
    // a URL to fetch a wiped thumbnail back to disk with. The URLs go
    // first, so a re-sign can never reuse one. A closed relationship's
    // re-read finds nothing, and its media are no longer signed
    // (STORIES.md §4.1). Not on sign-out: the session still signs then,
    // and the account change resets these anyway.
    StorySignedUrlCache.clearEveryLiveCache();
    _quietlySync(() => ref.invalidate(storyMediaSignedUrlProvider));
    _quietlySync(() => ref.invalidate(storyRingSummaryProvider));
    _quietlySync(() => ref.invalidate(storyDayCountsProvider));
  }
  await clearStoryDeviceCaches(
    includeImages: includeImages,
    images:
        includeImages
            ? _readOrNull(() => ref.read(chatImageCacheProvider))
            : null,
    lastKnown: _readOrNull(() => ref.read(storyRingLastKnownStoreProvider)),
  );
  // After the delete: a re-read now finds nothing.
  _quietlySync(() => ref.invalidate(storyRingLastKnownProvider));
  // Just-posted thumbnails held in memory (batch-4 review nit 8).
  _quietlySync(() {
    if (ref.exists(storyPostedHoldsProvider)) {
      ref.invalidate(storyPostedHoldsProvider);
    }
  });
}

/// Every sign-in, cold starts included: drops the snapshot only when it is
/// another account's, so this account's offline rings (03 M3) survive a
/// launch. URLs and the rings' memory are per account already.
Future<void> clearOtherAccountsStoryCaches(Ref ref, String userId) async {
  final store = _readOrNull(() => ref.read(storyRingLastKnownStoreProvider));
  if (store == null) return;
  _quietlySync(store.allowWrites);
  await _quietly(() async {
    final snapshot = await store.read();
    if (snapshot != null && snapshot.userId != userId) await store.clear();
  });
}

void _clearDecodedImages() {
  try {
    // No binding (a bare test host) means no decoded images to clear.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  } catch (_) {}
}

T? _readOrNull<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

void _quietlySync(void Function() step) {
  try {
    step();
  } catch (_) {}
}

Future<void> _quietly(Future<void> Function() step) async {
  try {
    await step();
  } catch (_) {}
}
