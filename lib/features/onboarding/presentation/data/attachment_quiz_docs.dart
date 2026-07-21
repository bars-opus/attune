import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';

/// Documentation shown right before the attachment quiz — explains what the
/// quiz is, why Attune asks it, and how the answers get used, so the 26
/// questions that follow don't feel like an unexplained wall of prompts.
///
/// The copy branches on [mode]. A single user's most common objection is
/// "why am I answering relationship questions when I'm not in one?", so the
/// Personal-mode copy answers that head-on rather than reusing couples copy
/// that talks about a partner they don't have. Per ATTUNE_MASTER_SPEC
/// "Onboarding fork", the quiz is deliberately up front for singles —
/// self-initiated self-knowledge is the value, not a partner comparison.
class AttachmentQuizDocs implements DocumentationModule {
  AttachmentQuizDocs({this.mode});

  /// The mode picked on the previous step, if any. Null when shown outside the
  /// onboarding flow (e.g. the general documentation registry), where the copy
  /// falls back to a mode-neutral explanation.
  final OnboardingMode? mode;

  /// Couples and couples-pending share the partner-facing copy; personal and
  /// an unknown mode do not.
  bool get _isRelationship => mode?.isRelationshipTrack ?? false;

  /// True only for a user who explicitly said they are single, as opposed to
  /// a null mode outside the onboarding flow — the "you're single, here's why
  /// this still matters" framing would be confusing without that context.
  bool get _isSingle => mode == OnboardingMode.personal;

  @override
  String get id => 'attachmentQuiz';

  @override
  IconData get icon => Icons.psychology_outlined;

  @override
  int get order => 1;

  @override
  String getTitle(BuildContext context) => 'About the attachment quiz';

