// lib/core/services/app_content_visibility.dart
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Attune's content is on screen right now: the app is resumed (the
/// privacy cover is down) and the Safety lock is open (not checking, not
/// locked).
///
/// The shell keeps the app's subtree mounted behind the privacy cover and
/// during the lock's return check (stories Wave 3; 07b G7), so leaving the
/// screen no longer disposes anything. Whatever must stop when nobody can
/// see it -- media with sound, a camera, a recording, read receipts --
/// listens to this instead of relying on being unmounted.
///
/// The lifecycle half is decided in the lifecycle callback itself, not
/// from a rebuilt frame: iOS can go from inactive to hidden before another
/// frame is drawn. The lock half is pushed in by `SafetyLockGate`
/// ([setLockOpen]), so core does not depend on the safety feature and a
/// test without the gate sees only the lifecycle. The gate pushes the
/// starting lock state after its first frame, so a reader outside the
/// gate's subtree may see true for the first frame of a cold start.
class AppContentVisibility extends Notifier<bool> {
  bool _lockOpen = true;

  @override
  bool build() {
    final listener = AppLifecycleListener(onStateChange: (_) => _sync());
    ref.onDispose(listener.dispose);
    return _compute();
  }

  bool _compute() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    return foreground && _lockOpen;
  }

  void _sync() {
    final next = _compute();
    if (next != state) state = next;
  }

  /// Called by `SafetyLockGate` on every lock state change: open, or not
  /// (checking a return, or locked). Never during a build: the reel and the
  /// streak viewer call setState from their listeners synchronously.
  void setLockOpen(bool open) {
    assert(
      SchedulerBinding.instance.schedulerPhase !=
          SchedulerPhase.persistentCallbacks,
      'setLockOpen was called during a build, layout or paint; push the '
      'lock state from a lifecycle, listener or post-frame callback.',
    );
    _lockOpen = open;
    _sync();
  }
}

final appContentVisibleProvider = NotifierProvider<AppContentVisibility, bool>(
  AppContentVisibility.new,
);

/// For a provider that used to refetch only because the shell's teardown
/// re-created it on every return (stories Wave 3): re-runs it each time
/// Attune's content comes back on screen (not visible -> visible), the way
/// the Together and Planning providers re-run on their change signals.
/// A FutureProvider keeps showing its last value while it refetches.
void refreshWhenVisibleAgain(Ref ref) {
  ref.listen<bool>(appContentVisibleProvider, (prev, next) {
    if (next && prev == false) ref.invalidateSelf();
  });
}

/// For a plain State (not a ConsumerState) that may be built without a
/// ProviderScope above it, as some widget tests do: listens to
/// [appContentVisibleProvider] when there is a scope, else returns null and
/// the caller treats Attune as on screen. Safe from initState (it adds no
/// dependency). The caller closes the subscription in dispose.
ProviderSubscription<bool>? listenAppContentVisibleOf(
  BuildContext context,
  void Function(bool visible) onChange,
) {
  final ProviderContainer container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return null;
  }
  return container.listen<bool>(
    appContentVisibleProvider,
    (_, next) => onChange(next),
  );
}
