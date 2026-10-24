import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final relationshipLifecycleServiceProvider =
    Provider<RelationshipLifecycleService>(
      (_) => RelationshipLifecycleService(),
    );

/// The caller's paused, ended or archived shared space, or null (Spec 3a).
final relationshipLifecycleProvider =
    FutureProvider.autoDispose<RelationshipLifecycle?>(
      (ref) => ref.watch(relationshipLifecycleServiceProvider).fetchLifecycle(),
    );

final lifecycleClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// The home-screen card, lock-screen plan and calendar copy (F1 (6)), and
/// since stories Wave 4 the story caches on this phone (05 #6).
final lifecycleClearSurfacesProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => clearLifecycleDeviceSurfaces(
        stories: () => clearStoryDeviceState(ref),
      ),
);

/// Each part on its own: a failure in one never skips the other. The
/// stories part is bounded, so the ended sheet is never held behind it.
Future<void> clearLifecycleDeviceSurfaces({
  Future<void> Function() together = clearTogetherDeviceSurfaces,
  Future<void> Function() stories = clearStoryDeviceCaches,
}) async {
  try {
    await together();
  } catch (_) {}
  try {
    await Future.sync(stories).timeout(const Duration(seconds: 3));
  } catch (_) {}
}

final lifecycleUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

/// True while the app is open (not checking, not behind the Safety PIN).
final lifecycleLockOpenProvider = Provider<bool>(
  (ref) => ref.watch(safetyLockProvider) == SafetyLockState.open,
);
