// Spec 2 W3a (§3.0 Lock, §3.14; R-8): with Spec 1's Dating lock on, every
// Dating route, deep link and push tap asks for the Safety PIN first, once
// per foreground session. The unlock is memory only: putting the app away,
// another account, quick exit and sign-out all end it. The lock itself is
// Spec 1's protective setting and is never cleared here.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/me/presentation/widgets/dating_lock_setting.dart'
    show setDatingLock;
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const datingUnlockPath = '/dating/unlock';

/// Dating state held in memory, cleared on quick exit and sign-out through
/// Spec 1's registry (registerDatingDeviceWipes). No device key.
abstract final class DatingSessionMemory {
  static final _clears = <Object, void Function()>{};

  /// [owner]'s [clear], until [ref] is disposed or rebuilt.
  static void track(Object owner, Ref ref, void Function() clear) {
    _clears[owner] = clear;
    ref.onDispose(() => _clears.remove(owner));
  }

  static Future<void> clear() async {
    for (final clear in List.of(_clears.values)) {
      try {
        clear();
      } catch (_) {
        // Something being torn down has nothing left to clear.
      }
    }
  }
}

/// Whether the Safety PIN was entered for Dating in this foreground session.
class DatingUnlock extends Notifier<bool> with WidgetsBindingObserver {
  @override
  bool build() {
    // Another account (or a sign-out) starts locked again (D8). Only a
    // change of account counts: the same id again (a token refresh)
    // keeps the unlock (fix round 1, I-2).
    ref.watch(datingLockAccountProvider.select((a) => a.valueOrNull));
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    DatingSessionMemory.track(this, ref, lock);
    return false;
  }

  void unlock() => state = true;

  void lock() {
    if (state) state = false;
  }

  @override
  // The parameter keeps the framework's name; `this.state` is the unlock.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      lock();
    }
  }
}

final datingUnlockedProvider = NotifierProvider<DatingUnlock, bool>(
  DatingUnlock.new,
);

/// Final fix (I-2): Spec 1's setDatingLock from a Dating screen. Turned on
/// here, the lock guards the next session: the person is already inside
/// Dating in this one, so they stay where they are (their answers and
/// back stack kept). The unlock still ends when the app is put away, on
/// another account and on quick exit.
Future<void> setDatingLockInDating(
  BuildContext context,
  WidgetRef ref,
  bool on, {
  SafetyPinStore? pins,
}) async {
  await setDatingLock(context, ref, on, pins: pins);
  if (on && (ref.read(datingLockProvider).valueOrNull ?? false)) {
    ref.read(datingUnlockedProvider.notifier).unlock();
  }
}

/// Fix round 1 (C-1; §3.0, §3.14): every Dating page but the unlock sits
/// in this gate (datingRoute adds it, so each new route has it). While the
/// Dating lock is on, or can't be read, and the PIN hasn't been entered in
/// this foreground session, nothing of the page is built: an empty screen,
/// then the PIN screen in its place. So an open page asks again as soon as
/// the unlock ends (the app put away, another account), not only on the
/// next navigation. Fix round 2 (I-3): the router's top page decides, so
/// a sheet or dialog open over it goes too.
class DatingLockGate extends ConsumerStatefulWidget {
  const DatingLockGate({
    super.key,
    required this.pageKey,
    required this.from,
    required this.child,
  });

  /// The page's key in the router: only the gate of the router's top page
  /// moves, once, however many Dating pages are stacked.
  final LocalKey pageKey;

  /// The page's own location: where the unlock comes back to.
  final String from;
  final Widget child;

  @override
  ConsumerState<DatingLockGate> createState() => _DatingLockGateState();
}

class _DatingLockGateState extends ConsumerState<DatingLockGate> {
  bool _asking = false;

  void _askAgain() {
    if (_asking) return;
    _asking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _asking = false;
      if (!mounted) return;
      // Only the router's top page moves, with every sheet and dialog over
      // it: go() replaces the pages, and a pageless route (on this
      // navigator or the root one) goes with the page it was opened over.
      // A page that isn't Dating on top (quick exit's decoy, Me) stays.
      final router = GoRouter.of(context);
      final top = router.routerDelegate.currentConfiguration;
      if (top.isEmpty || top.last.pageKey != widget.pageKey) return;
      router.go(
        Uri(
          path: datingUnlockPath,
          queryParameters: {'from': widget.from},
        ).toString(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(datingLockProvider);
    if (ref.watch(datingUnlockedProvider)) return widget.child;
    // Being read again (another account): show nothing until it is known.
    if (lock.isLoading) return const Scaffold(body: SizedBox.shrink());
    if (!lock.hasError && lock.valueOrNull == false) return widget.child;
    _askAgain();
    return const Scaffold(body: SizedBox.shrink());
  }
}

/// The one redirect every Dating route carries: signed out → sign in; the
/// Dating lock on and not yet unlocked → the PIN first. A lock setting that
/// can't be read asks (fail closed).
Future<String?> datingRedirect(
  BuildContext context,
  GoRouterState state, {
  required bool signedIn,
}) async {
  if (!signedIn) return RouteNames.login;
  if (state.uri.path == datingUnlockPath) return null;
  final ProviderContainer container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return homeLocation(tab: AppTab.me);
  }
  bool locked;
  try {
    locked = await container.read(datingLockProvider.future);
  } catch (_) {
    locked = true;
  }
  if (!locked || container.read(datingUnlockedProvider)) return null;
  return Uri(
    path: datingUnlockPath,
    queryParameters: {'from': state.uri.toString()},
  ).toString();
}

/// Where an unlock goes on: only a Dating location, never the unlock
/// itself, never anything with a scheme, a host or `..` (no open redirect).
String datingSafeReturn(String? from) {
  final uri = Uri.tryParse(from ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/dating/') ||
      uri.path == datingUnlockPath ||
      uri.path.contains('..')) {
    return homeLocation(tab: AppTab.me);
  }
  return uri.toString();
}

/// §3.14's "PIN screen": the existing Safety PIN sheet, then the place asked
/// for. Dismissing the sheet stays here; Back goes to Me.
class DatingUnlockScreen extends ConsumerStatefulWidget {
  const DatingUnlockScreen({super.key, required this.from});

  final String from;

  @override
  ConsumerState<DatingUnlockScreen> createState() => _DatingUnlockScreenState();
}

class _DatingUnlockScreenState extends ConsumerState<DatingUnlockScreen> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    if (_asking || !mounted) return;
    setState(() => _asking = true);
    final ok = await confirmSafetyPin(context);
    if (!mounted) return;
    setState(() => _asking = false);
    if (!ok) return;
    ref.read(datingUnlockedProvider.notifier).unlock();
    context.go(datingSafeReturn(widget.from));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_slotLocked,
      onBack: () => context.go(homeLocation(tab: AppTab.me)),
      body: Text(
        loc.flow_slotLockedLine,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.dating_unlockButton,
          busy: _asking,
          onPressed: _ask,
        ),
      ],
    );
  }
}
