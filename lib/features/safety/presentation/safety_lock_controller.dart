import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SafetyLockState { checking, open, locked }

class SafetyLockDeps {
  const SafetyLockDeps({
    required this.quickExitFlag,
    required this.clearQuickExitFlag,
    required this.pins,
    required this.signOut,
    required this.signedIn,
    required this.leaveDecoy,
  });

  final Future<bool> Function() quickExitFlag;
  final Future<void> Function() clearQuickExitFlag;
  final SafetyPinStore pins;
  final Future<void> Function() signOut;
  final bool Function() signedIn;

  /// Off the quick-exit decoy, if the router is still on it (review I2).
  final void Function() leaveDecoy;
}

final safetyLockDepsProvider = Provider<SafetyLockDeps>((ref) {
  return SafetyLockDeps(
    quickExitFlag: QuickExitService.requiresSafetyUnlock,
    clearQuickExitFlag: QuickExitService.clearSafetyUnlockRequired,
    pins: SafetyPinStore.instance,
    signOut: () => safetySignOut(ref),
    signedIn: () => ref.read(currentUserProvider) != null,
    leaveDecoy: () {
      final router = ref.read(appRouterProvider);
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path == RouteNames.neutralScreen) router.go(RouteNames.home);
    },
  );
});

/// What the first frame shows, computed before runApp from the keystore
/// (review I5), so the common unlocked path mounts the Router on frame 1.
SafetyLockState initialLockState({
  required bool flag,
  required bool hasPin,
  required bool everyOpen,
  required bool signedIn,
}) {
  if (!signedIn) return SafetyLockState.open;
  if (flag) return hasPin ? SafetyLockState.locked : SafetyLockState.checking;
  if (hasPin && everyOpen) return SafetyLockState.locked;
  return SafetyLockState.open;
}

/// What main() seeds, read before runApp. A signed-out phone keeps no PIN
/// data (review I-6); a PIN the keystore lost is decided by evaluate, which
/// signs out (review I-4).
Future<SafetyLockState> computeLockSeed({
  required Future<bool> Function() quickExitFlag,
  required Future<void> Function() clearQuickExitFlag,
  required SafetyPinStore pins,
  required bool signedIn,
}) async {
  if (!signedIn) {
    await pins.clearAll();
    await clearQuickExitFlag();
    return SafetyLockState.open;
  }
  if (await pins.isCorrupt()) return SafetyLockState.checking;
  return initialLockState(
    flag: await quickExitFlag(),
    hasPin: await pins.hasPin(),
    everyOpen: await pins.everyOpen(),
    signedIn: true,
  );
}

/// Seeded by main(); null in tests and when the keystore could not be read.
final safetyLockSeedProvider = Provider<SafetyLockState?>((ref) => null);

/// A push arriving while Attune is in the foreground shows no banner over
/// the lock or the decoy (review I10).
bool shouldSuppressForegroundPush(SafetyLockState state, String path) =>
    state != SafetyLockState.open || path == RouteNames.neutralScreen;

/// A notification tap waits while locked, on the decoy (iOS keeps the decoy
/// in the foreground after a quick exit) or before the Navigator exists
/// (review I-2, I5).
bool shouldDeferNotificationTap({
  required SafetyLockState state,
  required String path,
  required bool navigatorReady,
}) => !navigatorReady || shouldSuppressForegroundPush(state, path);

/// A waiting tap goes only to a signed-in, open app off the decoy: never to
/// a person a sign-out just took to the login screen (review I-5).
bool canReplayNotificationTap({
  required bool signedIn,
  required SafetyLockState state,
  required String path,
  required bool navigatorReady,
}) =>
    signedIn &&
    !shouldDeferNotificationTap(
      state: state,
      path: path,
      navigatorReady: navigatorReady,
    );

/// Whether Attune may show itself (Spec 2; research 06 §3 F2). Decided at
/// cold start and on every return from the background, in a provider, so
/// the decision lives outside everything the gate hides or replaces.
/// Every failure fails closed: signed out, or locked (review C2, I1).
class SafetyLockController extends Notifier<SafetyLockState> {
  SafetyLockDeps get _deps => ref.read(safetyLockDepsProvider);

