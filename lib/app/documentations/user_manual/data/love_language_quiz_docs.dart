// lib/app/documentations/user_manual/data/love_language_quiz_docs.dart
//
// Documents "What feels loving to me right now" (Spec 5, R5-5), which
// replaced the 15-question love language quiz.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class LoveLanguageQuizDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'What feels loving';

  @override
  String get id => 'loveLanguageQuiz';

  @override
  String getSubtitle(BuildContext context) =>
      'What feels loving to you right now';

  @override
  IconData get icon => Icons.self_improvement_outlined;

  @override
  int get order => 12;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'love_lang_what_it_is',
      title: 'What it is',
      subtitle: 'Self-awareness, not a matching test',
      icon: Icons.self_improvement_outlined,
      category: 'What feels loving',
      order: 1,
      contents: [
        ManualContent(
          id: 'love_lang_intro',
          title: 'Five ratings, under a minute',
          numberPrefix: '1',
          content:
              'Rate five ways of feeling cared for (words, time together, help, touch and small gifts) as not really, a little or a lot. You can add the moments they matter most, like when you\'re stressed or celebrating.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'love_lang_framework',
          title: '',
          content:
              'Based on a popular framework, not a science. There\'s no type and no "your love language is"; what feels loving changes with the week you\'re having.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'love_lang_not_compatibility',
          title: '',
          content:
              'It\'s never used to score compatibility or in your monthly readout. Research hasn\'t found that "matching" predicts anything about a relationship, so Attune never treats it that way.',
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
        question: 'Does it matter if ours are different?',
        answer:
            'No. Different answers are just useful to know; Attune never suggests a difference is a problem.',
        category: 'What feels loving',
        order: 1,
      ),
      FAQModel(
        id: 'faq_love_lang_compatibility',
        question: 'Is this used anywhere as a compatibility score?',
        answer:
            'No, never. It\'s for you, and it isn\'t read by the monthly readout or any matching.',
        category: 'What feels loving',
        order: 2,
      ),
      FAQModel(
        id: 'faq_love_lang_retake',
        question: 'Can I change my answers?',
        answer:
            'Yes, any time. If you shared them, your partner sees the newest version.',
        category: 'What feels loving',
        order: 3,
      ),
      FAQModel(
        id: 'faq_love_lang_share',
        question: 'Is it shared with my partner automatically?',
        answer:
            'No. It\'s private unless you choose to share it.',
        category: 'What feels loving',
        order: 4,
      ),
    ];
  }
}
