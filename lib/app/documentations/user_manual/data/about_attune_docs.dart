// lib/app/documentations/user_manual/data/about_attune_docs.dart
//
// Documents what Attune is and why it exists, distilled for users from
// lib/architecture/attune/ATTUNE_THESIS.md (Sections 1, 2, and 3.7) and the
// one-line soul statement quoted throughout the governing specs. Deliberately
// excludes everything in the thesis that is founder/investor-facing —
// business strategy, competitive moats, unit economics, and risk tripwires
// have no place in a user-facing doc and are omitted entirely, not softened.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class AboutAttuneDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'About Attune';

  @override
  String get id => 'aboutAttune';

  @override
  String getSubtitle(BuildContext context) =>
      'Why we built this, and what we\'ll never do';

  @override
  IconData get icon => Icons.diamond_outlined;

  @override
  int get order => 1;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'about_the_bet',
      title: 'The idea behind Attune',
      subtitle: 'Your own conversation, turned into honest insight',
      icon: Icons.lightbulb_outline,
      category: 'About Attune',
      order: 1,
      contents: [
        ManualContent(
          id: 'about_pattern_blindness',
          title: 'Most people repeat the same patterns, not because they\'re broken',
          numberPrefix: '1',
          content:
              'Nobody gets objective insight into their own relationship. Memory holds onto the worst moments, not the times things were repaired well. Advice is generic — it\'s never actually about you. And real support is often expensive, hard to find, or something people feel they can\'t admit to needing.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'about_the_bet_itself',
          title: 'Our bet',
          content:
              'The raw material for real self-knowledge already exists — it\'s the conversation you and your partner already have. Attune reads it quietly, never interrupting or judging, and over time surfaces what no friend or quiz ever could: your own patterns, in your own words.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'about_beyond_couples',
      title: 'It doesn\'t end when a relationship does',
      subtitle: 'For singles, healing, and starting again',
      icon: Icons.all_inclusive,
      category: 'About Attune',
      order: 2,
      contents: [
        ManualContent(
          id: 'about_lifecycle',
          title: 'A companion through the whole arc',
          content:
              'Relationships end — so Attune doesn\'t stop there. A private healing journey helps you make sense of an ending, on your own timeline. And when you\'re genuinely ready (never rushed, never based on loneliness), Dating Mode can introduce you to people matched on who you actually are in relationships — not a photo, not a swipe.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'about_help_scarce',
          title: '',
          content:
              'Attune is not therapy, and never claims to be. But where real support is genuinely hard to reach, honest, carefully reviewed insight can still make a real difference.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'about_never_do',
      title: 'What Attune will never do',
      subtitle: 'These aren\'t promises we can quietly walk back',
      icon: Icons.gpp_good_outlined,
      category: 'About Attune',
      order: 3,
      contents: [
        ManualContent(
          id: 'about_never_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'No streaks, badges, or leaderboards — ever, under any name.',
            'No engagement-driven notifications designed to pull you back in.',
            'No scorecard that ranks you against your partner.',
            'No swipe mechanics, "they liked you" queues, or dating urgency tactics.',
            'No selling your data, and never training AI models on your private conversations.',
            'No telling you what to decide about your own relationship — ever.',
          ],
        ),
        ManualContent(
          id: 'about_architecture_not_marketing',
          title: '',
          content:
              'These rules aren\'t just policy — many of them are built directly into how the app is engineered, so they can\'t quietly change later just because it might be more profitable to do so.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'about_soul',
      title: 'The one thing to remember',
      subtitle: '',
      icon: Icons.favorite_border,
      category: 'About Attune',
      order: 4,
      contents: [
        ManualContent(
          id: 'about_soul_line',
          title: '',
          content:
              'Attune is designed to be worth returning to — not designed to make leaving feel painful.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_about_therapy',
        question: 'Is Attune a replacement for therapy?',
        answer:
            'No. Attune is not therapy, treatment, or a clinical service, and it never claims to be. It\'s a tool for self-knowledge and reflection — where real professional support is what you need, we\'ll always point you toward it rather than pretend to replace it.',
        category: 'About Attune',
        order: 1,
      ),
      FAQModel(
        id: 'faq_about_data_sold',
        question: 'Is my data ever sold or used to train AI models?',
        answer:
            'No, never. This is a permanent rule, not a policy that could change — your private conversations are never sold and never used to train AI models.',
        category: 'About Attune',
        order: 2,
      ),
      FAQModel(
        id: 'faq_about_gamification',
        question: 'Why doesn\'t Attune have streaks or badges like other apps?',
        answer:
            'It\'s a deliberate choice, not an oversight. Attune is built to be worth returning to on its own merits — never to make you feel guilty or anxious about missing a day.',
        category: 'About Attune',
        order: 3,
      ),
      FAQModel(
        id: 'faq_about_tell_decide',
        question: 'Will Attune ever tell me what to do about my relationship?',
        answer:
            'No. Attune can share honest, sourced observations, but it never tells you whether to stay, leave, or what to decide about your own relationship. That\'s always yours to decide.',
        category: 'About Attune',
        order: 4,
      ),
    ];
  }
}
