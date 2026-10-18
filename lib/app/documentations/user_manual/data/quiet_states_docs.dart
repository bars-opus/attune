// lib/app/documentations/user_manual/data/quiet_states_docs.dart
//
// "Quiet for a while" and "Ask for support" (Spec 7, research 06 B9, A9).
// Listed only while quiet_states is on (DocumentationRegistry). "Hide a
// period" is unflagged and documented in privacy_data_docs.dart.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class QuietStatesDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Quiet for a while';

  @override
  String get id => 'quietStates';

  @override
  String getSubtitle(BuildContext context) =>
      'When celebrations feel like too much, Attune can go quiet for you';

  @override
  IconData get icon => Icons.spa_outlined;

  @override
  int get order => 5;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'quiet_what',
      title: 'What it does',
      subtitle: 'Fewer celebrations, for you only',
      icon: Icons.spa_outlined,
      category: 'Quiet',
      order: 1,
      contents: [
        ManualContent(
          id: 'quiet_where',
          title: 'Turning it on',
          numberPrefix: '1',
          content:
              'Go to Settings → Quiet for a while and choose "Having a hard time" or "Going through a loss". It ends on its own after 14 days, or tap "End now" any time.',
        ),
        ManualContent(
          id: 'quiet_effects',
          title: 'What goes quiet',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'No sparkles or goal-reached celebrations.',
            'A plainer daily summary.',
            'No "On this day" memories or memory prompts.',
            'No celebration cards for wins.',
            'Gentler Love map questions and date ideas.',
          ],
        ),
        ManualContent(
          id: 'quiet_private',
          title: '',
          content:
              'Only you can see that it is on. Your partner\'s app doesn\'t change, and they are not told.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'quiet_line',
          title: 'If you want to tell them',
          numberPrefix: '3',
          content:
              'When you turn it on, Attune offers you one optional message you can send: "I\'m in a heavy patch. I may be quieter; it isn\'t about you." You can send it or not — it\'s only offered once.',
        ),
      ],
    ),
    ManualSection(
      id: 'quiet_support',
      title: 'Ask for support',
      subtitle: 'Say what would help, without having to find the words',
      icon: Icons.volunteer_activism_outlined,
      category: 'Quiet',
      order: 2,
      contents: [
        ManualContent(
          id: 'quiet_support_how',
          title: 'A few ready lines',
          numberPrefix: '1',
          content:
              'In Chat, tap the attach button and choose "Ask for support". Pick what would help — for example "I need to vent. Can you just listen for a bit?" — and it is added to your message for you to edit or send.',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_quiet_partner',
      question: 'Will my partner notice anything?',
      answer:
          'Nothing in their app changes, and they are never told. The only way they know is if you send the optional message or tell them yourself.',
      category: 'Quiet',
      order: 1,
    ),
    FAQModel(
      id: 'faq_quiet_longer',
      question: 'Can I keep it on for longer than 14 days?',
      answer:
          'Turn it on again when it ends. It stops on its own so that the app never stays quiet without you choosing it.',
      category: 'Quiet',
      order: 2,
    ),
  ];
}
