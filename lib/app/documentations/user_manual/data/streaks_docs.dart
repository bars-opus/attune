// lib/app/documentations/user_manual/data/streaks_docs.dart
//
// Streaks: press-and-hold camera clips that are seen once (or up to three
// times) and then gone. Listed only while streak capture is on
// (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class StreaksDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Streaks';

  @override
  String get id => 'streaks';

  @override
  String getSubtitle(BuildContext context) =>
      'Quick camera moments your partner sees once, then they are gone';

  @override
  IconData get icon => Icons.photo_camera_outlined;

  @override
  int get order => 6;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'streak_send',
      title: 'Sending a streak',
      subtitle: 'Hold, record, send',
      icon: Icons.photo_camera_outlined,
      category: 'In the moment',
      order: 1,
      contents: [
        ManualContent(
          id: 'streak_where',
          title: 'Where to find it',
          numberPrefix: '1',
          content:
              'In Chat, with the message box empty, tap the camera next to it. Tap to take a photo, or press and hold to record a video. Long videos are split into parts of up to 60 seconds.',
        ),
        ManualContent(
          id: 'streak_review',
          title: 'Look before you send',
          numberPrefix: '2',
          content:
              'You see what you recorded before it goes. Send it, or cancel and nothing is sent.',
        ),
        ManualContent(
          id: 'streak_not_sent',
          title: 'If it does not send',
          numberPrefix: '3',
          content:
              'On a weak connection the streak keeps trying. If it cannot send, it shows "Not sent" with Retry, so you always know it did not reach your partner.',
        ),
      ],
    ),
    ManualSection(
      id: 'streak_view',
      title: 'Seen once, then gone',
      subtitle: 'What your partner gets',
      icon: Icons.visibility_outlined,
      category: 'In the moment',
      order: 2,
      contents: [
        ManualContent(
          id: 'streak_once',
          title: 'One view by default',
          numberPrefix: '1',
          content:
              'Your partner can watch a streak once. A view only counts once the photo or video is actually on their screen, so a slow connection never uses it up.',
        ),
        ManualContent(
          id: 'streak_replays',
          title: 'Replays, if you allow them',
          numberPrefix: '2',
          content:
              'Turn on Allow streak replays in chat settings and your partner can watch each streak you send up to 3 times.',
        ),
        ManualContent(
          id: 'streak_window',
          title: 'A 30-minute window',
          numberPrefix: '3',
          content:
              'Once your partner opens a streak, any views left can be used within the next 30 minutes. After that it reads "Opened" and can no longer be played.',
        ),
        ManualContent(
          id: 'streak_gone',
          title: 'Not kept',
          numberPrefix: '4',
          content:
              'When a streak has been watched or its time is up, the photo or video is deleted from Attune. Streaks are not part of Download my data.',
        ),
        ManualContent(
          id: 'streak_tip',
          title: '',
          content:
              'A streak is for the moment itself. For something you both want to keep, send a photo or video instead.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_streak_expired',
      question: 'Why does a streak say "Expired"?',
      answer:
          'It was opened but never shown, for example on a bad connection, and its 30 minutes ran out. Nobody saw it, and it cannot be played any more.',
      category: 'In the moment',
      order: 1,
    ),
    FAQModel(
      id: 'faq_streak_rewatch',
      question: 'Can I watch a streak I sent?',
      answer:
          'Yes, until your partner opens it. After that it is theirs to watch, within the same limits.',
      category: 'In the moment',
      order: 2,
    ),
  ];
}
