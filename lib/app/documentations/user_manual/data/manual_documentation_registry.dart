// lib/core/documentation/documentation_registry.dart
import 'package:attune/app/documentations/user_manual/data/about_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/data/appreciation_docs.dart';
import 'package:attune/app/documentations/user_manual/data/couple_map_docs.dart';
import 'package:attune/app/documentations/user_manual/data/couples_journal_docs.dart';
import 'package:attune/app/documentations/user_manual/data/hard_moment_docs.dart';
import 'package:attune/app/documentations/user_manual/data/planning_docs.dart';
import 'package:attune/app/documentations/user_manual/data/privacy_data_docs.dart';
import 'package:attune/app/documentations/user_manual/data/quiet_states_docs.dart';
import 'package:attune/app/documentations/user_manual/data/relationship_lifecycle_docs.dart';
import 'package:attune/app/documentations/user_manual/data/safety_check_docs.dart';
import 'package:attune/app/documentations/user_manual/data/share_a_win_docs.dart';
import 'package:attune/app/documentations/user_manual/data/streaks_docs.dart';
import 'package:attune/app/documentations/user_manual/data/together_docs.dart';
import 'package:attune/app/documentations/user_manual/data/attachment_style_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/chat_docs.dart';
import 'package:attune/app/documentations/user_manual/data/communication_style_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/community_questions_docs.dart';
import 'package:attune/app/documentations/user_manual/data/conflict_style_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/conflict_translator_docs.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/games_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/app/documentations/user_manual/data/love_language_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/opinions_docs.dart';
import 'package:attune/app/documentations/user_manual/data/paint_ball_docs.dart';
import 'package:attune/app/documentations/user_manual/data/pulse_docs.dart';
import 'package:attune/app/documentations/user_manual/data/reflection_journal_docs.dart';
import 'package:attune/app/documentations/user_manual/data/safety_docs.dart';
import 'package:attune/app/documentations/user_manual/data/thirty_six_questions_docs.dart';
import 'package:attune/app/documentations/user_manual/data/this_or_that_docs.dart';
import 'package:attune/app/documentations/user_manual/data/truth_or_dare_docs.dart';
import 'package:attune/app/documentations/user_manual/data/verdict_docs.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/onboarding/presentation/data/anchors_docs.dart';
import 'package:attune/features/onboarding/presentation/data/attachment_quiz_docs.dart';

/// Every manual topic, registered once. A topic that explains a feature
/// behind a feature flag declares it in [_requiredFlags] and is listed only
/// while every one of its flags is on, so nobody reads about a feature they
/// cannot find.
class DocumentationRegistry {
  static final Map<String, DocumentationModule> _idMap = {};

  /// Topic id -> the feature flags that must all be on to list it.
  static const Map<String, List<String>> _requiredFlags = {
    'hardMoment': [
      ChatFeatureFlags.conflictToolkit,
      ChatFeatureFlags.privateSafetyCheck,
    ],
    'safetyCheck': [ChatFeatureFlags.privateSafetyCheck],
    'appreciation': [ChatFeatureFlags.appreciationNotes],
    'shareAWin': [ChatFeatureFlags.shareAWin],
    'streaks': [ChatFeatureFlags.ephemeralVideo, ChatFeatureFlags.videoSharing],
    'quietStates': [ChatFeatureFlags.quietStates],
    'coupleMap': [ChatFeatureFlags.coupleMap],
    // These two reflections wait for clinical sign-off.
    'communicationQuiz': [ChatFeatureFlags.quizClinicalSignoff],
    'conflictStyleQuiz': [ChatFeatureFlags.quizClinicalSignoff],
  };

  static List<String> requiredFlags(String moduleId) =>
      _requiredFlags[moduleId] ?? const [];

  /// Every flag any topic depends on (read once by documentationFlagsProvider).
  static Set<String> get allRequiredFlags =>
      {for (final flags in _requiredFlags.values) ...flags};

  /// IDs of modules related to [moduleId], shown as a "Related" tab in
  /// DocumentationTabView. One level only: a related module's own related
  /// ids are not consulted. Gated topics are dropped by the tab view while
  /// their flags are off.
  static List<String> getRelatedModuleIds(String moduleId) {
    switch (moduleId) {
      case 'games':
        return const ['truthOrDare', 'thisOrThat', 'thirtySixQuestions'];
      case 'safety':
        return const ['safetyCheck', 'privacyData', 'relationshipLifecycle'];
      case 'chat':
        return const ['hardMoment', 'appreciation', 'streaks', 'privacyData'];
      case 'pulse':
        return const ['safetyCheck', 'privacyData'];
      case 'hardMoment':
        return const ['conflictTranslator', 'safetyCheck'];
      case 'quietStates':
        return const ['appreciation', 'shareAWin'];
      case 'privacyData':
        return const ['relationshipLifecycle', 'safety'];
      case 'conflictTranslator':
        return const ['hardMoment'];
      case 'couplesJournal':
        return const [
          'planning',
          'together',
          'coupleMap',
          'reflectionJournal',
          'relationshipLifecycle',
        ];
      case 'planning':
        return const ['together', 'coupleMap'];
      default:
        return const [];
    }
  }

  static bool _initialized = false;

  /// Registers every topic, once; later calls do nothing. Lookups call it
  /// too, so a help button opened before any screen set the registry up
  /// still finds its topic and related topics.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    for (final module in <DocumentationModule>[
      AboutAttuneDocs(),
      ChatDocs(),
      GamesDocs(),
      TruthOrDareDocs(),
      ThisOrThatDocs(),
      ThirtySixQuestionsDocs(),
      HealingDocs(),
      ReflectionJournalDocs(),
      PulseDocs(),
      VerdictDocs(),
      ConflictTranslatorDocs(),
      SafetyDocs(),
      AttachmentQuizDocs(),
      AnchorsDocs(),
      DatingModeDocs(),
      OpinionsDocs(),
      CommunityQuestionsDocs(),
      PaintBallDocs(),
      AttachmentStyleQuizDocs(),
      CommunicationStyleQuizDocs(),
      ConflictStyleQuizDocs(),
      LoveLanguageQuizDocs(),
      PrivacyDataDocs(),
      RelationshipLifecycleDocs(),
      SafetyCheckDocs(),
      HardMomentDocs(),
      AppreciationDocs(),
      ShareAWinDocs(),
      StreaksDocs(),
      QuietStatesDocs(),
      CouplesJournalDocs(),
      PlanningDocs(),
      TogetherDocs(),
      CoupleMapDocs(),
    ]) {
      registerModule(module);
    }
  }

  /// All modules, sorted by order.
  static List<DocumentationModule> getAllModules() {
    initialize();
    return _idMap.values.toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  /// The modules to list for someone whose enabled flags are [enabledFlags]:
  /// every ungated topic, and each gated one whose flags are all on. Before
  /// sign-in pass an empty set.
  static List<DocumentationModule> visibleModules(Set<String> enabledFlags) {
    return getAllModules()
        .where((m) => requiredFlags(m.id).every(enabledFlags.contains))
        .toList();
  }

  static DocumentationModule? getById(String id) {
    initialize();
    return _idMap[id];
  }

  static void registerModule(DocumentationModule module) {
    _idMap[module.id] = module;
  }
}
