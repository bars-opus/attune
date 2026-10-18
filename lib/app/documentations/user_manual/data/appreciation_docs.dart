// lib/app/documentations/user_manual/data/appreciation_docs.dart
//
// "I noticed…" notes and the appreciation jar (Spec 7, research 06 B1).
// Listed only while appreciation_notes is on (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class AppreciationDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => '"I noticed…" and your jar';

  @override
  String get id => 'appreciation';

  @override
  String getSubtitle(BuildContext context) =>
      'Small, specific thanks — and a private place to keep the ones you receive';

  @override
  IconData get icon => Icons.eco_outlined;

  @override
  int get order => 5;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'appreciation_note',
      title: 'Sending a note',
      subtitle: 'Specific beats sweeping',
      icon: Icons.eco_outlined,
      category: 'Good things',
      order: 1,
      contents: [
        ManualContent(
          id: 'appreciation_where',
          title: 'Where to find it',
          numberPrefix: '1',
          content:
              'In Chat, tap the attach button and choose "I noticed…". It is also under Good things in Planning → Calendar.',
        ),
        ManualContent(
          id: 'appreciation_form',
          title: 'You write the middle',
          numberPrefix: '2',
          content:
              'The note reads "I noticed you … . Thank you." — you fill in what you noticed, like "remembered Mum\'s appointment". It arrives in your chat as an ordinary message with a small leaf.',
        ),
        ManualContent(
          id: 'appreciation_thankful',
          title: 'Another way to say it',
          numberPrefix: '3',
          content:
              'If you prefer, turn on "Thankful for you" phrasing in Settings. Then you can also choose "Thankful for you because … ." This setting stays on your phone.',
        ),
        ManualContent(
          id: 'appreciation_tip',
          title: '',
          content:
              'Name one small, real thing. "You made the morning easy" lands far better than "You\'re the best".',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'appreciation_jar',
      title: 'Your appreciation jar',
      subtitle: 'Notes you chose to keep',
      icon: Icons.savings_outlined,
      category: 'Good things',
      order: 2,
      contents: [
        ManualContent(
          id: 'appreciation_jar_save',
          title: 'Keep the ones that matter',
          numberPrefix: '1',
          content:
              'Long-press a note you received and choose "Save to my jar". Open your jar from Good things to read them again. You can remove any note from your jar.',
        ),
        ManualContent(
          id: 'appreciation_jar_private',
          title: '',
          content:
              'Your jar is yours alone. Your partner never sees what you kept, and nothing counts how many notes either of you sent or saved.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'appreciation_never',
      title: 'What never happens',
      subtitle: 'No quotas, no reminders',
      icon: Icons.block_flipped,
      category: 'Good things',
      order: 3,
      contents: [
        ManualContent(
          id: 'appreciation_never_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'No streaks, counts or "you haven\'t thanked them" reminders.',
            'Notes are never read by Attune\'s AI and never affect Pulse.',
            'A note can\'t be edited after sending, so it always says what you meant. You can delete it like any message.',
          ],
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_appreciation_saved',
      question: 'Is my partner told when I save their note?',
      answer:
          'No. Saving to your jar is private. Nothing on their side changes.',
      category: 'Good things',
      order: 1,
    ),
    FAQModel(
      id: 'faq_appreciation_ended',
      question: 'What happens to my jar if our relationship ends?',
      answer:
          'You can read your jar while your chat is still readable. Download my data includes the notes you kept.',
      category: 'Good things',
      order: 2,
    ),
  ];
}
