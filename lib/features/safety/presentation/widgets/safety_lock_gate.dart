import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/pin_lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root gate above the Navigator (Spec 2; research 06 §3 F2): while the
/// PIN is required the app's subtree -- the Navigator included -- is not in
/// the tree at all, so no deep link, notification tap or widget launch can
/// show it. A tap that arrives meanwhile is replayed on unlock (review I5).
class SafetyLockGate extends ConsumerStatefulWidget {
  const SafetyLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SafetyLockGate> createState() => _SafetyLockGateState();
}

class _SafetyLockGateState extends ConsumerState<SafetyLockGate> {
  late final AppLifecycleListener _lifecycle;
  bool _wentBackground = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _wentBackground = true,
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
      if (next == SafetyLockState.open && prev != SafetyLockState.open) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _replay());
      }
    });
    switch (ref.watch(safetyLockProvider)) {
      case SafetyLockState.checking:
        return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
      case SafetyLockState.locked:
        return const PinLockScreen();
      case SafetyLockState.open:
        return widget.child;
    }
  }
}
