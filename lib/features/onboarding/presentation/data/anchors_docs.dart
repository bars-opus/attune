import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';

/// Documentation shown right before the anchors step — explains what an
/// "anchor" is and why Attune asks for them in the user's own words, so the
/// three open questions that follow don't feel like an unexplained detour
/// after the attachment quiz.
///
/// The copy branches on [mode] the same way AttachmentQuizDocs does: a
/// single user answers about themselves and their own history, a couples
/// user answers about their partner and the relationship.
class AnchorsDocs implements DocumentationModule {
  AnchorsDocs({this.mode});

  /// The mode picked earlier in onboarding, if any. Null when shown outside
  /// the onboarding flow, where the copy falls back to a mode-neutral
  /// explanation.
  final OnboardingMode? mode;

  bool get _isRelationship => mode?.isRelationshipTrack ?? false;

  bool get _isSingle => mode == OnboardingMode.personal;

  @override
  String get id => 'anchors';

  @override
  IconData get icon => Icons.anchor_outlined;

  @override
  int get order => 2;

  @override
  String getTitle(BuildContext context) => 'About your anchors';

  @override
  String getSubtitle(BuildContext context) {
    if (_isSingle) {
      return 'Up next: three anchors — short, open questions about what you want to understand about yourself and what you\'re hoping to do differently. Unlike the quiz, there\'s no scale here — you write your own answer, in your own words. It takes about 2-3 minutes, and this is the very next step, right after you close this.';
    }
    return 'Up next: three anchors — short, open questions about your relationship, in your own words. Unlike the quiz, there\'s no scale here — you write a real answer, not a rating. It takes about 2-3 minutes, and this is the very next step, right after you close this.';
  }

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'anchors',
      title: mode?.label ?? 'About anchors',
      subtitle:
          'An anchor is a short written answer, in your own words, to a question that matters to how Attune understands you. Where the quiz measures your general patterns on a scale, anchors capture the specific, current details a scale can\'t — what you\'re actually thinking about right now.',
      icon: Icons.anchor_outlined,
      category: 'Onboarding',
      order: 2,
      contents: [
        ManualContent(
          id: 'anchors_what',
          title: 'What you\'re about to do',
          numberPrefix: '1',
          content:
              'You\'ll answer three open questions by typing a real response — a sentence or two is enough. There\'s no scale and no right length; this is the one part of onboarding written entirely in your own words.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'anchors_how',
          title: 'How each question works',
          numberPrefix: '2',
          content:
              'Every anchor follows the same layout, so all three feel familiar:',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'A short heading marks which anchor you\'re on — Anchor 1, 2, or 3',
            'The question itself sits above the field — e.g. "What\'s one thing you genuinely admire about your partner?"',
            'A text box is where you type your answer — it grows as you write',
            'Under the box, a few examples show the kind of answer that fits, so an empty box isn\'t your only starting point',
            'Once all three are filled in, Continue takes you to the next step',
          ],
        ),
        if (_isSingle)
          ManualContent(
            id: 'anchors_why_single',
            title: 'Why we ask',
            numberPrefix: '3',
            content:
                'The quiz tells Attune your general patterns; anchors tell it what\'s actually going on for you right now. Together they give your reflections and insights something concrete to work from:',
            type: ManualContentType.bulletList,
            bulletPoints: [
              'Your specific goals and history shape the language Attune uses with you, not just your quiz score',
              'Insights can reference what you actually said, instead of guessing at your situation',
              'If you link with a partner later, these anchors are already part of your profile',
            ],
          )
        else
          ManualContent(
            id: 'anchors_why_couple',
            title: 'Why we ask',
            numberPrefix: '3',
            content:
                'The quiz tells Attune your general patterns; anchors tell it what\'s actually going on in your relationship right now:',
            type: ManualContentType.bulletList,
            bulletPoints: [
              'Your specific answers give Attune real context instead of generic relationship advice',
              'Once you and your partner are both linked, shared insights can draw on what you both actually said',
              'Conflict guidance and prompts can reference the real things you\'re each hoping for',
            ],
          ),
        ManualContent(
          id: 'anchors_honesty',
          title: '',
          content:
              'Write what\'s actually true for you, not what sounds good — short and honest is more useful than long and polished.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'anchors_privacy',
          title: '',
          content:
              _isRelationship
                  ? 'Your individual anchors stay private. Your partner only ever sees insights derived from both of your answers together, never your raw text.'
                  : 'Your anchors are private to you. Nothing here is shared with anyone, and if you link with a partner later, they still only ever see derived insights — never your raw text.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_anchors_1',
        question: 'How long should my answers be?',
        answer:
            'A sentence or two is enough. There\'s no minimum or maximum — the examples under each field show the kind of length and detail that works well.',
        category: 'Onboarding',
        order: 1,
      ),
      FAQModel(
        id: 'faq_anchors_2',
        question: 'What if I\'m not sure how to answer?',
        answer:
            'Use the examples under the field as a starting point, or write the closest true thing even if it feels incomplete — you can always update it later from Settings.',
        category: 'Onboarding',
        order: 2,
      ),
      if (!_isSingle)
        FAQModel(
          id: 'faq_anchors_partner',
          question: 'Can my partner see my individual anchors?',
          answer:
              'No. Your partner only ever sees the insights derived from both of your answers together, never your raw text.',
          category: 'Onboarding',
          order: 3,
        ),
      FAQModel(
        id: 'faq_anchors_3',
        question: 'Can I change my anchors later?',
        answer:
            'Yes — you can revisit and update your anchors from Settings at any time, and your insights will update accordingly.',
        category: 'Onboarding',
        order: 4,
      ),
    ];
  }
}
