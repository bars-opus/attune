import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/widgets/keep_mounted_cover.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/pin_lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root gate above the Navigator (Spec 2; research 06 §3 F2): while the
/// PIN is required the app's subtree -- the Navigator included -- is not in
/// the tree at all, so no deep link, notification tap or widget launch can
/// show it. A tap that arrives meanwhile is replayed on unlock (review I5).
/// While a return from the background is being checked, an app that was
/// already shown stays mounted behind a plain cover (stories Wave 3; 07b
/// G7), and notification taps still wait: shouldDeferNotificationTap keys
/// on the lock state, not on whether a Navigator exists.
class SafetyLockGate extends ConsumerStatefulWidget {
  const SafetyLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SafetyLockGate> createState() => _SafetyLockGateState();
}

class _SafetyLockGateState extends ConsumerState<SafetyLockGate> {
  late final AppLifecycleListener _lifecycle;
  bool _wentBackground = false;

  /// The app has been shown since the last lock (or the cold start). While
  /// true, a return's `checking` hides it behind a cover but keeps it
  /// mounted (stories Wave 3); `locked` replaces it and clears this, so the
  /// PIN screen never has the app behind it.
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _wentBackground = true;
        // Off from now until the return's check passes, whatever order the
        // lifecycle listeners run in: `resumed` alone must never read as
        // on screen while the lock is still deciding (stories Wave 3).
        ref.read(appContentVisibleProvider.notifier).setLockOpen(false);
        // A tap delivered before the return's check waits for it (M5).
        ref.read(safetyLockProvider.notifier).onHidden();
      },
      onResume: () {
        if (!_wentBackground) return;
        _wentBackground = false;
        ref.read(safetyLockProvider.notifier).evaluate(coldStart: false);
      },
    );
    // Seeded open, there is no transition to replay on: a cold-start tap
    // held only because the Navigator did not exist yet goes now (review I5).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The starting state (a seeded lock, a cold-start check) is no
      // transition, so the listener in build never pushes it; pushed after
      // the frame, as a provider may not change while widgets build.
      ref
          .read(appContentVisibleProvider.notifier)
          .setLockOpen(ref.read(safetyLockProvider) == SafetyLockState.open);
      if (ref.read(safetyLockProvider) == SafetyLockState.open) {
        _replay();
      }
    });
  }

  void _replay() {
    try {
      ref.read(oneSignalServiceProvider).replayPendingTap();
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The next person on this phone must not inherit this person's PIN.
    ref.listen(currentUserProvider, (prev, next) {
      if (prev != null && next == null) {
        ref.read(safetyLockProvider.notifier).onSignedOut();
      }
    });
    ref.listen(safetyLockProvider, (prev, next) {
      // What is kept mounted behind the check -- media, cameras, read
      // receipts -- waits for the lock to open (stories Wave 3).
      ref
          .read(appContentVisibleProvider.notifier)
          .setLockOpen(next == SafetyLockState.open);
      if (next == SafetyLockState.open && prev != SafetyLockState.open) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _replay());
      }
    });
    final state = ref.watch(safetyLockProvider);
    if (state == SafetyLockState.locked) {
      _shown = false;
      return const PinLockScreen();
    }
    if (state == SafetyLockState.checking && !_shown) {
      // Cold start: the Router is not built until the check ends (I5).
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    }
    final open = state == SafetyLockState.open;
    if (open) _shown = true;
    return KeepMountedCover(
      obscured: !open,
      cover: ColoredBox(
        key: const Key('safety_lock_checking_cover'),
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: widget.child,
    );
  }
}
