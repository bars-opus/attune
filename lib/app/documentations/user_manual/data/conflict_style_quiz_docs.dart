// lib/app/documentations/user_manual/data/conflict_style_quiz_docs.dart
//
// Documents the Conflict Style Quiz. Sourced from
// lib/architecture/CONFLICT_STYLE_QUIZ_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ConflictStyleQuizDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Conflict Style Quiz';

  @override
  String get id => 'conflictStyleQuiz';

  @override
  String getSubtitle(BuildContext context) =>
      'How you tend to approach disagreement';

  @override
  IconData get icon => Icons.balance_outlined;

  @override
  int get order => 11;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'conflict_what_it_is',
      title: 'What it is',
      subtitle: 'No approach is universally right',
      icon: Icons.balance_outlined,
      category: 'Conflict Style Quiz',
      order: 1,
      contents: [
        ManualContent(
          id: 'conflict_intro',
          title: '18 questions, about 4 minutes',
          numberPrefix: '1',
          content:
              'This quiz reflects on the approaches you may use during disagreement: collaborating, competing, avoiding, accommodating, and compromising. You\'ll see how much you lean toward each — not just one label.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'conflict_no_good_bad',
          title: '',
          content:
              'No conflict style is universally good or bad. Context, safety, power, and culture all shape which approach makes sense at a given moment — avoiding or accommodating can genuinely be the right call sometimes, and direct engagement isn\'t always safe or appropriate.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'conflict_result',
      title: 'Your result',
      subtitle: 'Five independent tendencies',
      icon: Icons.insights_outlined,
      category: 'Conflict Style Quiz',
      order: 2,
      contents: [
        ManualContent(
          id: 'conflict_five_scores',
          title: '',
          content:
              'You\'ll see a score for all five tendencies, with your primary and secondary approaches highlighted. Framing stays gentle throughout — "your answers lean toward avoiding in the situations you considered," never "you are avoidant."',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'conflict_scope',
      title: 'What this doesn\'t determine',
      subtitle: 'A reflection tool, not a grade',
      icon: Icons.rule_outlined,
      category: 'Conflict Style Quiz',
      order: 3,
      contents: [
        ManualContent(
          id: 'conflict_not_used',
          title: '',
          content:
              'This result never affects your Pulse Score, feeds into a couple-level verdict, or scores your conflict-handling skill. It\'s for your own self-awareness, and it stays private unless you choose to share it.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_conflict_bad_style',
        question: 'Is one conflict style considered the "best" one?',
        answer:
            'No — no style is universally good or bad. Context, safety, and the relationship all shape which approach genuinely makes sense in a given moment.',
        category: 'Conflict Style Quiz',
        order: 1,
      ),
      FAQModel(
        id: 'faq_conflict_pulse',
        question: 'Does my result affect my Pulse Score?',
        answer:
            'No — this quiz result is never used to compute Pulse Score or any couple-level relationship metric.',
        category: 'Conflict Style Quiz',
        order: 2,
      ),
      FAQModel(
        id: 'faq_conflict_tki',
        question: 'Is this the official Thomas-Kilmann Conflict Mode Instrument?',
        answer:
            'No — this is an Attune-authored reflection tool inspired by the general five-mode conflict framework, not the proprietary TKI, and it is not a clinically validated assessment.',
        category: 'Conflict Style Quiz',
        order: 3,
      ),
      FAQModel(
        id: 'faq_conflict_private',
        question: 'Is my result private?',
        answer:
            'Yes — private by default, shared with your partner only if you explicitly choose to.',
        category: 'Conflict Style Quiz',
        order: 4,
      ),
    ];
  }
}
