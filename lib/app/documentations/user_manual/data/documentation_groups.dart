// The guides' sections (owner 2026-11-26): the manual is listed by what
// people want to do, not as one long list. Every registered guide belongs to
// exactly one section (guarded by documentation_groups_test.dart), so a new
// guide only needs a line here to land in the right place.
//
// English only for now, like the guides list's other new labels.

/// A section of the guides, in display order.
enum DocumentationGroup {
  startHere('Start here'),
  talking('Talking together'),
  understanding('Understanding yourselves'),
  together('Doing things together'),
  dating('Dating'),
  healing('Healing and just you'),
  relationship('Your relationship');

  const DocumentationGroup(this.title);

  /// The section's heading.
  final String title;
}

/// Each guide's section, by its DocumentationModule.id.
const Map<String, DocumentationGroup> documentationGroupOf = {
  // Start here
  'aboutAttune': DocumentationGroup.startHere,
  'howYouUseAttune': DocumentationGroup.startHere,
  'privacyData': DocumentationGroup.startHere,
  'safety': DocumentationGroup.startHere,
  // Talking together
  'chat': DocumentationGroup.talking,
  'conflictTranslator': DocumentationGroup.talking,
  'hardMoment': DocumentationGroup.talking,
  'safetyCheck': DocumentationGroup.talking,
  // Understanding yourselves
  'pulse': DocumentationGroup.understanding,
  'verdict': DocumentationGroup.understanding,
  'attachmentQuiz': DocumentationGroup.understanding,
  'attachmentStyleQuiz': DocumentationGroup.understanding,
  'communicationQuiz': DocumentationGroup.understanding,
  'conflictStyleQuiz': DocumentationGroup.understanding,
  'loveLanguageQuiz': DocumentationGroup.understanding,
  'coupleMap': DocumentationGroup.understanding,
  'anchors': DocumentationGroup.understanding,
  // Doing things together
  'games': DocumentationGroup.together,
  'thisOrThat': DocumentationGroup.together,
  'truthOrDare': DocumentationGroup.together,
  'thirtySixQuestions': DocumentationGroup.together,
  'paintBall': DocumentationGroup.together,
  'planning': DocumentationGroup.together,
  'together': DocumentationGroup.together,
  'appreciation': DocumentationGroup.together,
  'shareAWin': DocumentationGroup.together,
  'couplesJournal': DocumentationGroup.together,
  // Dating
  'datingMode': DocumentationGroup.dating,
  // Healing and just you
  'healing': DocumentationGroup.healing,
  'reflectionJournal': DocumentationGroup.healing,
  'opinions': DocumentationGroup.healing,
  'communityQuestions': DocumentationGroup.healing,
  // Your relationship
  'relationshipLifecycle': DocumentationGroup.relationship,
  'aboutUs': DocumentationGroup.relationship,
  'quietStates': DocumentationGroup.relationship,
  'streaks': DocumentationGroup.relationship,
};

/// A guide's section; one not listed yet goes to "Start here" rather than
/// disappearing (the guard test catches it first).
DocumentationGroup documentationGroupFor(String moduleId) =>
    documentationGroupOf[moduleId] ?? DocumentationGroup.startHere;
