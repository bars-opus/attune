import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Spec §6.1: "logout/account removal clears them." Rows first (their own
/// try, so a stuck file wipe never leaves a row that would auto-post on the
/// next sign-in), then the capture files, and beside them the story caches
/// (signed URLs and last-known rings; 05 #6). Never throws; holds the
/// caller at most [bound], like chat's staging wipe.
class StoryOutboxWiper {
  StoryOutboxWiper(
    this._ref, {
    this.bound = const Duration(seconds: 3),
    Future<void> Function()? clearCaches,
  }) : _clearCaches = clearCaches;

  final Ref _ref;
  final Duration bound;

  /// Signed URLs and the last-known rings (05 #6). Test seam.
  final Future<void> Function()? _clearCaches;

  Future<void> wipeAll() => _run(
    rows: () => _ref.read(storyOutboxStoreProvider).wipeAll(),
    files: () => _ref.read(storyMediaVaultProvider).wipeAll(),
    caches:
        _clearCaches ??
        // Sign-out empties both image caches itself (wipeImages).
        () => clearStoryDeviceState(
          _ref,
          includeImages: false,
          signingOut: true,
        ),
  );

  /// Every sign-in, cold starts included: only another account's snapshot
  /// goes, so this account's offline rings (03 M3) survive a launch.
  Future<void> wipeExcept(String userId) => _run(
    rows: () => _ref.read(storyOutboxStoreProvider).removeOtherUsers(userId),
    files: () => _ref.read(storyMediaVaultProvider).wipeExcept(userId),
    caches: _clearCaches ?? () => clearOtherAccountsStoryCaches(_ref, userId),
  );

  Future<void> _run({
    required Future<void> Function() rows,
    required Future<void> Function() files,
    required Future<void> Function() caches,
  }) async {
    // One deadline for every step: the caches run beside the rows and the
    // files, which get whatever the rows left, so the caller is held at
    // most [bound] in total. An abandoned step keeps running in the
    // background.
    final watch = Stopwatch()..start();
    final cachesDone = Future.sync(caches).timeout(bound).catchError((
      Object e,
    ) {
      debugPrint('⚠️ [STORIES] cache wipe failed: ${e.runtimeType}');
    });
    try {
      await rows().timeout(bound);
    } catch (e) {
      debugPrint('⚠️ [STORIES] outbox row wipe failed: ${e.runtimeType}');
    }
    try {
      final left = bound - watch.elapsed;
      await files().timeout(left.isNegative ? Duration.zero : left);
    } catch (e) {
      debugPrint('⚠️ [STORIES] outbox file wipe failed: ${e.runtimeType}');
    }
    await cachesDone;
  }
}

final storyOutboxWiperProvider = Provider<StoryOutboxWiper>(
  (ref) => StoryOutboxWiper(ref),
);
