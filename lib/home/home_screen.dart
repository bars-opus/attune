import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/core/repositories/repository_helpers.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/safety/presentation/widgets/triple_tap_detector.dart';
import 'package:attune/home/widgets/home_tab.dart';
import 'package:attune/home/widgets/home_widget_responsive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bumped whenever code outside HomeScreen's own subtree needs to force an
/// immediate relationship-mode resync — currently only
/// EndRelationshipAction, whose confirm-and-end flow navigates away from
/// Settings (not a descendant of HomeScreen's build method the way
/// AuthenticatedChatWorkspace/_onInviteSent is) immediately after ending a
/// relationship. A plain SharedPreferences write is NOT sufficient on its
/// own: HomeScreen's build() reads _gateData, a plain field that only
/// changes via setState — an ancestor route rebuilding on a Navigator pop
/// does not itself trigger that setState, so a caller with no reference to
/// _HomeScreenState needs an explicit signal, not just a shared-storage
/// write. See docs/superpowers/specs/
/// 2026-08-02-relationship-lifecycle-sync-design.md §1/§3.
final relationshipModeResyncSignal = ValueNotifier<int>(0);

/// The app shell: an anonymous-browsable two-tab home (Opinions + Chat).
///
/// Guests see the Opinions feed and a sign-in surface in the Chat tab. Once the
/// user authenticates, this rebuilds and routes them into onboarding if it is
/// not yet complete; after that the Chat tab becomes the real workspace.
///
/// Stateful (not Stateless) on purpose: the onboarding store must be loaded
/// ONCE per auth identity, and the shell must REBUILD when auth flips. A
/// stateless build that read `currentUser` inline both re-derived its gate
/// data on every rebuild and never rebuilt on sign-in/sign-out at all.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _authService = PasswordlessAuthService();
  final _syncService = OnboardingSyncService();
  final _inviteService = RelationshipInviteService();

  StreamSubscription<AuthState>? _authSubscription;

  /// The gate's current, always-renderable data — seeded synchronously from
  /// local SharedPreferences on every load (see _loadGateDataSync), then
  /// upgraded in place once the background server reconcile
  /// (resolveIsComplete) resolves. Never null after the first frame: unlike
  /// the old FutureBuilder<_HomeGateData> gate, there is no "waiting on the
  /// network" state for build() to render a spinner for — the local flag is
  /// always immediately available, so this shell paints on the same frame
  /// as any other screen instead of blocking behind a Supabase round trip
  /// on every cold launch and every sign-in/out remount.
  late _HomeGateData _gateData;
  String? _scopeUserId;

  /// Latches the one-shot redirect into onboarding — see its use in build().
  bool _redirectingToOnboarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scopeUserId = _authService.currentUser?.id;
    _gateData = _loadGateDataSync();
    _reconcileGateData();

    // Rebuild (and re-scope the onboarding store) when the user signs in or
    // out, so the shell swaps between the guest and authenticated surfaces
    // without needing a manual navigation.
    _authSubscription = _authService.authStateChanges.listen((_) {
      if (!mounted) return;
      final userId = _authService.currentUser?.id;
      if (userId == _scopeUserId) return;
      setState(() {
        _scopeUserId = userId;
        _gateData = _loadGateDataSync();
      });
      _reconcileGateData();
      // Signing in is the single most important moment to reconcile the
      // relationship mode, and it used to be the one moment that didn't.
      // The post-frame call in initState below runs while the user is
      // still signed out (no userId -> immediate return), so without this
      // a sign-in on a fresh install left `mode` null — stranding a user
      // whose relationship is active on the server behind the
      // invite/pairing screen until an unrelated app resume happened to
      // fire the sync. The store was just re-scoped to the new user above,
      // so this reads and writes the right scope.
      _syncRelationshipMode();
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncRelationshipMode(),
    );
    relationshipModeResyncSignal.addListener(_syncRelationshipMode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    relationshipModeResyncSignal.removeListener(_syncRelationshipMode);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncRelationshipMode();
  }

  /// Reconciles the locally-cached OnboardingMode against the server's
  /// relationships.status, in both directions: a partner accepting an
  /// invite (pending -> active) and either partner ending a relationship
  /// (active -> ended). This is the self-healing half of the fix — it
  /// runs independent of whether a push notification was delivered,
  /// tapped, or missed entirely, so the worst case is "found out when you
  /// next open the app" rather than "never found out." See design spec
  /// docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md
  /// §1.
  Future<void> _syncRelationshipMode() async {
    // Called from an unawaited addPostFrameCallback/lifecycle listener with
    // no caller to report to — an uncaught exception here (network blip,
    // timeout) previously vanished into an unhandled Future entirely,
    // silently leaving the couples-locked screen showing forever with no
    // visible error and no retry until the next resume/launch happened to
    // succeed.
    try {
      final store = _gateData.store;
      // No local mode is short-circuited here — reconciliation always asks
      // the server. Two earlier guards each created a permanent trap:
      //
      //   `personal` short-circuit: a bad cached `personal` (written by
      //   OnboardingStore.resolveIsComplete's old local backfill,
      //   `mode ?? OnboardingMode.personal`) meant the query below never
      //   ran, so a real active relationship could never self-heal.
      //
      //   `null` short-circuit: a fresh install / cleared prefs / sign-in
      //   on a new device has NO local mode, which is exactly when the
      //   server is the only thing that knows the user is in a
      //   relationship. resolveIsComplete deliberately no longer invents a
      //   mode (see its doc), leaving it null until "something that
      //   actually knows the real value" sets it — this sync IS that
      //   something, so returning early here left the user stranded on the
      //   invite/pairing screen for a relationship they never ended.
      //
      // The signed-out case is already handled by the userId check below,
      // which is the only state with genuinely nothing to reconcile.
      // Querying every launch/resume costs one indexed read, which is
      // cheap next to "couples chat never unlocks."

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Wrapped in the shared repo helper for a per-attempt timeout,
      // retry-on-transient (it does NOT retry auth/validation failures),
      // and structured logging — checklist 1.2/3.9/3.10. This matters more
      // now that the query runs on EVERY launch, resume, and sign-in
      // rather than only when a mode was already cached: an untimed call
      // on a dead network would otherwise hang this reconciliation
      // indefinitely.
      final row = await runRepoQuery(
        () => supabase
            .from('relationships')
            .select('status')
            .or('user_a.eq.$userId,user_b.eq.$userId')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        opName: 'syncRelationshipMode',
        // Never surfaced: this is a background reconciliation with no
        // user-visible failure path (the catch below swallows it and the
        // next launch/resume retries). Required by the helper's signature.
        userMessage: 'Could not check your relationship status.',
      );

      // The store was captured before the await above, but auth can change
      // while the query is in flight (sign-out, or switching accounts).
      // Writing the resolved mode into a store still scoped to the
      // previous user would persistently corrupt THAT user's cached mode,
      // so re-verify the scope still matches the user this result is
      // about before committing it.
      if (!mounted || _scopeUserId != userId) return;

      final resolved = resolveModeFromRelationshipStatus(
        row?['status'] as String?,
      );
      if (resolved != store.mode) {
        await store.syncModeFromServer(resolved);
        // store.mode is a live SharedPreferences read, not a field cached on
        // _gateData — the write above is already visible on the next read,
        // this setState just forces build() to run that read again.
        if (mounted) setState(() {});
      }
    } catch (error) {
      debugPrint('[home] relationship mode sync failed: ${error.runtimeType}');
    }
  }

  /// Synchronous, local-only gate data — no network, no await, safe to call
  /// straight out of initState/setState so the very first frame renders the
  /// real shell instead of a spinner. `isComplete` here is OnboardingStore's
  /// bare local flag, which resolveIsComplete's doc explains can be wrong in
  /// exactly one direction: false when the server would say true (onboarded
  /// on another device/install). It can never be wrong the other way — a
  /// local `true` is written only by this device's own completed flow or a
  /// prior server confirmation, so it's always safe to trust immediately.
  /// _reconcileGateData below is what upgrades a false into a true.
  _HomeGateData _loadGateDataSync() {
    final prefs = ref.read(sharedPreferencesProvider);
    final userId = _scopeUserId;
    final scope =
        userId == null || userId.isEmpty
            ? OnboardingStore.anonymousScope
            : '${OnboardingStore.userScopePrefix}.$userId';
    final store = OnboardingStore(prefs, scope: scope);
    return _HomeGateData(store: store, isComplete: store.isComplete);
  }

  /// Background upgrade of the synchronously-seeded _gateData: pays off any
  /// pending onboarding submission, retries a stashed invite code, and —
  /// only when the local flag says NOT complete — asks the server whether
  /// this account actually finished onboarding elsewhere (resolveIsComplete
  /// beats the local read: see its own doc for why "false" is the one
  /// direction that can't be trusted). A locally-complete flag is already
  /// maximally trusted (see _loadGateDataSync) and skips the network call
  /// entirely — nothing about the shell can regress from true to false, so
  /// there's nothing to reconcile.
  Future<void> _reconcileGateData() async {
    final store = _gateData.store;
    final userId = _scopeUserId;

    if (userId == null || userId.isEmpty) return;

    // Fire-and-forget: the shell has already rendered, and a failed flush
    // keeps the payload for the next launch.
    unawaited(_syncService.flush(store));

    // A pending invite code can outlive the /onboarding visit that stashed
    // it — e.g. the app was killed after main.dart's deep-link handler
    // stored the code but before OnboardingGate/OnboardingFlow ever
    // consumed it. Every real HomeScreen load (launch, resume, sign-in —
    // see didChangeAppLifecycleState/_authSubscription above) is a chance
    // to retry it here, the same way OnboardingGate does for a visitor who
    // arrives already authenticated. Best-effort: a failure just leaves the
    // code for the next load rather than blocking the shell — already not
    // blocking the first paint now that this runs after render, not before.
    if (store.pendingInviteCode != null) {
      await _acceptPendingInvite(store);
    }

    if (_gateData.isComplete) return;

    final resolved = await store.resolveIsComplete(userId);
    if (resolved && mounted && _scopeUserId == userId) {
      setState(() {
        _gateData = _HomeGateData(store: store, isComplete: true);
      });
    }
  }

  /// Mirrors OnboardingGate's own _acceptPendingInvite — kept as a
  /// duplicate rather than a shared helper since the two call sites own
  /// their OnboardingStore instances independently and neither is in a
  /// position to depend on the other's widget tree.
  Future<void> _acceptPendingInvite(OnboardingStore store) async {
    final code = store.pendingInviteCode;
    if (code == null) return;
    try {
      await _inviteService.acceptInvite(code);
      await store.clearPendingInviteCode();
    } on RelationshipInviteException catch (error) {
      // Deterministic rejections (expired/self/already-accepted/invalid)
      // can never succeed on retry — drop the stale code so it doesn't
      // resurface on every future launch/resume. Transient failures
      // (retryable) keep the code so the next load tries again.
      if (!error.retryable) await store.clearPendingInviteCode();
    } catch (_) {
      // Unreachable client/network failure — leave the code in place for
      // a later retry rather than silently discarding a real invite.
    }
  }

  /// Persists a personal-mode user's move onto the couplesPending track
  /// (see OnboardingStore.startCouplesInvite's doc) after they generate a
  /// partner invite from ChatCouplesLockedScreen, then triggers a rebuild so
  /// this shell re-reads `mode` (a live SharedPreferences getter — see
  /// _syncRelationshipMode's own setState) and swaps the Chat tab over to
  /// the pending state. The screen that triggers this has no access to
  /// _gateData itself — it lives several widgets below where the store is
  /// owned — so this is threaded down as a callback instead.
  Future<void> _onInviteSent() async {
    await _gateData.store.startCouplesInvite();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _gateData.store;
    final isAuthenticated = _authService.currentUser != null;

    if (isAuthenticated && !_gateData.isComplete) {
      // _gateData.isComplete starts as the LOCAL flag (_loadGateDataSync)
      // and only flips true once _reconcileGateData's server-truth check
      // (resolveIsComplete) confirms it — so this still genuinely waits on
      // the network for exactly the one case that can be wrong (a returning
      // user onboarded on another device/install), while every other case
      // (anonymous, or already locally complete) skips this branch and
      // paints the real shell on the very first frame.
      //
      // Latched and route-guarded. Unlatched, this fired a fresh
      // context.go on EVERY rebuild — and HomeScreen rebuilds while it
      // is still buried under the login sheet, so a sign-in produced a
      // storm of repeated /onboarding redirects that tore down the
      // EULA sheet's own context mid-await. isCurrent keeps this from
      // redirecting a route the user isn't even looking at; the latch
      // keeps one redirect from becoming eighteen.
      if (!_redirectingToOnboarding &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        _redirectingToOnboarding = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go(RouteNames.onboarding);
        });
      }
      return const Scaffold(body: Center(child: CircularLoadingIndicator()));
    }
    _redirectingToOnboarding = false;

    final isOnboarded = isAuthenticated && _gateData.isComplete;
    final mode = store.mode;
    final isActiveCouples = mode == OnboardingMode.couples;
    final isRelationshipTrack = mode?.isRelationshipTrack ?? false;

    // Default tab: Opinions (0) for single/personal, Chat (1) for active couples
    final initialTabIndex = isOnboarded && isActiveCouples ? 1 : 0;

    final tabs = [
      const HomeTab(
        id: 'opinions',
        label: 'Opinions',
        icon: Icons.forum_outlined,
        activeIcon: Icons.forum,
        screen: OpinionsTab(),
      ),
      HomeTab(
        id: 'chat',
        label: 'Chat',
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        screen:
            isOnboarded
                ? AuthenticatedChatWorkspace(
                  isCouples: isActiveCouples,
                  isPendingCouples: isRelationshipTrack && !isActiveCouples,
                  onInviteSent: _onInviteSent,
                )
                : const LoginProfile(),
      ),
    ];

    final home = HomeWidgetResponsive.adaptive(
      context: context,
      tabs: tabs,
      initialTabIndex: initialTabIndex,
    );

    if (!isAuthenticated) {
      return home;
    }

    return TripleTapDetector(child: home);
  }
}

class _HomeGateData {
  const _HomeGateData({required this.store, required this.isComplete});

  final OnboardingStore store;
  final bool isComplete;
}
