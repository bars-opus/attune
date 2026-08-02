// lib/core/documentation/documentation_registry.dart
import 'package:attune/app/documentations/user_manual/data/about_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/data/attachment_style_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/chat_docs.dart';
import 'package:attune/app/documentations/user_manual/data/communication_style_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/community_questions_docs.dart';
import 'package:attune/app/documentations/user_manual/data/conflict_style_quiz_docs.dart';
import 'package:attune/app/documentations/user_manual/data/conflict_translator_docs.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/forum_docs.dart';
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
import 'package:attune/features/onboarding/presentation/data/anchors_docs.dart';
import 'package:attune/features/onboarding/presentation/data/attachment_quiz_docs.dart';

// lib/core/documentation/documentation_registry.dart
// 4. Update DocumentationRegistry

class DocumentationRegistry {
  // Store all modules by ID
  static final Map<String, DocumentationModule> _idMap = {};

  // Initialize with default modules
  static void initialize() {
    // Register all your modules here
    registerModule(AboutAttuneDocs());

    registerModule(ChatDocs());
    registerModule(GamesDocs());
    registerModule(TruthOrDareDocs());
    registerModule(ThisOrThatDocs());
    registerModule(ThirtySixQuestionsDocs());
    registerModule(HealingDocs());

    registerModule(ReflectionJournalDocs());
    registerModule(PulseDocs());
    registerModule(VerdictDocs());
    registerModule(ConflictTranslatorDocs());
    registerModule(SafetyDocs());
    registerModule(AttachmentQuizDocs());
    registerModule(AnchorsDocs());

    registerModule(DatingModeDocs());
    registerModule(OpinionsDocs());
    registerModule(ForumDocs());
    registerModule(CommunityQuestionsDocs());
    registerModule(PaintBallDocs());
    registerModule(AttachmentStyleQuizDocs());
    registerModule(CommunicationStyleQuizDocs());
    registerModule(ConflictStyleQuizDocs());
    registerModule(LoveLanguageQuizDocs());

    // Add more as needed
  }

  // ✅ 1. Get all modules (sorted by order)
  static List<DocumentationModule> getAllModules() {
    return _idMap.values.toList()..sort((a, b) => a.order.compareTo(b.order));
  }

  // ✅ 2. Get module by ID
  static DocumentationModule? getById(String id) => _idMap[id];

  static AboutAttuneDocs get aboutAttune =>
      getById('aboutAttune') as AboutAttuneDocs;
  static ChatDocs get chat => getById('chat') as ChatDocs;
  static GamesDocs get games => getById('games') as GamesDocs;
  static TruthOrDareDocs get truthOrDare =>
      getById('truthOrDare') as TruthOrDareDocs;
  static ThisOrThatDocs get thisOrThat =>
      getById('thisOrThat') as ThisOrThatDocs;
  static ThirtySixQuestionsDocs get thirtySixQuestions =>
      getById('thirtySixQuestions') as ThirtySixQuestionsDocs;
  static HealingDocs get healing => getById('healing') as HealingDocs;

  // ✅ 3. Get direct instances (for type-safe access)
  static ReflectionJournalDocs get reflectionJournal =>
      getById('reflectionJournal') as ReflectionJournalDocs;
  static PulseDocs get pulse => getById('pulse') as PulseDocs;
  static VerdictDocs get verdict => getById('verdict') as VerdictDocs;
  static ConflictTranslatorDocs get conflictTranslator =>
      getById('conflictTranslator') as ConflictTranslatorDocs;
  static SafetyDocs get safety => getById('safety') as SafetyDocs;
  static DatingModeDocs get datingMode =>
      getById('datingMode') as DatingModeDocs;
  static OpinionsDocs get opinions => getById('opinions') as OpinionsDocs;
  static ForumDocs get forums => getById('forums') as ForumDocs;
  static CommunityQuestionsDocs get communityQuestions =>
      getById('communityQuestions') as CommunityQuestionsDocs;
  static PaintBallDocs get paintBall =>
      getById('paintBall') as PaintBallDocs;
  static AttachmentStyleQuizDocs get attachmentStyleQuiz =>
      getById('attachmentStyleQuiz') as AttachmentStyleQuizDocs;
  static CommunicationStyleQuizDocs get communicationQuiz =>
      getById('communicationQuiz') as CommunicationStyleQuizDocs;
  static ConflictStyleQuizDocs get conflictStyleQuiz =>
      getById('conflictStyleQuiz') as ConflictStyleQuizDocs;
  static LoveLanguageQuizDocs get loveLanguageQuiz =>
      getById('loveLanguageQuiz') as LoveLanguageQuizDocs;
  // static AuthenticationDocs get authentication =>
  // getById('authentication') as AuthenticationDocs;

  // ✅ 4. Register new modules
  static void registerModule(DocumentationModule module) {
    _idMap[module.id] = module;
  }

  // ✅ 5. Get all topic IDs
  static List<String> getAllTopicIds() => _idMap.keys.toList();

  // ✅ 6. Get modules by category
  static Map<String, List<DocumentationModule>> getModulesByCategory() {
    final map = <String, List<DocumentationModule>>{};

    return map;
  }
}