  @override
  String getSubtitle(BuildContext context) {
    if (_isSingle) {
      return 'Up next: an attachment quiz — a set of questions that reveal how you tend to bond, trust, and handle conflict in close relationships. You don\'t need to be in a relationship to answer them, and you shouldn\'t wait until you are. Your attachment patterns are already yours; they show up in how you date, how you handle closeness, and what you notice in other people. You\'ll answer 26 short questions from 1 (no, not really) to 5 (yes, definitely), and it takes about 3-5 minutes. This is the very next step, right after you close this.';
    }
    return 'Up next: an attachment quiz — a set of questions that reveal how you tend to bond, trust, and handle conflict in close relationships. It\'s not a pass/fail test; it\'s how Attune learns the patterns that make you, you, so the insights and prompts you get later actually fit your relationship style. You\'ll answer 26 short questions from 1 (no, not really) to 5 (yes, definitely), and it takes about 3-5 minutes. This is the very next step, right after you close this.';
  }

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'attachmentQuiz',
      title: mode?.label ?? 'About the quiz',
      subtitle:
          'An attachment quiz is a set of questions used to understand how you relate to others — especially in close or romantic relationships. It doesn\'t diagnose or judge you; it maps your natural tendencies around trust, closeness, and conflict so Attune can tailor its guidance to how you actually show up, not a generic average.',
      icon: Icons.psychology_outlined,
      category: 'Onboarding',
      order: 1,
      contents: [
        ManualContent(
          id: 'quiz_what',
          title: 'What you\'re about to do',
          numberPrefix: '1',
          content:
              'You\'ll go through 26 short questions about how you relate to others — closeness, trust, communication, conflict. For each one, you\'ll say how much it\'s a yes or a no for you. There are no right answers.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'quiz_how',
          title: 'How each question works',
          numberPrefix: '2',
          content:
              'Every question follows the same layout, so once you\'ve done one you\'ve got the rhythm for all 26:',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'A number badge shows which question you\'re on, out of 26',
            'A short question is the actual thing you\'re answering — e.g. "Do you find it easy to ask for reassurance when you need it?"',
            'Underneath it, a line or two sets the scene with a relatable moment — if you want the fuller version with more context, tap it to expand',
            'A row of numbers from 1 to 5 is how you answer — tap the one that fits',
            'The scale is labelled 1 = No, not really, and 5 = Yes, definitely',
            'Tap Next once you\'ve answered to move to the next question — Back is there if you want to change something',
          ],
        ),
        if (_isSingle)
          ManualContent(
            id: 'quiz_why_single',
            title: 'Why take this if you\'re single?',
            numberPrefix: '3',
            content:
                'This is the question most people ask here, and it\'s a fair one. Attachment patterns aren\'t created by a relationship — they show up in one. Yours are already shaping how you read interest, how much closeness feels comfortable, and what you do when something goes quiet. Taking this now means:',
            type: ManualContentType.bulletList,
            bulletPoints: [
              'Your reflections and journal insights are read against your actual patterns from day one, instead of generic advice',
              'You get a personal attachment profile you can act on alone — this is the product for you, not a placeholder until you couple up',
              'Personal pulse and pattern memory have something real to work from',
              'If you do link with a partner later, you arrive with a richer profile than someone who onboards cold',
            ],
          )
        else
          ManualContent(
            id: 'quiz_why_couple',
            title: 'Why we ask',
            numberPrefix: '3',
            content:
                'Your answers shape the attachment and compatibility insights Attune builds for you and your partner:',
            type: ManualContentType.bulletList,
            bulletPoints: [
              'A personalised attachment style profile, not a generic quiz result',
              'Compatibility insights once you and your partner are both linked',
              'Guidance during conflict that accounts for how each of you responds to distance and repair',
              'More relevant prompts throughout the app',
            ],
          ),
        ManualContent(
          id: 'quiz_honesty',
          title: '',
          content:
              'Answer how you actually are, not how you\'d like to be — the insights are only as useful as the honesty behind them.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'quiz_privacy',
          title: '',
          content:
              _isRelationship
                  ? 'Your individual answers stay private. Your partner only ever sees insights derived from both of your answers together, never your raw responses.'
                  : 'Your answers are private to you. Nothing here is shared with anyone, and if you link with a partner later, they still only ever see derived insights — never your raw responses.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_attachment_quiz_1',
        question: 'How long does the quiz take?',
        answer:
            'Most people finish in 3-5 minutes. You can go back and change an answer at any point before finishing.',
        category: 'Onboarding',
        order: 1,
      ),
      if (_isSingle) ...[
        FAQModel(
          id: 'faq_attachment_quiz_single_relevance',
          question: 'I\'m single — is this quiz even relevant to me?',
          answer:
              'Yes. Attachment style describes how you relate to closeness in general, not just inside a current relationship. It shows up in dating, friendships, and family, and it\'s often clearest between relationships when you have room to notice your own patterns without someone else\'s in the way.',
          category: 'Onboarding',
          order: 2,
        ),
        FAQModel(
          id: 'faq_attachment_quiz_single_answering',
          question: 'How do I answer questions about a partner I don\'t have?',
          answer:
              'Answer from your general experience of close relationships — past partners, people you\'ve dated, or how you imagine you\'d respond. If a statement genuinely doesn\'t apply to you, answer with what feels closest to true rather than defaulting to the middle.',
          category: 'Onboarding',
          order: 3,
        ),
        FAQModel(
          id: 'faq_attachment_quiz_single_wait',
          question: 'Can I skip this until I\'m actually in a relationship?',
          answer:
              'The quiz is part of setting up your account, because almost everything Attune offers a single user — reflection analysis, personal insights, pattern memory — depends on knowing your patterns. Waiting would leave those features running on generic assumptions. You can retake it any time as your circumstances change.',
          category: 'Onboarding',
          order: 4,
        ),
      ] else
        FAQModel(
          id: 'faq_attachment_quiz_2',
          question: 'Can my partner see my individual answers?',
          answer:
              'No. Your partner only ever sees the compatibility insights derived from both of your answers together, never your raw responses.',
          category: 'Onboarding',
          order: 2,
        ),
      FAQModel(
        id: 'faq_attachment_quiz_3',
        question: 'Can I retake the quiz later?',
        answer:
            'Yes — you can revisit and update your answers from Settings at any time, and your insights will update accordingly.',
        category: 'Onboarding',
        order: 5,
      ),
    ];
  }
}
