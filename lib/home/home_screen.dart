import 'dart:async';

import 'package:attune/features/relationships/presentation/open_relationship_notice.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/user_timezone_reporter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/core/repositories/repository_helpers.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/home/home_seams.dart';
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
  const HomeScreen({super.key, this.tabRequest});

  /// Spec 1 W3a (§3.11): `/home?tab=chat|me` (homeLocation) opens Tab 2.
  /// The route passes the whole query, so a repeated request (its `n`
  /// differs) opens it again; null when the location asked for no tab.
  final String? tabRequest;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late final HomeAuth _authService = ref.read(homeAuthProvider);
  // Preflight F-4: the v2 replay of a queued A6 goes through the same
  // home-state seam as the rest of the shell.
  late final _syncService = OnboardingSyncService(
    homeStateService: ref.read(homeStateServiceProvider),
  );
  // B3 fix round: the shared seam, so tests can script it.
  late final _inviteService = ref.read(invitePartnerServiceProvider);

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

  /// Spec 1 W3a: the v2 home state for the signed-in account, and the flag.
  ProviderSubscription<HomeSnapshot>? _homeSubscription;
  ProviderSubscription<bool>? _pathsSubscription;

  /// Batch-5 review I-1: the signed-in flags becoming known (a fresh
  /// install's first answer) lets the legacy branch's waiting accept run.
  ProviderSubscription<bool>? _flagsKnownSubscription;

  /// Bumped by each new `/home?tab=` request, so the keyed shell opens Tab 2.
  int _tabRequests = 0;

  /// flow_paths_v2, effective (spec §5.3).
  bool get _pathsV2 => ref.read(flowPathsV2Provider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scopeUserId = _authService.currentUser?.id;
    _gateData = _loadGateDataSync();
    _bindHomeState(null);
    _pathsSubscription = ref.listenManual<bool>(flowPathsV2Provider, (
      previous,
      next,
    ) {
      if (!mounted || previous == next) return;
      setState(() => _gateData = _loadGateDataSync());
      _reconcileGateData();
      // Fix round 1 (review I#1): v2 removed the legacy mode (§5.5); with
      // the flag off again, today's sync rebuilds it now, not next resume.
      if (!next) _syncRelationshipMode();
    });
    _flagsKnownSubscription = ref.listenManual<bool>(flowFlagsKnownProvider, (
      previous,
      next,
    ) {
      // Under flow_paths_v2 the paths listener above reconciles.
      if (!mounted || previous == true || !next || _pathsV2) return;
      _reconcileGateData();
    });
    _reconcileGateData();

    // Rebuild (and re-scope the onboarding store) when the user signs in or
    // out, so the shell swaps between the guest and authenticated surfaces
    // without needing a manual navigation.
    _authSubscription = _authService.authStateChanges.listen((_) {
      if (!mounted) return;
      final userId = _authService.currentUser?.id;
      if (userId == _scopeUserId) return;
      final previousUserId = _scopeUserId;
      setState(() {
        _scopeUserId = userId;
        _gateData = _loadGateDataSync();
      });
      _bindHomeState(previousUserId);
      // Batch-5 review N-2: the next account's stored code gets its RI-3.
      _joinOffered = false;
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
      _reportTimezone();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncRelationshipMode();
      _reportTimezone();
    });
    relationshipModeResyncSignal.addListener(_syncRelationshipMode);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Spec 1 W3a: a new /home?tab= while the shell is up opens Tab 2.
    if (widget.tabRequest != null && widget.tabRequest != oldWidget.tabRequest) {
      _tabRequests++;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    relationshipModeResyncSignal.removeListener(_syncRelationshipMode);
    _authSubscription?.cancel();
    _homeSubscription?.close();
    _pathsSubscription?.close();
    _flagsKnownSubscription?.close();
    super.dispose();
  }

  /// Spec 1 W3a (§5.3): follows the signed-in account's home state; the
  /// account that just signed out forgets its live answer (D20: in memory
  /// only).
  void _bindHomeState(String? previousUserId) {
    _homeSubscription?.close();
    _homeSubscription = null;
    if (previousUserId != null && previousUserId.isNotEmpty) {
      ref.invalidate(homeStateProvider(previousUserId));
    }
    final userId = _scopeUserId;
    if (userId == null || userId.isEmpty) return;
    _homeSubscription = ref.listenManual<HomeSnapshot>(
      homeStateProvider(userId),
      (_, next) {
        if (!mounted || !_pathsV2 || _scopeUserId != userId) return;
        setState(() => _gateData = _v2GateData(_gateData.store, next));
      },
    );
  }

  /// get_my_home_state(), shared with every other reader (deduplicated).
  Future<void> _refreshHomeState() async {
    final userId = _scopeUserId;
    if (userId == null || userId.isEmpty) return;
    await ref.read(homeStateProvider(userId).notifier).refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncRelationshipMode();
      _reportTimezone();
    }
  }

  // Quiet hours follow the phone's zone (Spec 1b). The reporter sends only
  // a changed zone and never throws.
  void _reportTimezone() {
    unawaited(
      ref
          .read(userTimezoneReporterProvider)
          .report(_authService.currentUser?.id),
    );
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
    // Spec 1 W3a: under flow_paths_v2 the home state replaces the mode
    // sync (§5.5), at the same moments.
    if (_pathsV2) {
      await _refreshHomeState();
      return;
    }
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
    // Spec 1 W3a (§5.5): under flow_paths_v2 the home state decides.
    if (_pathsV2 && userId != null && userId.isNotEmpty) {
      return _v2GateData(store, ref.read(homeStateProvider(userId)));
    }
    return _HomeGateData(store: store, isComplete: store.isComplete);
  }

  /// `isComplete` under flow_paths_v2 is "nothing is missing and no hold"
  /// (spec §5.5). Until this phone has any v2 answer for the account, the
  /// legacy flag stands in, so an account that is set up doesn't flash
  /// through /onboarding; the first server answer then decides.
  _HomeGateData _v2GateData(OnboardingStore store, HomeSnapshot home) =>
      _HomeGateData(
        store: store,
        isComplete: home.known ? home.isComplete : store.isComplete,
        home: home,
      );

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

    // Spec 1 W3a: under flow_paths_v2 the queued A5 and A6 are replayed
    // first, then the server's home state decides (it can also close the
    // home again: a new need, a hold).
    if (_pathsV2) {
      final home = ref.read(homeStateProvider(userId).notifier);
      try {
        await _syncService
            .flush(store, onPathSynced: home.apply)
            .timeout(const Duration(seconds: 20));
      } catch (_) {}
      if (!mounted || _scopeUserId != userId) return;
      await _refreshHomeState();
      if (!mounted || _scopeUserId != userId) return;
      // Ruling (B3 fix round, D9/§5.2/§3.14): a stored invite waits for a
      // complete account on the server (its name and date of birth); until
      // then the v2 gate accepts it, after the name.
      if (store.pendingInviteCode != null &&
          store.pendingSignUp == null &&
          ref.read(homeStateProvider(userId)).isComplete) {
        // Spec 1 W4b (D9): under flow_couples_v2 a stored code is joined
        // only from RI-3, after an explicit tap; never here.
        if (ref.read(flowCouplesV2Provider)) {
          await _openJoinInvite();
          return;
        }
        await _acceptPendingInvite(store);
        await _refreshHomeState();
      }
      return;
    }

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
    // Batch-5 review I-1 (D9): never while the signed-in flags are unknown
    // (unknown is not off); the code waits, and the flags' first answer
    // reconciles again (_flagsKnownSubscription).
    if (store.pendingInviteCode != null && ref.read(flowFlagsKnownProvider)) {
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

  /// RI-3 for a stored code, once per HomeScreen (flow_couples_v2), while
  /// home is the screen on top.
  bool _joinOffered = false;

  Future<void> _openJoinInvite() async {
    if (_joinOffered || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _joinOffered = true;
    unawaited(GoRouter.of(context).push(RouteNames.joinInvite));
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
      // Sync audit I-8: already in a relationship (active or paused) —
      // say why the link did nothing; nothing was ended.
      if (error.alreadyInRelationship) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showOpenRelationshipNotice(context, error.message);
        });
      }
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
    // Spec 1 W3a: under flow_paths_v2 the server knows; ask it.
    if (_pathsV2) {
      await _refreshHomeState();
      return;
    }
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

    // Spec 1 W3a (§3.11): under flow_paths_v2, Tab 2 is Chat or Me by the
    // home state's layout (the legacy mode stands in until it is known).
    final homeState = _gateData.home;
    final AppTab? layout =
        homeState == null || !isOnboarded
            ? null
            : homeState.tab ??
                (isRelationshipTrack ? AppTab.chat : AppTab.me);
    final loc = AppLocalizations.of(context)!;
    // Fix round 1 (ruling): until this phone has any v2 answer, the couple
    // link comes from the legacy mode, so an active couple keeps the chat.
    final tabTwoHome =
        homeState == null || homeState.known
            ? homeState
            : HomeSnapshot(
              link:
                  isActiveCouples
                      ? LinkState.linked
                      : isRelationshipTrack
                      ? LinkState.pending
                      : LinkState.none,
              needs: homeState.needs,
              hold: homeState.hold,
            );

    // Default tab: Opinions (0) for single/personal, Chat (1) for active
    // couples. Spec 1 W3a: Tab 2 for everyone signed in under
    // flow_paths_v2, and whenever /home?tab= asked for it.
    final initialTabIndex =
        layout != null ||
                widget.tabRequest != null ||
                (isOnboarded && isActiveCouples)
            ? 1
            : 0;

    final tabs = [
      HomeTab(
        id: 'opinions',
        label: 'Opinions',
        icon: Icons.forum_outlined,
        activeIcon: Icons.forum,
        screen: ref.watch(homeOpinionsTabProvider),
      ),
      HomeTab(
        id: layout == AppTab.me ? 'me' : 'chat',
        // Spec 1 §3.2 G2: a guest's Tab 2 is "Sign in" under flow_signin_v2
        // (preflight F-5: guests only, not a signed-in account mid-setup).
        label:
            layout == AppTab.me
                ? loc.flow_tabMe
                : !isAuthenticated && ref.watch(signInFlowV2Provider)
                ? loc.flow_tabSignIn
                : 'Chat',
        icon:
            layout == AppTab.me
                ? Icons.person_outline
                : Icons.chat_bubble_outline,
        activeIcon: layout == AppTab.me ? Icons.person : Icons.chat_bubble,
        screen:
            isOnboarded
                ? layout != null
                    ? ref.watch(homeTabTwoBuilderProvider)(
                      layout,
                      tabTwoHome!,
                      _onInviteSent,
                    )
                    : AuthenticatedChatWorkspace(
                      isCouples: isActiveCouples,
                      isPendingCouples: isRelationshipTrack && !isActiveCouples,
                      onInviteSent: _onInviteSent,
                    )
                : const LoginProfile(),
      ),
    ];

    final home = KeyedSubtree(
      // Spec 1 W3a (§3.11): HomeWidget reads initialTabIndex only once, so a
      // new layout (Chat <-> Me) rebuilds the shell; a link change, or
      // Dating <-> Just for me (both Me), keeps it. A /home?tab= request
      // selects Tab 2 in place (fix round 1, review minor #5).
      key: ValueKey('home-${layout?.wire ?? 'legacy'}'),
      child: HomeWidgetResponsive.adaptive(
        context: context,
        tabs: tabs,
        initialTabIndex: initialTabIndex,
        reselectToken: _tabRequests,
      ),
    );

    if (!isAuthenticated) {
      return home;
    }

    // Quick exit lives in the root shell now (Spec 2: one target, every route).
    return home;
  }
}

class _HomeGateData {
  const _HomeGateData({
    required this.store,
    required this.isComplete,
    this.home,
  });

  final OnboardingStore store;
  final bool isComplete;

  /// Spec 1 W3a: the v2 home state, under flow_paths_v2 only.
  final HomeSnapshot? home;
}
