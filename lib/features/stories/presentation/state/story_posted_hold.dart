/// A story that just posted, kept on my ring until a ring summary issued
/// after it arrives (03 M1). Finalize removes the outbox row and the local
/// capture at once, but the summary only learns of the post on its next
/// read; without this the ring flashed back to `+` (or to the previous
/// story) in between, and stayed there while realtime was down. In memory
/// only, with the thumbnail's bytes (the file is already gone), and never
/// longer than [kStoryPostedHoldCap].
library;

import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Duration kStoryPostedHoldCap = Duration(minutes: 2);

@immutable
class StoryPostedHold {
  const StoryPostedHold({
    required this.relationshipId,
    required this.clientStoryId,
    required this.heldAt,
    this.thumbnailBytes,
    this.thumbnailStorageKey,
  });

  final String relationshipId;
  final String clientStoryId;
  final DateTime heldAt;
  final Uint8List? thumbnailBytes;

  /// Where the server keeps the thumbnail: the key the summary will name,
  /// and the one [thumbnailBytes] are seeded under on disk.
  final String? thumbnailStorageKey;
}

/// Puts a just-posted thumbnail's bytes in the shared disk cache under its
/// storage key (the chat_poster_prewarmer pattern), so the summary's ring
/// finds them on disk instead of waiting on signing and a download.
typedef StoryThumbnailSeeder =
    Future<void> Function(String storageKey, Uint8List bytes);

final storyThumbnailSeederProvider = Provider<StoryThumbnailSeeder>(
  (_) => seedStoryThumbnailOnDisk,
);

/// Never throws, never holds the caller: DefaultCacheManager is built in a
/// guarded zone, as [storyCachedThumbnailOnDisk] reads it.
Future<void> seedStoryThumbnailOnDisk(String storageKey, Uint8List bytes) {
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      await DefaultCacheManager().putFile(
        storageKey,
        bytes,
        key: storageKey,
        fileExtension: 'jpg',
      );
      if (!done.isCompleted) done.complete();
    },
    (_, __) {
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}

class StoryPostedHolds extends StateNotifier<List<StoryPostedHold>> {
  StoryPostedHolds() : super(const []);

  final Map<String, Timer> _caps = {};

  /// Released holds' bytes by storage key, until [kStoryPostedHoldCap] after
  /// their hold (review #1): the summary's ring paints them while its disk
  /// lookup runs, so the release never blinks to grey. Pruned on use, with
  /// no timer of their own.
  final Map<String, ({Uint8List bytes, DateTime until})> _bridges = {};

  /// The bytes a just-released hold carried for [storageKey], if any.
  Uint8List? bridgeFor(String storageKey) {
    _pruneBridges();
    return _bridges[storageKey]?.bytes;
  }

  void _pruneBridges() {
    final now = clock.now();
    _bridges.removeWhere((_, b) => !b.until.isAfter(now));
  }

  void hold(StoryPostedHold hold) {
    if (!mounted) return;
    state = [
      for (final h in state)
        if (h.clientStoryId != hold.clientStoryId) h,
      hold,
    ];
    _caps.remove(hold.clientStoryId)?.cancel();
    _caps[hold.clientStoryId] = Timer(
      kStoryPostedHoldCap,
      () => _drop((h) => h.clientStoryId == hold.clientStoryId),
    );
  }

  /// A ring read for [relationshipId] issued at [fetchStartedAt] landed:
  /// every hold set at or before then is answered by it.
  void releaseFetchedSince(String relationshipId, DateTime fetchStartedAt) {
    bool answered(StoryPostedHold h) =>
        h.relationshipId == relationshipId && !h.heldAt.isAfter(fetchStartedAt);
    if (!mounted) return;
    _pruneBridges();
    for (final hold in state.where(answered)) {
      final bytes = hold.thumbnailBytes;
      final key = hold.thumbnailStorageKey;
      if (bytes != null && key != null && key.isNotEmpty) {
        _bridges[key] = (
          bytes: bytes,
          until: hold.heldAt.add(kStoryPostedHoldCap),
        );
      }
    }
    _drop(answered);
  }

  void _drop(bool Function(StoryPostedHold hold) test) {
    if (!mounted) return;
    final gone = state.where(test).toList();
    if (gone.isEmpty) return;
    for (final hold in gone) {
      _caps.remove(hold.clientStoryId)?.cancel();
    }
    state = [
      for (final h in state)
        if (!test(h)) h,
    ];
  }

  @override
  void dispose() {
    for (final timer in _caps.values) {
      timer.cancel();
    }
    _caps.clear();
    _bridges.clear();
    super.dispose();
  }
}

/// Per account: a new, empty list on every sign-in.
final storyPostedHoldsProvider =
    StateNotifierProvider<StoryPostedHolds, List<StoryPostedHold>>((ref) {
      ref.watch(currentUserProvider.select((u) => u?.id));
      return StoryPostedHolds();
    });
