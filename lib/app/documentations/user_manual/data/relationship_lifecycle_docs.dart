// lib/app/documentations/user_manual/data/relationship_lifecycle_docs.dart
//
// Pausing, ending, the 30-day window, sealing and archiving (Specs 3a, 3b,
// 3c). Facts from supabase/migrations/20261018100000..., the lifecycle
// card and sheet, and the pause/end confirmations. There is no manual
// "delete a chapter" control: deletion is automatic at 12 months.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class RelationshipLifecycleDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Pausing, ending and your space';

  @override
  String get id => 'relationshipLifecycle';

  @override
  String getSubtitle(BuildContext context) =>
      'What happens to your shared space if you pause or end it';

  @override
  IconData get icon => Icons.hourglass_empty_outlined;

  @override
  int get order => 3;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'lifecycle_pause',
      title: 'Pausing',
      subtitle: 'Time out, without ending anything',
      icon: Icons.pause_circle_outline,
      category: 'Your space',
      order: 1,
      contents: [
        ManualContent(
          id: 'lifecycle_pause_how',
          title: 'Either of you can pause',
          numberPrefix: '1',
          content:
              'Go to Settings → "Pause our shared space". Your partner won\'t get a notification.',
        ),
        ManualContent(
          id: 'lifecycle_pause_what',
          title: 'What a pause does',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Chat becomes read-only for both of you: you can read, not send.',
            'Nothing new is shared — no reactions, places, ticks or "here now" signals.',
            'Pending notifications and reminders for your space stop.',
            'Calendar links keep working until the space ends.',
            'Paint Ball, Word Hunt and Snakes and Ladders end; other games wait.',
          ],
        ),
        ManualContent(
          id: 'lifecycle_pause_decide',
          title: '30 days to decide',
          numberPrefix: '3',
          content:
              'Either of you can resume or end it within 30 days. The Chat screen shows how many days are left. If neither of you decides, the space ends on its own after 30 days.',
        ),
      ],
    ),
    ManualSection(
      id: 'lifecycle_end',
      title: 'Ending',
      subtitle: 'Quietly, and with time to read',
      icon: Icons.door_front_door_outlined,
      category: 'Your space',
      order: 2,
      contents: [
        ManualContent(
          id: 'lifecycle_end_how',
          title: 'Either of you can end it, alone',
          numberPrefix: '1',
          content:
              'Go to Settings → "End relationship". Your partner won\'t get a notification. The next time they open Attune, they see a short note that the shared space has ended — with no reason and no way to reply.',
        ),
        ManualContent(
          id: 'lifecycle_end_window',
          title: '30 days to read',
          numberPrefix: '2',
          content:
              'After an ending, you can both still read your chat for 30 days. In that time you can download what you shared (Settings → Download my data).',
        ),
        ManualContent(
          id: 'lifecycle_end_seal',
          title: 'Seal your side now',
          numberPrefix: '3',
          content:
              'If you don\'t want the 30 days, choose "Seal my side now". Your chat closes for you straight away and can\'t be opened again. It closes only for you — your partner keeps their 30 days unless they seal too. Download first if you want a copy.',
        ),
        ManualContent(
          id: 'lifecycle_end_healing',
          title: '',
          content:
              'After an ending, Healing is there to help you make sense of it, privately and at your own pace.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'lifecycle_after',
      title: 'After the 30 days',
      subtitle: 'Closed, then deleted',
      icon: Icons.archive_outlined,
      category: 'Your space',
      order: 3,
      contents: [
        ManualContent(
          id: 'lifecycle_after_list',
          title: 'When a space closes',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '30 days after an ending, or when you have both sealed.',
            'Straight away if either of you starts a new relationship on Attune.',
          ],
        ),
        ManualContent(
          id: 'lifecycle_after_delete',
          title: 'Deleted after 12 months',
          numberPrefix: '2',
          content:
              'A closed space is deleted 12 months after it closes, photos included. What stays is only yours: your own journal, check-ins, insights and Healing.',
        ),
        ManualContent(
          id: 'lifecycle_after_new',
          title: '',
          content:
              'To start a new relationship on Attune, end your current one first. Opening someone else\'s invite while you are in an active or paused space won\'t accept it.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_lifecycle_notify',
      question: 'Will my partner be notified if I pause or end?',
      answer:
          'No. Neither a pause nor an ending sends a notification, text or email. They find out the next time they open Attune.',
      category: 'Your space',
      order: 1,
    ),
    FAQModel(
      id: 'faq_lifecycle_sealed',
      question: 'Does my partner know if I sealed my side?',
      answer:
          'No. Sealing closes the chat for you only, and nothing tells them you did it.',
      category: 'Your space',
      order: 2,
    ),
    FAQModel(
      id: 'faq_lifecycle_resume',
      question: 'Can we undo an ending?',
      answer:
          'An ending can\'t be undone. A pause can be resumed by either of you within its 30 days.',
      category: 'Your space',
      order: 3,
    ),
    FAQModel(
      id: 'faq_lifecycle_previous',
      question: 'Where do I find a chat that has ended?',
      answer:
          'During its 30 days it is under Previous relationships, read-only. Once it closes it is no longer shown.',
      category: 'Your space',
      order: 4,
    ),
  ];
}
