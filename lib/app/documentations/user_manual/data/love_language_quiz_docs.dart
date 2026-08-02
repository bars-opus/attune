// lib/app/documentations/user_manual/data/love_language_quiz_docs.dart
//
// Documents the Love Language Quiz. Sourced from
// lib/architecture/LOVE_LANGUAGE_QUIZ_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class LoveLanguageQuizDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Love Language Quiz';

  @override
  String get id => 'loveLanguageQuiz';

  @override
  String getSubtitle(BuildContext context) =>
      'How you most naturally give and receive affection';

  @override
  IconData get icon => Icons.favorite_outline;

  @override
  int get order => 12;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'love_lang_what_it_is',
      title: 'What it is',
      subtitle: 'Self-awareness, not a matching test',
      icon: Icons.self_improvement_outlined,
      category: 'Love Language Quiz',
      order: 1,
      contents: [
        ManualContent(
          id: 'love_lang_intro',
          title: '15 questions, about 3 minutes',
          numberPrefix: '1',
          content:
              'Based on the well-known five love languages framework, this quiz explores how you most naturally feel appreciated: words of affirmation, quality time, receiving gifts, acts of service, and physical touch.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'love_lang_not_compatibility',
          title: '',
          content:
              'This is strictly a self-awareness tool — it\'s never used to score compatibility between you and a partner. Research hasn\'t found solid evidence that "matching" love languages predicts anything about a relationship, so Attune never treats it that way.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'love_lang_result',
      title: 'Your result',
      subtitle: 'A spectrum across all five',
      icon: Icons.pie_chart_outline,
      category: 'Love Language Quiz',
      order: 2,
      contents: [
        ManualContent(
          id: 'love_lang_result_shape',
          title: '',
          content:
              'You\'ll see a spectrum across all five languages, with your primary and secondary highlighted — not just a single label, so you get a fuller picture of what actually resonates with you.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'love_lang_no_mismatch_claim',
          title: '',
          content:
              'You\'ll never see a claim like "your love languages don\'t match your partner\'s, which may be causing disconnection" — that framing isn\'t supported by the research, so Attune doesn\'t make it.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_love_lang_matching',
        question:
            'Does it matter if my love language doesn\'t match my partner\'s?',
        answer:
            'Attune doesn\'t treat this as a problem — research hasn\'t found real evidence that matching love languages predicts relationship outcomes, so this quiz is never used to imply mismatch is an issue.',
        category: 'Love Language Quiz',
        order: 1,
      ),
      FAQModel(
        id: 'faq_love_lang_compatibility',
        question: 'Is this used anywhere as a compatibility score?',
        answer:
            'No, never. It\'s explicitly a self-awareness tool only, and is not used for compatibility scoring anywhere in the app.',
        category: 'Love Language Quiz',
        order: 2,
      ),
      FAQModel(
        id: 'faq_love_lang_retake',
        question: 'Can I retake this quiz?',
        answer:
            'Yes, any time — your new result replaces the old one, and prior results are kept so you can see how things have shifted.',
        category: 'Love Language Quiz',
        order: 3,
      ),
      FAQModel(
        id: 'faq_love_lang_share',
        question: 'Is my result shared with my partner automatically?',
        answer:
            'No — it\'s private by default, and only shared if you explicitly choose to.',
        category: 'Love Language Quiz',
        order: 4,
      ),
    ];
  }
}
