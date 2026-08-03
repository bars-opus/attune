import 'package:attune/app/app_info/app_info_screen.dart';
import 'package:attune/app/documentations/legal_documentation/widgets/all_legal_documentations_screen.dart';
import 'package:attune/app/licenses_screen.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/features/onboarding/presentation/screens/ask2_flow.dart';
import 'package:attune/core/moderation/presentation/screens/blocked_accounts_screen.dart';
import 'package:attune/features/opinions/presentation/screen/muted_authors_screen.dart';
import 'package:attune/features/auth/intro/intro_screen.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_battle_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_knockout_screen.dart';
import 'package:attune/features/games/paint_ball/presentation/screens/paint_ball_lobby_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/screens/debate_room_screen.dart';
import 'package:attune/features/forums/presentation/screens/forum_insight_screen.dart';
import 'package:attune/features/forums/presentation/screens/side_selection_screen.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_channel_loader.dart';
import 'package:attune/features/chat/presentation/screens/chat_import_screen.dart';
import 'package:attune/features/chat/presentation/screens/chat_insights_screen.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_journey_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/reflection_journal_screen.dart';
import 'package:attune/features/pulse/presentation/screens/checkin_complete_screen.dart';
import 'package:attune/features/pulse/presentation/screens/pulse_screen.dart';
import 'package:attune/features/pulse/presentation/screens/weekly_checkin_screen.dart';
import 'package:attune/features/reminders/presentation/screens/couples_calendar_screen.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_type_screen.dart';
import 'package:attune/features/games/presentation/screens/games_hub_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_completion_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_history_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_introduction_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_invitation_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_journey_completion_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_question_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_reveal_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_waiting_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/custom_truth_or_dare_create_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/custom_truth_or_dare_list_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_game_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_history_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_session_router_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_tone_selector_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_reveal_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/dare_reveal_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_journey_overview_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/custom_question_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/custom_question_list_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_detail_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_history_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_create_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_custom_list_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_games_hub_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/tone_selector_screen.dart';
import 'package:attune/features/community/presentation/screens/community_feed_screen.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/screens/attachment_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/communication_style_loading_screen.dart';
import 'package:attune/features/quiz/presentation/screens/communication_style_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/communication_style_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/conflict_style_loading_screen.dart';
import 'package:attune/features/quiz/presentation/screens/conflict_style_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/conflict_style_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_loading_screen.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_entry_screen.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_loading_screen.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/partner_quiz_result_screen.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/screens/healing_stage_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_consent_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_guided_date_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_matches_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_profile_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_photos_screen.dart';
import 'package:attune/features/dating/presentation/screens/dating_verification_screen.dart';
import 'package:attune/features/profile/widgets/profile_screen.dart';
import 'package:attune/core/notifications/presentation/screens/notification_inbox_screen.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
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
  static const String mutedAuthorsScreen = '/mutedAuthorsScreen';
  static const String datingMode = '/dating-mode';
  static const String ask2Flow = '/ask2/:relationshipId';
  static const String anonymousProfile = '/anonymousProfile';
  static const String commentThread = '/commentThread';
  static const String editOpinion = '/editOpinion';
  static const String quoteCompose = '/quoteCompose';
  static const String tagBrowse = '/tagBrowse';
  static const String debateRoom = '/debateRoom';
  static const String sideSelection = '/sideSelection';
  static const String forumInsight = '/forumInsight';
  static const String healingJourney = '/healingJourney';
  static const String reflectionJournal = '/reflectionJournal';
  static const String journalEntryCompose = '/journalEntryCompose';
  static const String journalEntryDetail = '/journalEntryDetail';
  static const String pulse = '/pulse';
  static const String couplesCalendar = '/couples-calendar';
  static const String addEditReminder = '/couples-calendar/add';
  static const String familyMembers = '/couples-calendar/family';
  static const String chatInsights = '/chatInsights';
  static const String chatImport = '/chatImport';
  static const String weeklyCheckin = '/weeklyCheckin';
  static const String checkinComplete = '/checkinComplete';
  static const String logMomentType = '/logMomentType';
  static const String quizEntry = '/quizEntry';
  static const String attachmentQuiz = '/attachmentQuiz';
  static const String attachmentQuizLoading = '/attachmentQuizLoading';
  static const String attachmentQuizResult = '/attachmentQuizResult';
  static const String conflictStyleQuiz = '/conflictStyleQuiz';
  static const String conflictStyleLoading = '/conflictStyleLoading';
  static const String conflictStyleResult = '/conflictStyleResult';
  static const String loveLanguageQuiz = '/loveLanguageQuiz';
  static const String loveLanguageLoading = '/loveLanguageLoading';
  static const String loveLanguageResult = '/loveLanguageResult';
  static const String communicationStyleQuiz = '/communicationStyleQuiz';
  static const String communicationStyleLoading = '/communicationStyleLoading';
  static const String communicationStyleResult = '/communicationStyleResult';
  static const String partnerQuizResult = '/partnerQuizResult';
  static const String healingStage = '/healingStage';
  static const String datingConsent = '/datingConsent';
  static const String datingProfile = '/datingProfile';
  static const String datingMatches = '/datingMatches';
  static const String datingGuidedDate = '/datingGuidedDate';
  static const String datingPhotos = '/datingPhotos';
  static const String datingVerification = '/datingVerification';
  static const String logMomentDetails = '/logMomentDetails';
  static const String gamesHub = '/gamesHub';
  static const String thirtySixChapterInvitation =
      '/thirtySixChapterInvitation';
  static const String thirtySixChapterIntroduction =
      '/thirtySixChapterIntroduction';
  static const String thirtySixQuestion = '/thirtySixQuestion';
  static const String thirtySixChapterCompletion =
      '/thirtySixChapterCompletion';
  static const String thirtySixWaiting = '/thirtySixWaiting';
  static const String thirtySixReveal = '/thirtySixReveal';
  static const String thirtySixJourneyCompletion =
      '/thirtySixJourneyCompletion';
  static const String thirtySixChapterHistory = '/thirtySixChapterHistory';
  static const String truthOrDareGame = '/truthOrDareGame';
  static const String truthOrDareToneSelector = '/truthOrDareToneSelector';
  static const String truthOrDareSessionRouter = '/truthOrDareSessionRouter';
  static const String customTruthOrDareList = '/customTruthOrDareList';
  static const String customTruthOrDareCreate = '/customTruthOrDareCreate';
  static const String truthOrDareHistory = '/truthOrDareHistory';
  static const String truthReveal = '/truthReveal';
  static const String dareReveal = '/dareReveal';
  static const String thirtySixJourneyOverview = '/thirtySixJourneyOverview';
  static const String communityFeed = '/communityFeed';
  static const String thisOrThatGamesHub = '/thisOrThatGamesHub';
  static const String thisOrThatToneSelector = '/thisOrThatToneSelector';
  static const String thisOrThatSessionRouter = '/thisOrThatSessionRouter';
  static const String customQuestionList = '/customQuestionList';
  static const String customQuestionCreate = '/customQuestionCreate';
  static const String thisOrThatSessionHistory = '/thisOrThatSessionHistory';
  static const String thisOrThatSessionDetail = '/thisOrThatSessionDetail';
  static const String thisOrThatCustomList = '/thisOrThatCustomList';
  static const String thisOrThatCustomCreate = '/thisOrThatCustomCreate';
  static const String neutralScreen = '/neutralScreen';
  static const String notificationInbox = '/notificationInbox';
}

