// lib/app/documentations/user_manual/data/thirty_six_questions_docs.dart
//
// Documents the 36 Questions Journey. Sourced from
// lib/architecture/36_QUESTIONS.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ThirtySixQuestionsDocs implements DocumentationModule {
  @override
  int get order => 16;

  @override
  String getTitle(BuildContext context) => '36 Questions';

  @override
  String get id => 'thirtySixQuestions';

  @override
  String getSubtitle(BuildContext context) =>
      'A guided journey toward closeness, one chapter at a time';

  @override
  IconData get icon => Icons.diversity_1_outlined;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'tsq_what_it_is',
      title: 'What it is',
      subtitle: 'Based on a well-known closeness study',
      icon: Icons.diversity_1_outlined,
      category: '36 Questions',
      order: 1,
      contents: [
        ManualContent(
          id: 'tsq_intro',
          title: 'Three chapters, thirty-six questions',
          numberPrefix: '1',
          content:
              'This journey adapts a well-known 1997 psychology study designed to build closeness through structured conversation. It\'s organized into 3 chapters of 12 questions each, moving gradually from light and easy to genuinely vulnerable.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tsq_chapters',
          title: 'The three chapters',
          content: '',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Chapter 1 — Warm Up:** Light, easy questions — preferences, memories, everyday closeness.',
            '**Chapter 2 — Deeper:** Values, family, emotional needs, hopes, and what makes you feel seen.',
            '**Chapter 3 — Vulnerable:** Fear, loss, healing, the future, trust, and truly being known.',
          ],
        ),
        ManualContent(
          id: 'tsq_boundaries',
          title: '',
          content:
              'This journey never asks you to disclose past trauma or abuse, list what you dislike about your partner, or make a commitment decision. It\'s built to deepen understanding, not extract confession.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'tsq_playing',
      title: 'How a chapter works',
      subtitle: 'Answer, then reveal together',
      icon: Icons.forum_outlined,
      category: '36 Questions',
      order: 2,
      contents: [
        ManualContent(
          id: 'tsq_answering',
          title: 'Writing your answers',
          content:
              'Each question gets a written answer — a sentence or two is plenty, up to 400 characters. Your partner only sees your answer once you\'ve both submitted for that question.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tsq_skip',
          title: 'Skipping a question',
          content:
              'If a particular question doesn\'t feel right for you in the moment, you can skip it — there\'s no requirement to answer everything to move forward.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tsq_ceremony',
          title: 'Finishing a chapter',
          content:
              'Completing all 12 questions in a chapter shows a short completion moment, sometimes with a gentle observation about a theme that came up in your answers — always warm, never a verdict on your relationship.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'tsq_opt_in',
      title: 'Going deeper is always a choice',
      subtitle: 'Both of you decide, every time',
      icon: Icons.handshake_outlined,
      category: '36 Questions',
      order: 3,
      contents: [
        ManualContent(
          id: 'tsq_mutual_optin',
          title: 'Fresh consent for every chapter',
          content:
              'Finishing a chapter never automatically moves you into the next one. You\'ll both be asked explicitly whether to continue now or leave it for another day — and both of you have to agree before the next chapter opens, whether that\'s minutes or weeks later.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tsq_order',
          title: '',
          content:
              'Chapters unlock in order — you can\'t jump ahead to Chapter 3\'s vulnerable questions without genuinely completing Chapters 1 and 2 first. The gradual pace is part of how this journey is designed to work.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'tsq_reflection',
      title: 'The journey reflection',
      subtitle: 'A gentle summary, only when there\'s enough to say',
      icon: Icons.auto_awesome_outlined,
      category: '36 Questions',
      order: 4,
      contents: [
        ManualContent(
          id: 'tsq_reflection_what',
          title: 'A thread across your answers',
          content:
              'After all three chapters are complete, you may see a short reflection pointing at a theme that showed up across your answers — written warmly, grounded in what you both actually wrote, never a diagnosis of your relationship.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tsq_reflection_optional',
          title: '',
          content:
              'This reflection only appears when there\'s genuinely enough material to say something meaningful and specific. If you skipped a lot of questions, you may not see one at all — that\'s intentional, so nothing gets said that isn\'t really grounded in what you wrote.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_tsq_length',
        question: 'How long does this journey take?',
        answer:
            'Each chapter is about 20 minutes, and there are 3 chapters. There\'s no time pressure between chapters — you can take a break for a day, a week, or longer, and pick up right where you left off once you\'re both ready.',
        category: '36 Questions',
        order: 1,
      ),
      FAQModel(
        id: 'faq_tsq_skip_penalty',
        question: 'What happens if I skip a question?',
        answer:
            'Nothing bad — you simply move to the next one. Skipping is always available, and there\'s no penalty or note attached to it.',
        category: '36 Questions',
        order: 2,
      ),
      FAQModel(
        id: 'faq_tsq_one_journey',
        question: 'Can we start a second journey while one is in progress?',
        answer:
            'No — a relationship can only have one 36 Questions journey in progress at a time. You\'ll need to finish or end the current one before starting another.',
        category: '36 Questions',
        order: 3,
      ),
      FAQModel(
        id: 'faq_tsq_trauma',
        question: 'Will this journey ask about past trauma or abuse?',
        answer:
            'No. Questions that push toward disclosing trauma, listing grievances about your partner, or making a commitment decision are explicitly excluded from every chapter, by design.',
        category: '36 Questions',
        order: 4,
      ),
      FAQModel(
        id: 'faq_tsq_reflection_missing',
        question: 'Why didn\'t we get a journey reflection at the end?',
        answer:
            'A reflection only appears when there\'s enough usable material across your answers to say something genuinely grounded and specific. If several answers were skipped or removed, the reflection may not appear — that\'s intentional, not an error.',
        category: '36 Questions',
        order: 5,
      ),
      FAQModel(
        id: 'faq_tsq_advance_automatic',
        question: 'Does the next chapter start automatically when we finish one?',
        answer:
            'No. Every chapter requires both of you to explicitly choose to continue — nothing advances on its own. You\'re always free to stop after any chapter.',
        category: '36 Questions',
        order: 6,
      ),
    ];
  }
}
