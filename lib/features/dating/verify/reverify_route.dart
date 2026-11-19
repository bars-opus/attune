// Spec 2 W4b (§3.3.4; carry 9): /dating/verify, where every
// reverify_device answer leads. Before a passed check (setup_restart):
// "You started setting up Dating on another phone…" and Start again, which
// leaves Dating (the draft hard-deleted, as exit, §3.8) and opens D1 here,
// keeping the 'Never introduce me' list (R-32, owner ruling 2026-11-09).
// After one (verified): the video check on this phone (liveness and
// CompareFaces, no age), or a person checks two photos. What the person
// sees follows the home's answer, read again on every open (D8: nothing
// of one account shown to the next).
//
// Task 7 (T6 I-4 ruling): a phone with no install id can't be checked at
// all (every check there answers device_unavailable), so it shows the calm
// line and offers nothing: neither the re-check nor Start again, which
// would leave Dating for a setup that phone can't save.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingReverifyRoute extends ConsumerStatefulWidget {
  const DatingReverifyRoute({super.key});

  @override
  ConsumerState<DatingReverifyRoute> createState() =>
      _DatingReverifyRouteState();
}

class _DatingReverifyRouteState extends ConsumerState<DatingReverifyRoute> {
  /// The account whose re-check (or Start again) is on screen. Once shown,
  /// a home read again mid-check (a busy answer, T6 concern 2) never takes
  /// it away; another account starts over (D8).
  String? _shownFor;

  /// Fix round 1 (M-1): the home is read again once this opens, so a home
  /// cached before the phone was dropped never decides what shows.
  bool _readAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));
      setState(() => _readAgain = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final home = ref.watch(datingHomeProvider(account));
    void toMe() => context.go(homeLocation(tab: AppTab.me));
    void back() => context.canPop() ? context.pop() : toMe();
    final ready = datingDeviceReady(ref);
    if (ready == false) return DatingDeviceUnavailableScreen(onBack: back);
    // Fix round 1 (M-2): while the home or the install id is read, the
    // step frame with its way back (never a bare screen).
    final loading = DatingStepFrame(
      step: 'reverify',
      title: loc.flow_slotDatingTitle,
      onBack: back,
      body: const SizedBox.shrink(),
    );
    // Until this account's re-check is on screen, only a fresh read decides.
    final fresh = _shownFor == account || (_readAgain && !home.isLoading);
    final h = fresh ? home.valueOrNull : null;
    if (h == null || ready == null) {
      if (!fresh || !home.hasError || ready != true) return loading;
      _shownFor = account;
      return DatingVerifyFlow(
        step: 'reverify',
        reverify: true,
        onBack: back,
        onDone: toMe,
        onChangePhotos: () {},
      );
    }
    // Fix round 1 (M-1): a link followed after the home moved on (the
    // phone trusted again, or a check this account needs instead) never
    // opens the re-check: D11 for a check, otherwise back (final fix M-5:
    // to the screen it was followed from, or Me when there is none).
    if (h.state != DatingHomeState.reverifyDevice && _shownFor != account) {
      final check =
          h.state == DatingHomeState.verifying ||
          (h.state == DatingHomeState.paused &&
              h.pauseReason == DatingPauseReason.verification);
      return _GoTo(
        onShown: check ? () => context.go(DatingPaths.step('verify')) : back,
        child: loading,
      );
    }
    _shownFor = account;
    if (h.state == DatingHomeState.reverifyDevice &&
        h.reverifyVariant == DatingReverifyVariant.setupRestart) {
      return DatingStartAgainScreen(onBack: back);
    }
    return DatingVerifyFlow(
      step: 'reverify',
      reverify: true,
      onBack: back,
      onDone: () {
        ref.invalidate(datingHomeProvider(account));
        toMe();
      },
      onChangePhotos: () {},
    );
  }
}

/// Shows [child] for one frame, then runs [onShown] (a go, or back).
class _GoTo extends StatefulWidget {
  const _GoTo({required this.onShown, required this.child});

  final VoidCallback onShown;
  final Widget child;

  @override
  State<_GoTo> createState() => _GoToState();
}

class _GoToState extends State<_GoTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// §3.3.4's setup_restart: the draft was started on another phone.
class DatingStartAgainScreen extends ConsumerStatefulWidget {
  const DatingStartAgainScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<DatingStartAgainScreen> createState() =>
      _DatingStartAgainScreenState();
}

class _DatingStartAgainScreenState
    extends ConsumerState<DatingStartAgainScreen> {
  // D8: nothing here outlives the account. The route reads the home per
  // account and shows nothing while the next one loads, so another
  // account always gets a new screen (keys, busy and the refusal with it).
  final DatingActionKeys _keys = DatingActionKeys();
  bool _busy = false;
  DatingLifecycleError? _error;

  Future<void> _startAgain() async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final DatingLifecycleResult r = await ref
        .read(datingLifecycleGatewayProvider)
        .exit(_keys.keyFor('start_again', account), keepNeverIntroduce: true);
    _keys.settle('start_again', error: r.error);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      _error = r.error;
    });
    if (r.ok) {
      ref.invalidate(datingHomeProvider(account));
      context.go(DatingPaths.step('how'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final error = _error;
    return DatingStepFrame(
      step: 'reverify',
      title: loc.flow_slotDatingTitle,
      onBack: widget.onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.dating_reverifyRestart,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.sm),
          // Task 7 (T6 review M-5): a reset keystore makes this phone new.
          Text(
            loc.dating_reverifyRestartWhy,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            loc.dating_reverifyRestartKeeps,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.md),
          if (error != null) ...datingLifecycleErrorRows(context, loc, error),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_startAgain,
        busy: _busy,
        onPressed: online && !_busy ? _startAgain : null,
      ),
    );
  }
}

/// Task 7 (T6 I-4 ruling): this phone has no install id, so nothing can
/// check it: the calm line, and only the way back.
class DatingDeviceUnavailableScreen extends StatelessWidget {
  const DatingDeviceUnavailableScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DatingStepFrame(
      step: 'reverify',
      title: loc.flow_slotDatingTitle,
      onBack: onBack,
      body: DatingCalmLine(loc.dating_deviceUnavailable),
    );
  }
}
