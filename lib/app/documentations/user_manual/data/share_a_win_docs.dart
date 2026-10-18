// lib/app/documentations/user_manual/data/share_a_win_docs.dart
//
// "Share a win" (Spec 7, research 06 B2). Listed only while share_a_win is
// on (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ShareAWinDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Share a win';

  @override
  String get id => 'shareAWin';

  @override
  String getSubtitle(BuildContext context) =>
      'Good news, big or small — and a nudge for your partner to ask about it';

  @override
  IconData get icon => Icons.emoji_events_outlined;

  @override
  int get order => 5;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'win_how',
      title: 'Sharing good news',
      subtitle: 'A moment worth celebrating',
      icon: Icons.emoji_events_outlined,
      category: 'Good things',
      order: 1,
      contents: [
        ManualContent(
          id: 'win_where',
          title: 'Where to find it',
          numberPrefix: '1',
          content:
              'In Chat, tap the attach button and choose "Share a win", or find it under Good things in Planning → Calendar. Write what happened in a few words and, if you like, add a note.',
        ),
        ManualContent(
          id: 'win_partner',
          title: 'What your partner sees',
          numberPrefix: '2',
          content:
              'For three days, your partner sees a card on their Together screen: "{your name} shared a win" with a suggestion to ask you about it. They can open Chat with a ready-to-edit question or put the card aside. There is no push notification.',
        ),
        ManualContent(
          id: 'win_moment',
          title: 'Kept with your moments',
          numberPrefix: '3',
          content:
              'The win is saved as one of your shared moments, so it stays part of your story together.',
        ),
        ManualContent(
          id: 'win_tip',
          title: '',
          content:
              'How a partner responds to good news matters as much as how they respond to bad news. Asking "what was the best part?" is the whole point of the card.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_win_quiet',
      question: 'Why can\'t I see my partner\'s win card?',
      answer:
          'Cards show for three days. If you\'ve turned on Quiet for a while, celebration cards stay hidden until it ends.',
      category: 'Good things',
      order: 1,
    ),
  ];
}
