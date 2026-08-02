import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/features/safety/presentation/widgets/triple_tap_detector.dart';
import 'package:attune/home/widgets/home_tab.dart';
import 'package:attune/home/widgets/home_widget_responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bumped whenever code outside HomeScreen's own subtree needs to force an
/// immediate relationship-mode resync — currently only
/// EndRelationshipAction, whose confirm-and-end flow navigates away from
/// Settings (not a descendant of HomeScreen's build method the way
/// AuthenticatedChatWorkspace/_onInviteSent is) immediately after ending a
/// relationship. A plain SharedPreferences write is NOT sufficient on its
/// own: HomeScreen's FutureBuilder watches an already-resolved future
/// (Future of OnboardingStore) that doesn't re-invoke its builder just
/// because an ancestor route rebuilds on a Navigator pop, so a caller with no
/// reference to _HomeScreenState needs an explicit signal, not just a
/// shared-storage write. See docs/superpowers/specs/
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
/// stateless build that read `currentUser` inline both re-created its
/// FutureBuilder future on every rebuild (re-flashing a spinner) and never
/// rebuilt on sign-in/sign-out at all.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _authService = PasswordlessAuthService();
  final _syncService = OnboardingSyncService();

  StreamSubscription<AuthState>? _authSubscription;
  late Future<OnboardingStore> _storeFuture;
  String? _scopeUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scopeUserId = _authService.currentUser?.id;
    _storeFuture = _loadStore();

    // Rebuild (and re-scope the onboarding store) when the user signs in or
    // out, so the shell swaps between the guest and authenticated surfaces
    // without needing a manual navigation.
    _authSubscription = _authService.authStateChanges.listen((_) {
      if (!mounted) return;
      final userId = _authService.currentUser?.id;
      if (userId == _scopeUserId) return;
      setState(() {
        _scopeUserId = userId;
        _storeFuture = _loadStore();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRelationshipMode());
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
    final store = await _storeFuture;
    // mode is null for a signed-in user who hasn't completed onboarding —
    // that's not a relationship-track state either, so it must short
    // circuit here too, not just the explicit `personal` case.
    if (store.mode == null || store.mode == OnboardingMode.personal) return;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final row = await supabase
        .from('relationships')
        .select('status')
        .or('user_a.eq.$userId,user_b.eq.$userId')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final resolved = resolveModeFromRelationshipStatus(row?['status'] as String?);
    if (resolved != store.mode) {
      await store.syncModeFromServer(resolved);
      if (mounted) setState(() => _storeFuture = _loadStore());
    }
  }

  Future<OnboardingStore> _loadStore() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _scopeUserId;
    final scope =
        userId == null || userId.isEmpty
            ? OnboardingStore.anonymousScope
            : '${OnboardingStore.userScopePrefix}.$userId';
    final store = OnboardingStore(prefs, scope: scope);

    // Pay off any onboarding submission that never reached the server (the
    // "we will sync when your connection is stable" promise). Fire-and-forget:
    // the shell must render immediately, and a failed flush keeps the payload
    // for the next launch.
    if (userId != null && userId.isNotEmpty) {
      unawaited(_syncService.flush(store));
    }

    return store;
  }

  /// Persists a personal-mode user's move onto the couplesPending track
  /// (see OnboardingStore.startCouplesInvite's doc) after they generate a
  /// partner invite from ChatCouplesLockedScreen, then reloads the store so
  /// this shell re-reads `mode` and swaps the Chat tab over to the pending
  /// state on the next build. The screen that triggers this has no access
  /// to _storeFuture itself — it lives several widgets below where the
  /// store is owned — so this is threaded down as a callback instead.
  Future<void> _onInviteSent() async {
    final store = await _storeFuture;
    await store.startCouplesInvite();
    if (!mounted) return;
    setState(() {
      _storeFuture = _loadStore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingStore>(
      future: _storeFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        final store = snapshot.data!;
        final isAuthenticated = _authService.currentUser != null;

        if (isAuthenticated && !store.isComplete) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go(RouteNames.onboarding);
          });
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        final isOnboarded = isAuthenticated && store.isComplete;
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
      },
    );
  }
}
