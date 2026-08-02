// lib/app/documentations/user_manual/data/attachment_style_quiz_docs.dart
//
// Documents the Attachment Style Quiz. Sourced from
// lib/architecture/ATTACHMENT_STYLE_QUIZ.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class AttachmentStyleQuizDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Attachment Style Quiz';

  @override
  String get id => 'attachmentStyleQuiz';

  @override
  String getSubtitle(BuildContext context) =>
      'A snapshot of how you tend to show up in relationships';

  @override
  IconData get icon => Icons.psychology_alt_outlined;

  @override
  int get order => 9;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'attach_what_it_is',
      title: 'What it is',
      subtitle: 'A spectrum, not a fixed label',
      icon: Icons.explore_outlined,
      category: 'Attachment Quiz',
      order: 1,
      contents: [
        ManualContent(
          id: 'attach_intro',
          title: 'Rooted in real research',
          numberPrefix: '1',
          content:
              '25 questions, about 5 minutes, exploring two dimensions psychologists use to understand how people connect: how much you worry about a partner\'s availability, and how comfortable you are with closeness and depending on others.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'attach_not_fixed',
          title: '',
          content:
              'Your result is a snapshot of how you tend to show up right now — never presented as a permanent identity. Attachment tendencies genuinely shift with time, growth, and experience, and you can retake this quiz any time to see how things have changed.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'attach_result',
      title: 'Your result',
      subtitle: 'Warm language, real spectrum data',
      icon: Icons.insights_outlined,
      category: 'Attachment Quiz',
      order: 2,
      contents: [
        ManualContent(
          id: 'attach_result_shows',
          title: 'What you\'ll see',
          content:
              'Your result includes a named type (like "Secure" or "Anxious-secure") with a warm, plain-language description, plus the actual spectrum breakdown behind it — not just a label with nothing underneath.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'attach_no_bad_words',
          title: '',
          content:
              'Your result never uses words like "disorder," "broken," or "toxic" — even the more challenging patterns are described with genuine warmth and framed as something you can work with, not something wrong with you.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'attach_privacy',
      title: 'Privacy and sharing',
      subtitle: 'Yours until you choose otherwise',
      icon: Icons.lock_outline,
      category: 'Attachment Quiz',
      order: 3,
      contents: [
        ManualContent(
          id: 'attach_private_default',
          title: 'Private by default',
          content:
              'Your result is private and stays that way unless you explicitly choose to share it with your partner. Nothing is shared automatically, ever.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_attach_permanent',
        question: 'Is my attachment style permanent?',
        answer:
            'No — it\'s presented as how you tend to show up right now, not a fixed identity. Attachment tendencies can and do shift with growth, therapy, and life experience.',
        category: 'Attachment Quiz',
        order: 1,
      ),
      FAQModel(
        id: 'faq_attach_partner_sees',
        question: 'Can my partner see my result without my permission?',
        answer:
            'No — your result is private by default. It\'s only ever visible to your partner if you explicitly choose to share it.',
        category: 'Attachment Quiz',
        order: 2,
      ),
      FAQModel(
        id: 'faq_attach_retake',
        question: 'Can I retake the quiz?',
        answer:
            'Yes, any time. Your new result replaces the old one, and past results are kept so you can track how you\'ve changed over time.',
        category: 'Attachment Quiz',
        order: 3,
      ),
      FAQModel(
        id: 'faq_attach_diagnosis',
        question: 'Is this a clinical diagnosis?',
        answer:
            'No. This is a self-reflection tool based on established attachment research, not a clinical assessment or diagnosis of any kind.',
        category: 'Attachment Quiz',
        order: 4,
      ),
    ];
  }
}
