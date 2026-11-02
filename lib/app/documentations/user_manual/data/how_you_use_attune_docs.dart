// lib/app/documentations/user_manual/data/how_you_use_attune_docs.dart
//
// "How you use Attune" (Spec 1 §3.7, §3.10, §3.12). Listed only while
// flow_signin_v2 and flow_paths_v2 are on (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class HowYouUseAttuneDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'How you use Attune';

  @override
  String get id => 'howYouUseAttune';

  @override
  String getSubtitle(BuildContext context) =>
      'In a relationship, dating, or just for you, and how to change it';

  @override
  IconData get icon => Icons.alt_route_outlined;

  @override
  int get order => 2;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'how_paths',
      title: 'Three ways to use Attune',
      subtitle: 'Choose one; change it any time',
      icon: Icons.alt_route_outlined,
      category: 'How you use Attune',
      order: 1,
      contents: [
        ManualContent(
          id: 'how_paths_list',
          title: 'The three ways',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'In a relationship: a private space for you and your partner. Your second tab is Chat.',
            'Single and open to dating: a few introductions a day, only when it\'s mutual. Your second tab is Me, with Dating at the top.',
            'Just for me: your journal, quizzes and Healing. Your second tab is Me.',
          ],
        ),
        ManualContent(
          id: 'how_paths_yours',
          title: '',
          content:
              'Your journal, quizzes and Healing stay yours whichever you choose.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'how_change',
      title: 'Changing how you use Attune',
      subtitle: 'Settings → How you use Attune',
      icon: Icons.swap_horiz_outlined,
      category: 'How you use Attune',
      order: 2,
      contents: [
        ManualContent(
          id: 'how_change_where',
          title: 'Where to change it',
          numberPrefix: '1',
          content:
              'Go to Settings → How you use Attune and choose another way. Nobody is told when you change it.',
        ),
        ManualContent(
          id: 'how_change_shared',
          title: 'If you share a space with a partner',
          numberPrefix: '2',
          content:
              'To use Attune another way, pause or end your shared space first. Pausing keeps it, read-only, for up to 30 days.',
        ),
        ManualContent(
          id: 'how_change_invite',
          title: 'If your invite is still waiting',
          numberPrefix: '3',
          content:
              'Changing to another way cancels your invite: the code stops working, and nobody is told.',
        ),
        ManualContent(
          id: 'how_change_dating',
          title: 'Dating and a partner',
          numberPrefix: '4',
          content:
              'Inviting a partner pauses Dating: your introductions stop and your Dating profile is hidden. Nobody is told.',
        ),
      ],
    ),
    ManualSection(
      id: 'how_reminder',
      title: 'A reminder to write',
      subtitle: 'Only if you set one',
      icon: Icons.alarm_outlined,
      category: 'How you use Attune',
      order: 3,
      contents: [
        ManualContent(
          id: 'how_reminder_set',
          title: 'Setting it',
          numberPrefix: '1',
          content:
              'In Your space, or Settings → Notifications, tap "Remind me to write", choose a day and a time from 8:00 AM to 9:59 PM, and tap Turn on. The notification just says "A few quiet minutes for you, if you\'d like."',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_how_told',
      question: 'Is anyone told when I change how I use Attune?',
      answer:
          'No. Nobody is told, not a partner, not a match, not anyone who invited you.',
      category: 'How you use Attune',
      order: 1,
    ),
  ];
}