/// Lets code with no widget BuildContext of its own (e.g. a push
/// notification tap arriving from the OS, which has no guaranteed
/// context) still navigate. Read via appNavigatorKey.currentContext,
/// which is non-null any time the app has rendered at least one frame.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter(RoutingNotifier routingNotifier) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
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
        path: RouteNames.anonymousProfile,
        name: 'anonymousProfile',
        builder: (context, state) {
          final authorHandle = state.extra as String?;
          if (authorHandle == null) {
            return const Scaffold(
              body: Center(child: Text('Profile unavailable.')),
            );
          }
          return AnonymousProfileScreen(authorHandle: authorHandle);
        },
      ),
      GoRoute(
        path: RouteNames.commentThread,
        name: 'commentThread',
        builder: (context, state) {
          final opinion = state.extra as OpinionModel?;
          if (opinion == null) {
            return const Scaffold(
              body: Center(child: Text('Opinion unavailable.')),
            );
          }
          return CommentThreadScreen(opinionId: opinion.id, opinion: opinion);
        },
      ),
      GoRoute(
        path: RouteNames.editOpinion,
        name: 'editOpinion',
        builder: (context, state) {
          final opinion = state.extra as OpinionModel?;
          if (opinion == null) {
            return const Scaffold(
              body: Center(child: Text('Opinion unavailable.')),
            );
          }
          return EditOpinionScreen(opinion: opinion);
        },
      ),
      GoRoute(
        path: RouteNames.quoteCompose,
        name: 'quoteCompose',
        builder: (context, state) {
          final opinion = state.extra as OpinionModel?;
          if (opinion == null) {
            return const Scaffold(
              body: Center(child: Text('Opinion unavailable.')),
            );
          }
          return QuoteComposeScreen(quotedOpinion: opinion);
        },
      ),
      GoRoute(
        path: RouteNames.tagBrowse,
        name: 'tagBrowse',
        builder: (context, state) {
          final tagSlug = state.extra as String?;
          if (tagSlug == null) {
            return const Scaffold(body: Center(child: Text('Tag missing.')));
          }
          return TagBrowseScreen(tagSlug: tagSlug);
        },
      ),
      GoRoute(
        path: RouteNames.debateRoom,
        name: 'debateRoom',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String topicId,
                    String topicTitle,
                    String userSide,
                    TopicModel? initialTopic,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Topic unavailable.')),
            );
          }
          return DebateRoomScreen(
            topicId: args.topicId,
            topicTitle: args.topicTitle,
            userSide: args.userSide,
            initialTopic: args.initialTopic,
          );
        },
      ),
      GoRoute(
        path: RouteNames.sideSelection,
        name: 'sideSelection',
        builder: (context, state) {
          final topic = state.extra as TopicModel?;
          if (topic == null) {
            return const Scaffold(
              body: Center(child: Text('Topic unavailable.')),
            );
          }
          return SideSelectionScreen(topic: topic);
        },
      ),
      GoRoute(
        path: RouteNames.forumInsight,
        name: 'forumInsight',
        builder: (context, state) {
          final topicId = state.extra as String?;
          if (topicId == null) {
            return const Scaffold(
              body: Center(child: Text('Topic unavailable.')),
            );
          }
          return ForumInsightScreen(topicId: topicId);
        },
      ),
      GoRoute(
        path: RouteNames.healingJourney,
        name: 'healingJourney',
        builder: (context, state) => const HealingJourneyScreen(),
      ),
      GoRoute(
        path: RouteNames.reflectionJournal,
        name: 'reflectionJournal',
        builder: (context, state) => const ReflectionJournalScreen(),
      ),
      GoRoute(
        path: RouteNames.journalEntryCompose,
        name: 'journalEntryCompose',
        builder: (context, state) {
          final entryId = state.extra as String?;
          return JournalEntryComposeScreen(entryId: entryId);
        },
      ),
      GoRoute(
        path: RouteNames.journalEntryDetail,
        name: 'journalEntryDetail',
        builder: (context, state) {
          final entryId = state.extra as String;
          return JournalEntryDetailScreen(entryId: entryId);
        },
      ),
      GoRoute(
        path: RouteNames.pulse,
        name: 'pulse',
        builder: (context, state) => const PulseScreen(),
      ),
      GoRoute(
        path: RouteNames.couplesCalendar,
        name: 'couplesCalendar',
        builder: (context, state) => const CouplesCalendarScreen(),
      ),
      GoRoute(
        path: RouteNames.addEditReminder,
        name: 'addEditReminder',
        builder: (context, state) => const AddEditReminderScreen(),
      ),
      GoRoute(
        path: RouteNames.familyMembers,
        name: 'familyMembers',
        builder: (context, state) => const FamilyMembersScreen(),
      ),
      GoRoute(
        path: RouteNames.chatInsights,
        name: 'chatInsights',
        builder: (context, state) {
          final args =
              state.extra as ({String relationshipId, String partnerName})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Insights unavailable.')),
            );
          }
          return ChatInsightsScreen(
            relationshipId: args.relationshipId,
            partnerName: args.partnerName,
          );
        },
      ),
      GoRoute(
        path: RouteNames.chatImport,
        name: 'chatImport',
        builder: (context, state) {
          final conversation = state.extra as Conversation?;
          if (conversation == null) {
            return const Scaffold(
              body: Center(child: Text('Conversation unavailable.')),
            );
          }
          return ChatImportScreen(conversation: conversation);
        },
      ),
      GoRoute(
        path: RouteNames.weeklyCheckin,
        name: 'weeklyCheckin',
        builder: (context, state) => const WeeklyCheckinScreen(),
      ),
      GoRoute(
        path: RouteNames.checkinComplete,
        name: 'checkinComplete',
        builder: (context, state) => const CheckinCompleteScreen(),
      ),
      GoRoute(
        path: RouteNames.logMomentType,
        name: 'logMomentType',
        builder: (context, state) => const LogMomentTypeScreen(),
      ),
      GoRoute(
        path: RouteNames.quizEntry,
        name: 'quizEntry',
        builder: (context, state) {
          final quizType = state.extra as String? ?? 'attachment';
          return QuizEntryScreen(quizType: quizType);
        },
      ),
      GoRoute(
        path: RouteNames.attachmentQuiz,
        name: 'attachmentQuiz',
        builder: (context, state) {
          final quizType = state.extra as String? ?? 'attachment';
          return AttachmentQuizScreen(quizType: quizType);
        },
      ),
      GoRoute(
        path: RouteNames.attachmentQuizLoading,
        name: 'attachmentQuizLoading',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    Map<int, int?> answers,
                    String quizType,
                    Function(AttachmentResult) onComplete,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Quiz unavailable.')),
            );
          }
          return QuizLoadingScreen(
            answers: args.answers,
            quizType: args.quizType,
            onComplete: args.onComplete,
          );
        },
      ),
      GoRoute(
        path: RouteNames.attachmentQuizResult,
        name: 'attachmentQuizResult',
        builder: (context, state) {
          final args =
              state.extra as ({AttachmentResult result, String quizType})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Result unavailable.')),
            );
          }
          return QuizResultScreen(result: args.result, quizType: args.quizType);
        },
      ),
      GoRoute(
        path: RouteNames.conflictStyleQuiz,
        name: 'conflictStyleQuiz',
        builder: (context, state) => const ConflictStyleQuizScreen(),
      ),
      GoRoute(
        path: RouteNames.conflictStyleLoading,
        name: 'conflictStyleLoading',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    ConflictStyleResult result,
                    Map<int, int?> answers,
                    Function(ConflictStyleResult) onComplete,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Quiz unavailable.')),
            );
          }
          return ConflictStyleLoadingScreen(
            result: args.result,
            answers: args.answers,
            onComplete: args.onComplete,
          );
        },
      ),
      GoRoute(
        path: RouteNames.conflictStyleResult,
        name: 'conflictStyleResult',
        builder: (context, state) {
          final result = state.extra as ConflictStyleResult?;
          if (result == null) {
            return const Scaffold(
              body: Center(child: Text('Result unavailable.')),
            );
          }
          return ConflictStyleResultScreen(result: result);
        },
      ),
      GoRoute(
        path: RouteNames.loveLanguageQuiz,
        name: 'loveLanguageQuiz',
        builder: (context, state) => const LoveLanguageQuizScreen(),
      ),
      GoRoute(
        path: RouteNames.loveLanguageLoading,
        name: 'loveLanguageLoading',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    LoveLanguageResult result,
                    Map<int, int?> answers,
                    VoidCallback onComplete,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Quiz unavailable.')),
            );
          }
          return LoveLanguageLoadingScreen(
            result: args.result,
            answers: args.answers,
            onComplete: args.onComplete,
          );
        },
      ),
      GoRoute(
        path: RouteNames.loveLanguageResult,
        name: 'loveLanguageResult',
        builder: (context, state) {
          final result = state.extra as LoveLanguageResult?;
          if (result == null) {
            return const Scaffold(
              body: Center(child: Text('Result unavailable.')),
            );
          }
          return LoveLanguageResultScreen(result: result);
        },
      ),
      GoRoute(
        path: RouteNames.communicationStyleQuiz,
        name: 'communicationStyleQuiz',
        builder: (context, state) => const CommunicationStyleQuizScreen(),
      ),
      GoRoute(
        path: RouteNames.communicationStyleLoading,
        name: 'communicationStyleLoading',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    CommunicationStyleResult result,
                    Map<int, int?> answers,
                    Function(CommunicationStyleResult) onComplete,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Quiz unavailable.')),
            );
          }
          return CommunicationStyleLoadingScreen(
            result: args.result,
            answers: args.answers,
            onComplete: args.onComplete,
          );
        },
      ),
      GoRoute(
        path: RouteNames.communicationStyleResult,
        name: 'communicationStyleResult',
        builder: (context, state) {
          final result = state.extra as CommunicationStyleResult?;
          if (result == null) {
            return const Scaffold(
              body: Center(child: Text('Result unavailable.')),
            );
          }
          return CommunicationStyleResultScreen(result: result);
        },
      ),
      GoRoute(
        path: RouteNames.partnerQuizResult,
        name: 'partnerQuizResult',
        builder: (context, state) {
          final args = state.extra as ({String quizType, String partnerId})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Result unavailable.')),
            );
          }
          return PartnerQuizResultScreen(
            quizType: args.quizType,
            partnerId: args.partnerId,
          );
        },
      ),
      GoRoute(
        path: RouteNames.healingStage,
        name: 'healingStage',
        builder: (context, state) {
          final args = state.extra as ({HealingJourney journey, int stage})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Journey unavailable.')),
            );
          }
          return HealingStageScreen(journey: args.journey, stage: args.stage);
        },
      ),
      GoRoute(
        path: RouteNames.datingConsent,
        name: 'datingConsent',
        builder: (context, state) => const DatingConsentScreen(),
      ),
      GoRoute(
        path: RouteNames.datingProfile,
        name: 'datingProfile',
        builder: (context, state) => const DatingProfileScreen(),
      ),
      GoRoute(
        path: RouteNames.datingMatches,
        name: 'datingMatches',
        builder: (context, state) => const DatingMatchesScreen(),
      ),
      GoRoute(
        path: RouteNames.datingGuidedDate,
        name: 'datingGuidedDate',
        builder: (context, state) {
          final matchId = state.extra as String?;
          if (matchId == null) {
            return const Scaffold(
              body: Center(child: Text('Match unavailable.')),
            );
          }
          return DatingGuidedDateScreen(matchId: matchId);
        },
      ),
      GoRoute(
        path: RouteNames.datingPhotos,
        name: 'datingPhotos',
        builder: (context, state) => const DatingPhotosScreen(),
      ),
      GoRoute(
        path: RouteNames.datingVerification,
        name: 'datingVerification',
        builder: (context, state) => const DatingVerificationScreen(),
      ),
      GoRoute(
        path: RouteNames.logMomentDetails,
        name: 'logMomentDetails',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String eventType,
                    String? editEventId,
                    Map<String, dynamic>? initialData,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Moment unavailable.')),
            );
          }
          return LogMomentDetailsScreen(
            eventType: args.eventType,
            editEventId: args.editEventId,
            initialData: args.initialData,
          );
        },
      ),
      GoRoute(
        path: RouteNames.gamesHub,
        name: 'gamesHub',
        builder: (context, state) => const GamesHubScreen(),
      ),
      GoRoute(
        path: RouteNames.thirtySixChapterInvitation,
        name: 'thirtySixChapterInvitation',
        builder: (context, state) {
          final args =
              state.extra
                  as ({String sessionId, int chapter, bool isInitiator})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Chapter unavailable.')),
            );
          }
          return ThirtySixChapterInvitationScreen(
            sessionId: args.sessionId,
            chapter: args.chapter,
            isInitiator: args.isInitiator,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixChapterIntroduction,
        name: 'thirtySixChapterIntroduction',
        builder: (context, state) {
          final args = state.extra as ({String sessionId, int chapter})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Chapter unavailable.')),
            );
          }
          return ThirtySixChapterIntroductionScreen(
            sessionId: args.sessionId,
            chapter: args.chapter,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixQuestion,
        name: 'thirtySixQuestion',
        builder: (context, state) {
          final args = state.extra as ({String sessionId, int chapter})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Chapter unavailable.')),
            );
          }
          return ThirtySixQuestionScreen(
            sessionId: args.sessionId,
            chapter: args.chapter,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixChapterCompletion,
        name: 'thirtySixChapterCompletion',
        builder: (context, state) {
          final args = state.extra as ({String sessionId, int chapter})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Chapter unavailable.')),
            );
          }
          return ThirtySixChapterCompletionScreen(
            sessionId: args.sessionId,
            chapter: args.chapter,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixWaiting,
        name: 'thirtySixWaiting',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String sessionId,
                    String roundId,
                    int roundNumber,
                    int totalRounds,
                    int chapter,
                    String questionText,
                    String answerText,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Round unavailable.')),
            );
          }
          return ThirtySixWaitingScreen(
            sessionId: args.sessionId,
            roundId: args.roundId,
            roundNumber: args.roundNumber,
            totalRounds: args.totalRounds,
            chapter: args.chapter,
            questionText: args.questionText,
            answerText: args.answerText,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixReveal,
        name: 'thirtySixReveal',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String sessionId,
                    String roundId,
                    int roundNumber,
                    int totalRounds,
                    int chapter,
                    String questionText,
                    String userAnswer,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Round unavailable.')),
            );
          }
          return ThirtySixRevealScreen(
            sessionId: args.sessionId,
            roundId: args.roundId,
            roundNumber: args.roundNumber,
            totalRounds: args.totalRounds,
            chapter: args.chapter,
            questionText: args.questionText,
            userAnswer: args.userAnswer,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixJourneyCompletion,
        name: 'thirtySixJourneyCompletion',
        builder: (context, state) {
          final sessionId = state.extra as String?;
          if (sessionId == null) {
            return const Scaffold(
              body: Center(child: Text('Journey unavailable.')),
            );
          }
          return ThirtySixJourneyCompletionScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixChapterHistory,
        name: 'thirtySixChapterHistory',
        builder: (context, state) {
          final args = state.extra as ({String sessionId, int chapter})?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Chapter unavailable.')),
            );
          }
          return ThirtySixChapterHistoryScreen(
            sessionId: args.sessionId,
            chapter: args.chapter,
          );
        },
      ),
      GoRoute(
        path: RouteNames.truthOrDareGame,
        name: 'truthOrDareGame',
        builder: (context, state) => const TruthOrDareGameScreen(),
      ),
      GoRoute(
        path: RouteNames.truthOrDareToneSelector,
        name: 'truthOrDareToneSelector',
        builder: (context, state) => const TruthOrDareToneSelectorScreen(),
      ),
      GoRoute(
        path: RouteNames.truthOrDareSessionRouter,
        name: 'truthOrDareSessionRouter',
        builder: (context, state) {
          final sessionId = state.extra as String?;
          if (sessionId == null) {
            return const Scaffold(
              body: Center(child: Text('Session unavailable.')),
            );
          }
          return TruthOrDareSessionRouterScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: RouteNames.customTruthOrDareList,
        name: 'customTruthOrDareList',
        builder: (context, state) => const CustomTruthOrDareListScreen(),
      ),
      GoRoute(
        path: RouteNames.customTruthOrDareCreate,
        name: 'customTruthOrDareCreate',
        builder: (context, state) => const CustomTruthOrDareCreateScreen(),
      ),
      GoRoute(
        path: RouteNames.truthOrDareHistory,
        name: 'truthOrDareHistory',
        builder: (context, state) => const TruthOrDareHistoryScreen(),
      ),
      GoRoute(
        path: RouteNames.truthReveal,
        name: 'truthReveal',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String sessionId,
                    String roundId,
                    int roundNumber,
                    int totalRounds,
                    String tone,
                    bool isPartnerA,
                    String partnerName,
                    String questionText,
                    bool isCustom,
                    String? customQuestionId,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Round unavailable.')),
            );
          }
          return TruthRevealScreen(
            sessionId: args.sessionId,
            roundId: args.roundId,
            roundNumber: args.roundNumber,
            totalRounds: args.totalRounds,
            tone: args.tone,
            isPartnerA: args.isPartnerA,
            partnerName: args.partnerName,
            questionText: args.questionText,
            isCustom: args.isCustom,
            customQuestionId: args.customQuestionId,
          );
        },
      ),
      GoRoute(
        path: RouteNames.dareReveal,
        name: 'dareReveal',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String sessionId,
                    String roundId,
                    int roundNumber,
                    int totalRounds,
                    String tone,
                    bool isPartnerA,
                    String partnerName,
                    String dareText,
                    bool isCustom,
                    String? customQuestionId,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Round unavailable.')),
            );
          }
          return DareRevealScreen(
            sessionId: args.sessionId,
            roundId: args.roundId,
            roundNumber: args.roundNumber,
            totalRounds: args.totalRounds,
            tone: args.tone,
            isPartnerA: args.isPartnerA,
            partnerName: args.partnerName,
            dareText: args.dareText,
            isCustom: args.isCustom,
            customQuestionId: args.customQuestionId,
          );
        },
      ),
      GoRoute(
        path: RouteNames.thirtySixJourneyOverview,
        name: 'thirtySixJourneyOverview',
        builder: (context, state) {
          final journeyId = state.extra as String?;
          if (journeyId == null) {
            return const Scaffold(
              body: Center(child: Text('Journey unavailable.')),
            );
          }
          return ThirtySixJourneyOverviewScreen(journeyId: journeyId);
        },
      ),
      GoRoute(
        path: RouteNames.communityFeed,
        name: 'communityFeed',
        builder: (context, state) => const CommunityFeedScreen(),
      ),
      GoRoute(
        path: RouteNames.thisOrThatGamesHub,
        name: 'thisOrThatGamesHub',
        builder: (context, state) => const ThisOrThatGamesHubScreen(),
      ),
      GoRoute(
        path: RouteNames.thisOrThatToneSelector,
        name: 'thisOrThatToneSelector',
        builder: (context, state) => const ToneSelectorScreen(),
      ),
      GoRoute(
        path: RouteNames.thisOrThatSessionRouter,
        name: 'thisOrThatSessionRouter',
        builder: (context, state) {
          final sessionId = state.extra as String?;
          if (sessionId == null) {
            return const Scaffold(
              body: Center(child: Text('Session unavailable.')),
            );
          }
          return ThisOrThatSessionRouterScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: RouteNames.customQuestionList,
        name: 'customQuestionList',
        builder: (context, state) => const CustomQuestionListScreen(),
      ),
      GoRoute(
        path: RouteNames.customQuestionCreate,
        name: 'customQuestionCreate',
        builder: (context, state) => const CustomQuestionCreateScreen(),
      ),
      GoRoute(
        path: RouteNames.thisOrThatSessionHistory,
        name: 'thisOrThatSessionHistory',
        builder: (context, state) => const SessionHistoryScreen(),
      ),
      GoRoute(
        path: RouteNames.thisOrThatSessionDetail,
        name: 'thisOrThatSessionDetail',
        builder: (context, state) {
          final sessionId = state.extra as String?;
          if (sessionId == null) {
            return const Scaffold(
              body: Center(child: Text('Session unavailable.')),
            );
          }
          return SessionDetailScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: RouteNames.thisOrThatCustomList,
        name: 'thisOrThatCustomList',
        builder: (context, state) => const ThisOrThatCustomListScreen(),
      ),
      GoRoute(
        path: RouteNames.thisOrThatCustomCreate,
        name: 'thisOrThatCustomCreate',
        builder: (context, state) => const ThisOrThatCustomCreateScreen(),
      ),
      GoRoute(
        path: RouteNames.neutralScreen,
        name: 'neutralScreen',
        builder: (context, state) => const NeutralScreen(),
      ),
      GoRoute(
        path: RouteNames.notificationInbox,
        name: 'notificationInbox',
        builder: (context, state) => const NotificationInboxScreen(),
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
          final relationshipId =
              state.uri.queryParameters['relationshipId'] ?? '';
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
        path: RouteNames.mutedAuthorsScreen,
        name: 'mutedAuthorsScreen',
        builder: (context, state) => const MutedAuthorsScreen(),
      ),
      GoRoute(
        path: RouteNames.datingMode,
        name: 'datingMode',
        builder: (context, state) => const DatingDashboardScreen(),
      ),
      GoRoute(
        path: '/games/paint-ball/lobby/:relationshipId',
        name: 'paintBallLobby',
        builder: (context, state) {
          final relationshipId = state.pathParameters['relationshipId']!;
          return PaintBallLobbyScreen(relationshipId: relationshipId);
        },
      ),
      GoRoute(
        path: '/games/paint-ball/battle/:sessionId',
        name: 'paintBallBattle',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return PaintBallBattleScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: '/games/paint-ball/knockout/:sessionId',
        name: 'paintBallKnockout',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return PaintBallKnockoutScreen(sessionId: sessionId);
        },
      ),
      GoRoute(
        path: RouteNames.ask2Flow,
        builder: (context, state) {
          final relationshipId = state.pathParameters['relationshipId']!;
          return Ask2Flow(relationshipId: relationshipId);
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
