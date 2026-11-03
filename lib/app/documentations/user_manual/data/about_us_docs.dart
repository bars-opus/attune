// lib/app/documentations/user_manual/data/about_us_docs.dart
//
// "About us" (Spec 1 §3.8, W5). Listed only while flow_signin_v2,
// flow_paths_v2, flow_couples_v2 and couple_profile are on
// (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class AboutUsDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'About us';

  @override
  String get id => 'aboutUs';

  @override
  String getSubtitle(BuildContext context) =>
      'A few shared answers about your relationship';

  @override
  IconData get icon => Icons.favorite_border_rounded;

  @override
  int get order => 3;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'about_us_what',
      title: 'What About us is',
      subtitle: 'Short questions, every one skippable',
      icon: Icons.favorite_border_rounded,
      category: 'About us',
      order: 1,
      contents: [
        ManualContent(
          id: 'about_us_questions',
          title: 'The questions',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Where you are: dating, engaged, married, or in your own words.',
            'When you got together, as a month and year, a full date, or just the year.',
            'If you are married, the year of your ceremony (up to two).',
            'Where you live, and whether there are children in your life together.',
            'Whether to remember your anniversary.',
          ],
        ),
        ManualContent(
          id: 'about_us_never_scored',
          title: '',
          content:
              'Either of you can change these. It\'s never used to score or type you.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'about_us_where',
      title: 'Where to find it',
      subtitle: 'Before and after your partner joins',
      icon: Icons.place_outlined,
      category: 'About us',
      order: 2,
      contents: [
        ManualContent(
          id: 'about_us_before',
          title: 'While your invite is waiting',
          numberPrefix: '1',
          content:
              'Your answers are a draft only you can see. When your partner joins, your answers become your shared About us.',
        ),
        ManualContent(
          id: 'about_us_after',
          title: 'After your partner joins',
          numberPrefix: '2',
          content:
              'In Settings, open Your relationship, then About us. Under each answer you can see who changed it last, and when.',
        ),
        ManualContent(
          id: 'about_us_anniversary',
          title: 'Your anniversary',
          numberPrefix: '3',
          content:
              'If you choose a date to remember, Together keeps one yearly reminder for it. Change or turn it off in About us.',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_about_us_told',
      question: 'Does my partner get a notification when I change About us?',
      answer:
          'No. There is no notification and no feed. Your partner sees the change, with your name, next time your partner opens About us.',
      category: 'About us',
      order: 1,
    ),
  ];
}
