import 'package:attune/app/app_info/app_info_screen.dart';
import 'package:attune/app/documentations/legal_documentation/widgets/all_legal_documentations_screen.dart';
import 'package:attune/app/licenses_screen.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/moderation/presentation/screens/blocked_accounts_screen.dart';
import 'package:attune/features/auth/intro/intro_screen.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_knockout_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_lobby_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_channel_loader.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/profile/widgets/profile_screen.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/features/settings/screens/language_screen.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/features/settings/screens/theme_screen.dart';
import 'package:attune/home/home_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteNames {
  static const String intro = '/intro';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String language = '/language';
  static const String theme = '/theme';
  static const String allLegalDocumentation = '/allLegalDocumentation';
  static const String appInfoScreen = '/appInfoScreen';
  static const String licenses = '/licenses';
  static const String safetyResources = SafetyResourcesScreen.routeName;

  static const String splash = '/splash';
  static const String more = '/more';
  static const String login = '/login';
  static const String onboarding = '/onboarding';
  static const String loginOptions = '/loginOptions';
  static const String search = '/search';
  static const String chatScreen = '/chatScreen';
  static const String chatChannel = '/chat-channel';
  static const String editScreen = '/editScreen';
  static const String createUsername = '/createUsername';
  static const String verifyEmail = '/verifyEmail';
  static const String forgotPassword = '/forgot-password';
  static const String profileScreen = '/profile';
  static const String locationSearchScreen = '/locationSearchScreen';
  static const String nearYouShopsScreen = '/nearYouShopsScreen';
  static const String topRatedShopsScreen = '/topRatedShopsScreen';
  static const String premiumShopsScreen = '/premiumShopsScreen';
  static const String shopDetailsScreen = '/shopDetailsScreen';
  static const String calendar = '/calendar';
  static const String editBasics = '/editBasics';
  static const String editLocation = '/editLocation';
  static const String freelancerLocation = '/freelancerLocation';
  static const String setHours = '/setHours';
  static const String manageServices = '/manageServices';
  static const String manageMedia = '/manageMedia';
  static const String previewShop = '/previewShop';
  static const String editShop = '/editShop';
  static const String shopCreation = '/shopCreation';
  static const String manageSocialLinks = '/manageSocialLinks';
  static const String manageAmenities = '/manageAmenities';
  static const String manageDocuments = '/manageDocuments';
  static const String manageAwards = '/manageAwards';
  static const String manageContacts = '/manageContacts';
  static const String draftsScreen = '/draftsScreen';
  static const String appointmentAssignWorkersScreen =
      '/appointmentAssignWorkersScreen';
  static const String shopReviewsScreen = '/shopReviewsScreen';
  static const String allShopWorkersScreen = '/allShopWorkersScreen';
  static const String ownerDashboardScreen = '/ownerDashboardScreen';
  static const String shopScheduleHub = '/shopScheduleHub';
  static const String paystackConnectionScreen = '/paystackConnectionScreen';
  static const String paymentSettingsScreen = '/paymentSettingsScreen';
  static const String freelancerCreationDashboard =
      '/freelancerCreationDashboard';
  static const String freelancerBasicsScreen = '/freelancerBasicsScreen';
  static const String freelancerToolsScreen = '/freelancerToolsScreen';
  static const String myShopsScreen = '/myShopsScreen';
  static const String freelancerDetailsScreen = '/freelancerDetailsScreen';
  static const String freelancerPreviewScreen = '/freelancerPreviewScreen';
  static const String topRatedFreelancersScreen = '/topRatedFreelancersScreen';
  static const String nearYouFreelancersScreen = '/nearYouFreelancersScreen';
  static const String updatePasswordScreen = '/updatePasswordScreen';
  static const String passwordResetSentScreen = '/passwordResetSentScreen';
  static const String marketplace = '/marketplace';
  static const String productDetail = '/productDetail';
  static const String cart = '/cart';
  static const String checkout = '/checkout';
  static const String orderConfirmation = '/orderConfirmation';
  static const String customerOrders = '/customerOrders';
  static const String customerOrderDetail = '/customerOrderDetail';
  static const String shopOrders = '/shopOrders';
  static const String shopOrderDetail = '/shopOrderDetail';
  static const String shopProducts = '/shopProducts';
  static const String productForm = '/productForm';
  static const String blockedAccountsScreen = '/blockedAccountsScreen';
  static const String datingMode = '/dating-mode';
}

