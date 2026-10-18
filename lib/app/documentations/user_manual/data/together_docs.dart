// lib/app/documentations/user_manual/data/together_docs.dart
//
// The Together calendar (Planning → Calendar; lib/features/together; spec
// docs/superpowers/specs/2026-10-14-together-hub-design.md). Always listed.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class TogetherDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Together calendar';

  @override
  String get id => 'together';

  @override
  String getSubtitle(BuildContext context) =>
      'Your dates, rituals and plans — suggested, never imposed';

  @override
  IconData get icon => Icons.calendar_month_outlined;

  @override
  int get order => 4;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'together_what',
      title: 'What you\'ll see',
      subtitle: 'Planning → Calendar',
      icon: Icons.calendar_month_outlined,
      category: 'Together',
      order: 1,
      contents: [
        ManualContent(
          id: 'together_sections',
          title: 'From today to your story',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Needs you:** suggestions waiting for your answer, to-dos nobody has taken, polls to vote on.',
            '**Today and This week:** what\'s planned, and when you\'re both free.',
            '**Rituals:** the regular things you\'ve agreed to, like a weekly date night.',
            '**Coming up:** birthdays, anniversaries and plans ahead.',
            '**Our story:** recent moments and "On this day" from earlier years.',
          ],
        ),
        ManualContent(
          id: 'together_switch',
          title: 'Agenda or Month',
          numberPrefix: '2',
          content: 'Switch between a running list and a month view at the top.',
        ),
      ],
    ),
    ManualSection(
      id: 'together_suggest',
      title: 'Suggesting, not deciding',
      subtitle: 'Anything that involves your partner is a proposal',
      icon: Icons.handshake_outlined,
      category: 'Together',
      order: 2,
      contents: [
        ManualContent(
          id: 'together_proposals',
          title: 'Proposals',
          numberPrefix: '1',
          content:
              'Suggest a plan with up to three times; your partner picks one or declines. A suggestion nobody answers quietly expires after 7 days.',
        ),
        ManualContent(
          id: 'together_rituals',
          title: 'Rituals',
          numberPrefix: '2',
          content:
              'Agree once on a weekly or fortnightly ritual and it fills itself in ahead. Either of you can skip a week, move it, pause it or end it.',
        ),
        ManualContent(
          id: 'together_no_scores',
          title: '',
          content:
              'No streaks, badges or counts — skipping a ritual is never held against anyone.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'together_settings',
      title: 'Together settings',
      subtitle: 'Everything is off until you turn it on',
      icon: Icons.tune_outlined,
      category: 'Together',
      order: 3,
      contents: [
        ManualContent(
          id: 'together_settings_list',
          title: 'Your choices',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Morning summary:** one note at 8am when something involves you.',
            '**Free time together:** shows when you\'re both free. Only the fact that you\'re busy leaves your phone — never titles, places or people.',
            '**Home screen and lock screen:** show your next plan discreetly. Anyone who sees your phone can see it; quick exit clears it.',
            '**Your phone\'s calendar or a calendar link:** add your plans to Google, Apple or Outlook. Titles and places stay hidden unless you turn them on.',
          ],
        ),
        ManualContent(
          id: 'together_link_private',
          title: '',
          content:
              'Anyone with your calendar link can see your Together calendar, so keep it to yourself. You can get a new link or turn it off any time; ending a relationship turns both links off.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_together_private_event',
      question: 'Can I add something my partner can\'t see?',
      answer:
          'Yes. A private or surprise event is shown only to you — in the app, in your calendar link and in "free time" — until you choose otherwise.',
      category: 'Together',
      order: 1,
    ),
    FAQModel(
      id: 'faq_together_free_off',
      question: 'What happens when I turn off Free time together?',
      answer:
          'Your busy times are deleted straight away, and your partner isn\'t told.',
      category: 'Together',
      order: 2,
    ),
  ];
}
