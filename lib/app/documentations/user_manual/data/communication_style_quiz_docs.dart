// lib/app/documentations/user_manual/data/communication_style_quiz_docs.dart
//
// Documents the Communication Style Quiz. Sourced from
// lib/architecture/COMMUNICATION_STYLE_QUIZ_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class CommunicationStyleQuizDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Communication Style Quiz';

  @override
  String get id => 'communicationQuiz';

  @override
  String getSubtitle(BuildContext context) =>
      'How you tend to communicate when it matters most';

  @override
  IconData get icon => Icons.record_voice_over_outlined;

  @override
  int get order => 10;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'comm_what_it_is',
      title: 'What it is',
      subtitle: 'Noticing your patterns under pressure',
      icon: Icons.record_voice_over_outlined,
      category: 'Communication Quiz',
      order: 1,
      contents: [
        ManualContent(
          id: 'comm_intro',
          title: '20 questions, about 4 minutes',
          numberPrefix: '1',
          content:
              'This quiz helps you notice how you tend to report communicating — especially when expressing needs, facing disagreement, or feeling pressure. It measures four familiar tendencies: assertive, passive, aggressive, and passive-aggressive.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'comm_self_report',
          title: '',
          content:
              'This is a self-report snapshot, not a diagnosis, fixed identity, or moral judgment. It reflects how you see yourself, which naturally shifts depending on the relationship, the setting, and how safe you feel.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'comm_result',
      title: 'Your result',
      subtitle: 'All four tendencies, honestly framed',
      icon: Icons.bar_chart_outlined,
      category: 'Communication Quiz',
      order: 2,
      contents: [
        ManualContent(
          id: 'comm_result_shape',
          title: 'Four independent scores',
          content:
              'You\'ll see a score for each of the four tendencies — they don\'t need to add up to 100%, because it\'s entirely normal to lean toward more than one depending on the situation. Your primary and secondary tendencies are highlighted.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'comm_no_accusation',
          title: '',
          content:
              'You\'ll never see your result phrased as an accusation, like "you are passive-aggressive." Instead it\'s framed gently: "your answers suggest you may lean toward direct communication in many situations."',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'comm_where_used',
      title: 'Where this result is (and isn\'t) used',
      subtitle: 'Only where it genuinely helps',
      icon: Icons.rule_outlined,
      category: 'Communication Quiz',
      order: 3,
      contents: [
        ManualContent(
          id: 'comm_translator_use',
          title: 'A gentle assist for the Conflict Translator',
          content:
              'Your Conflict Translator suggestions may lean on your current tendency as soft, optional context — never a diagnosis, and the tool works perfectly fine even if you\'ve never taken this quiz.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'comm_not_used_elsewhere',
          title: '',
          content:
              'This result is never used to compute your Pulse Score or generate a couple-level compatibility verdict — it stays a personal self-awareness tool.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_comm_add_up',
        question: 'Should my four scores add up to 100%?',
        answer:
            'No — each of the four tendencies is scored independently, since it\'s completely normal to lean toward more than one depending on the situation.',
        category: 'Communication Quiz',
        order: 1,
      ),
      FAQModel(
        id: 'faq_comm_pulse',
        question: 'Does this result affect my Pulse Score?',
        answer:
            'No — this quiz result is never used in Pulse Score calculations or any couple-level compatibility summary. It\'s strictly a personal self-awareness tool.',
        category: 'Communication Quiz',
        order: 2,
      ),
      FAQModel(
        id: 'faq_comm_accusation',
        question: 'Will my result label me as "aggressive" or similar?',
        answer:
            'No. Result copy is always framed gently and non-accusatorially — for example, "your answers suggest you may lean toward direct communication" rather than a blunt label.',
        category: 'Communication Quiz',
        order: 3,
      ),
      FAQModel(
        id: 'faq_comm_translator_required',
        question:
            'Do I need to take this quiz for the Conflict Translator to work?',
        answer:
            'No — the Conflict Translator works perfectly well without it. This quiz only adds soft, optional personalization if you\'ve taken it.',
        category: 'Communication Quiz',
        order: 4,
      ),
    ];
  }
}
