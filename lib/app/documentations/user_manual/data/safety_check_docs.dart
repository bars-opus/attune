// lib/app/documentations/user_manual/data/safety_check_docs.dart
//
// The private safety check and "A trained outside perspective" (Spec 8,
// research 06 F14, B10). Listed only while private_safety_check is on
// (DocumentationRegistry). Never quotes the check's questions (clinician
// [DRAFT]); never describes what the server does with a positive answer
// beyond what the person sees, so the doc itself cannot become a tell.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class SafetyCheckDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Private safety check-in';

  @override
  String get id => 'safetyCheck';

  @override
  String getSubtitle(BuildContext context) =>
      'Four questions about how safe you feel — only you ever see it';

  @override
  IconData get icon => Icons.verified_user_outlined;

  @override
  int get order => 2;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'safety_check_what',
      title: 'What it is',
      subtitle: 'A short, private check-in',
      icon: Icons.verified_user_outlined,
      category: 'Safety',
      order: 1,
      contents: [
        ManualContent(
          id: 'safety_check_questions',
          title: 'Four questions, three answers',
          numberPrefix: '1',
          content:
              'Four short questions about how safe you feel in your relationship. Each one can be answered Yes, No or Prefer not to say. It takes under a minute.',
        ),
        ManualContent(
          id: 'safety_check_where',
          title: 'Where you\'ll find it',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'In Safety resources, any time.',
            'In Pulse, offered every 90 days.',
            'Once, at the end of the second set of getting-to-know-you questions.',
          ],
        ),
        ManualContent(
          id: 'safety_check_skip',
          title: '',
          content:
              'You can skip it whenever it is offered. Skipping changes nothing.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'safety_check_private',
      title: 'Completely private',
      subtitle: 'Not your partner, not a score, not stored',
      icon: Icons.lock_outline,
      category: 'Safety',
      order: 2,
      contents: [
        ManualContent(
          id: 'safety_check_private_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Your answers are never stored — not by your partner, not by Attune.',
            'Your partner is never told you took it, or what you said.',
            'It is never part of Pulse, the monthly readout or any score.',
            'The row that offers it looks the same whatever you answered.',
          ],
        ),
        ManualContent(
          id: 'safety_check_after',
          title: 'What happens after',
          numberPrefix: '1',
          content:
              'If any answer is Yes, you\'ll see support options straight away, once. If you chose Prefer not to say for all four, you\'ll see a simple link to support. Otherwise you just see a thank-you.',
        ),
        ManualContent(
          id: 'safety_check_emergency',
          title: '',
          content:
              'This check-in is not an emergency service. If you are in danger right now, call your local emergency number.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'safety_check_outside',
      title: 'A trained outside perspective',
      subtitle: 'What couples counselling is, and how to find it',
      icon: Icons.support_agent_outlined,
      category: 'Safety',
      order: 3,
      contents: [
        ManualContent(
          id: 'safety_check_outside_what',
          title: 'A resource, never a recommendation',
          numberPrefix: '1',
          content:
              'A short page about what couples counselling is, what to look for in someone, and how to find support where you live. It is reachable from Pulse, Settings, the Understand feature and the "In a hard moment" tools. Attune never tells you that your relationship "needs" it.',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_safety_check_partner',
      question: 'Can my partner find out I took the check-in?',
      answer:
          'No. Nothing on their phone changes, and nothing they can open shows whether you took it or what you answered. Your answers themselves are never saved anywhere.',
      category: 'Safety',
      order: 1,
    ),
    FAQModel(
      id: 'faq_safety_check_again',
      question: 'Can I take it again?',
      answer:
          'Yes, whenever you like, from Safety resources. Pulse offers it again every 90 days.',
      category: 'Safety',
      order: 2,
    ),
    FAQModel(
      id: 'faq_safety_check_paused',
      question: 'Can I take it while our relationship is paused?',
      answer:
          'Yes. The check-in is about you, so it is open while a relationship is active or paused.',
      category: 'Safety',
      order: 3,
    ),
  ];
}