GoRouter createAppRouter(RoutingNotifier routingNotifier) {
  return GoRouter(
    debugLogDiagnostics: kDebugMode,
    initialLocation: '/_invisible',
    refreshListenable: routingNotifier,
    redirect: (context, state) {
      if (state.matchedLocation == '/_invisible') {
        return routingNotifier.isFirstLaunch
            ? RouteNames.intro
            : RouteNames.home;
      }

      if (routingNotifier.isFirstLaunch &&
          state.matchedLocation != RouteNames.intro) {
        return RouteNames.intro;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/_invisible',
        builder: (context, state) => const _InvisibleRoute(),
      ),
      GoRoute(
        path: RouteNames.intro,
        name: 'intro',
        builder: (context, state) => const IntroScreen(),
      ),
      GoRoute(
        path: RouteNames.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        name: 'onboarding',
        builder: (context, state) {
          final previewOnboarding = kDebugMode && state.extra == true;
          return OnboardingGate(previewOnboarding: previewOnboarding);
        },
      ),
      GoRoute(
        path: RouteNames.profileScreen,
        name: 'profile',
        builder: (context, state) {
          final currentUserId = state.extra as String? ?? _currentUserId();
          return ProfileScreen(
            currentUserId: currentUserId,
            profileUserId: currentUserId,
          );
        },
      ),
      GoRoute(
        path: RouteNames.chatScreen,
        name: 'chatScreen',
        builder: (context, state) {
          final conversation = state.extra as Conversation?;
          if (conversation == null) {
            return const Scaffold(
              body: Center(child: Text('Conversation unavailable.')),
            );
          }
          return ChatScreen(conversation: conversation);
        },
      ),
      GoRoute(
        path: RouteNames.chatChannel,
        name: 'chatChannel',
        builder: (context, state) {
          final relationshipId = state.uri.queryParameters['relationshipId'] ?? '';
          return ChatChannelLoader(relationshipId: relationshipId);
        },
      ),
      GoRoute(
        path: RouteNames.settings,
        name: 'settings',
        builder: (context, state) {
          final currentUserId = state.extra as String? ?? _currentUserId();
          return SettingsScreen(currentUserId: currentUserId);
        },
      ),
      GoRoute(
        path: RouteNames.language,
        name: 'language',
        pageBuilder:
            (context, state) =>
                MaterialPage(key: state.pageKey, child: const LanguageScreen()),
      ),

      GoRoute(
        path: RouteNames.theme,
        name: 'theme',
        pageBuilder:
            (context, state) =>
                MaterialPage(key: state.pageKey, child: const ThemeScreen()),
      ),
      GoRoute(
        path: RouteNames.licenses,
        name: 'licenses',
        builder: (context, state) => const LicensesScreen(),
      ),
      GoRoute(
        path: RouteNames.safetyResources,
        name: 'safetyResources',
        builder: (context, state) => const SafetyResourcesScreen(),
      ),
      GoRoute(
        path: RouteNames.allLegalDocumentation,
        name: 'allLegalDocumentation',
        builder: (context, state) => const AllLegalDocumentationsScreen(),
      ),
      GoRoute(
        path: RouteNames.appInfoScreen,
        name: 'appInfoScreen',
        builder: (context, state) => const AppInfoScreen(),
      ),

      GoRoute(
        path: RouteNames.blockedAccountsScreen,
        name: 'blockedAccountsScreen',
        builder: (context, state) => const BlockedAccountsScreen(),
      ),
      GoRoute(
        path: RouteNames.datingMode,
        name: 'datingMode',
        builder: (context, state) => const DatingDashboardScreen(),
      ),
       GoRoute(
    path: '/games/paint-ball/lobby/:relationshipId',
    builder: (context, state) {
      final relationshipId = state.pathParameters['relationshipId']!;
      return PaintBallLobbyScreen(relationshipId: relationshipId);
    },
  ),
  GoRoute(
    path: '/games/paint-ball/battle/:sessionId',
    builder: (context, state) {
      final sessionId = state.pathParameters['sessionId']!;
      return PaintBallBattleScreen(sessionId: sessionId);
    },
  ),
  GoRoute(
    path: '/games/paint-ball/knockout/:sessionId',
    builder: (context, state) {
      final sessionId = state.pathParameters['sessionId']!;
      return PaintBallKnockoutScreen(sessionId: sessionId);
    },
  ),
    ],
  );
}

String _currentUserId() {
  try {
    return Supabase.instance.client.auth.currentUser?.id ?? '';
  } catch (_) {
    return '';
  }
}

class _InvisibleRoute extends StatelessWidget {
  const _InvisibleRoute();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}
