import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/features/safety/presentation/widgets/triple_tap_detector.dart';
import 'package:attune/home/widgets/home_tab.dart';
import 'package:attune/home/widgets/home_widget_responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingStore>(
      future: _loadStore(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        final store = snapshot.data!;
        final isAuthenticated = PasswordlessAuthService().currentUser != null;

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
          // Opinions tab - NOW using our full OpinionsTab with sub-tabs
          const HomeTab(
            id: 'opinions',
            label: 'Opinions',
            icon: Icons.forum_outlined,
            activeIcon: Icons.forum,
            screen: OpinionsTab(),
          ),

          //         const HomeTab(
          //   id: 'pulse',
          //   label: 'Pulse',
          //   icon: Icons.show_chart_outlined,
          //   activeIcon: Icons.show_chart,
          //   screen: PulseTab(),
          // ),

          // const HomeTab(
          //     id: 'games',
          //     label: 'Games',
          //     icon: Icons.sports_esports_outlined,
          //     activeIcon: Icons.sports_esports,
          //     screen: GamesTab(),
          //   ),
          //   const HomeTab(
          //     id: 'insights',
          //     label: 'Insights',
          //     icon: Icons.lightbulb_outline,
          //     activeIcon: Icons.lightbulb,
          //     screen: InsightsTab(),
          //   ),
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

  Future<OnboardingStore> _loadStore() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = PasswordlessAuthService().currentUser?.id;
    final scope =
        userId == null || userId.isEmpty
            ? OnboardingStore.anonymousScope
            : '${OnboardingStore.userScopePrefix}.$userId';
    return OnboardingStore(prefs, scope: scope);
  }
}