  @override
  SafetyLockState build() {
    final seed = ref.read(safetyLockSeedProvider);
    if (seed == SafetyLockState.open || seed == SafetyLockState.locked) {
      return seed!;
    }
    Future.microtask(() => evaluate(coldStart: true));
    return SafetyLockState.checking;
  }

  Future<void> _open() async {
    state = SafetyLockState.open;
    try {
      _deps.leaveDecoy();
    } catch (_) {}
  }

  bool _signedIn() {
    try {
      return _deps.signedIn();
    } catch (_) {
      // No auth client at all (no config): nothing is signed in to protect,
      // and the login screen is what shows (review M-10).
      return false;
    }
  }

  /// Sign out, and open only if it worked; otherwise stay locked.
  Future<bool> _signOutThenOpen() async {
    try {
      await _deps.signOut();
    } catch (_) {}
    if (_signedIn()) {
      state = SafetyLockState.locked;
      return false;
    }
    state = SafetyLockState.open;
    return true;
  }

  Future<void> evaluate({required bool coldStart}) async {
    final d = _deps;
    // On a return from the background nothing of the app may paint while
    // the keystore is read: the gate shows the cover colour (review I-1).
    if (!coldStart && state == SafetyLockState.open) {
      state = SafetyLockState.checking;
    }
    try {
      final flag = await d.quickExitFlag();
      if (!_signedIn()) {
        // Nothing to protect behind a login screen, and no PIN may outlive
        // the session it protected (review I-6).
        await d.pins.clearAll();
        if (flag) await d.clearQuickExitFlag();
        state = SafetyLockState.open;
        return;
      }
      // A PIN set here that the keystore no longer holds (a reset, or a
      // backup restored elsewhere) fails closed: signed out (review I-4).
      if (await d.pins.isCorrupt()) {
        await _signOutThenOpen();
        return;
      }
      final hasPin = await d.pins.hasPin();
      if (flag) {
        if (hasPin) {
          state = SafetyLockState.locked;
        } else {
          // Quick exit with no PIN: the way back is signed out (F2 (6)).
          // The flag clears only once that worked, so a failed sign-out
          // still comes back to this on the next open (review I-3).
          if (await _signOutThenOpen()) await d.clearQuickExitFlag();
        }
        return;
      }
      if (hasPin && await d.pins.everyOpen()) {
        state = SafetyLockState.locked;
        return;
      }
      if (state != SafetyLockState.locked) await _open();
    } catch (_) {
      await _signOutThenOpen();
    }
  }

  /// Attune left the screen (hidden): the return will be checked, so from
  /// now on the lock reads `checking`, not a stale `open`. A notification
  /// tap the OS delivers before `resumed` then waits like one during the
  /// check, and is replayed when the lock opens (stories Wave 3 final
  /// review M5). Locked stays locked.
  void onHidden() {
    if (state == SafetyLockState.open) state = SafetyLockState.checking;
  }

  Future<({PinCheck result, DateTime? retryAt})> unlock(String pin) async {
    try {
      final r = await _deps.pins.check(pin);
      if (r.result == PinCheck.ok) {
        await _deps.clearQuickExitFlag();
        await _open();
      }
      return r;
    } catch (_) {
      return (result: PinCheck.wrong, retryAt: null);
    }
  }

  /// "Forgot PIN?": sign out to the login screen; the PIN goes (F2 (5)).
  /// False when the sign-out did not happen (the lock stays).
  Future<bool> forgot() async {
    // Sign out first: the PIN stays until that worked, so a failed sign-out
    // and a relaunch are still locked (review I-3).
    final ok = await _signOutThenOpen();
    if (!ok) return false;
    try {
      await _deps.pins.clearAll();
      await _deps.clearQuickExitFlag();
    } catch (_) {}
    return true;
  }

  /// The next person on this phone must not inherit this person's PIN.
  Future<void> onSignedOut() async {
    try {
      await _deps.pins.clearAll();
      await _deps.clearQuickExitFlag();
    } catch (_) {}
    state = SafetyLockState.open;
  }
}

final safetyLockProvider =
    NotifierProvider<SafetyLockController, SafetyLockState>(
      SafetyLockController.new,
    );
