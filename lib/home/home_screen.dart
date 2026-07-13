import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/features/safety/presentation/widgets/triple_tap_detector.dart';
import 'package:attune/home/widgets/home_tab.dart';
import 'package:attune/home/widgets/home_widget_responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  final _authService = PasswordlessAuthService();
  final _syncService = OnboardingSyncService();

  StreamSubscription<AuthState>? _authSubscription;
  late Future<OnboardingStore> _storeFuture;
  String? _scopeUserId;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
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
