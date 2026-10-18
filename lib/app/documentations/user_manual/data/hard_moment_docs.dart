// lib/app/documentations/user_manual/data/hard_moment_docs.dart
//
// "In a hard moment" — the conflict toolkit in Chat (Spec 8, research 06
// B3; 05 Part C). Listed only while conflict_toolkit and
// private_safety_check are on (DocumentationRegistry). Describes what each
// tool does and never does; quotes only reviewed wording (the first pause
// message, the reply, the repair phrases), never a [DRAFT] text.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class HardMomentDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'In a hard moment';

  @override
  String get id => 'hardMoment';

  @override
  String getSubtitle(BuildContext context) =>
      'A pause, a repair, an apology or a gentler start — in your own words';

  @override
  IconData get icon => Icons.self_improvement_outlined;

  @override
  int get order => 7;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'hard_moment_what',
      title: 'What this is',
      subtitle: 'Four small tools for when things get heated',
      icon: Icons.self_improvement_outlined,
      category: 'Hard moments',
      order: 1,
      contents: [
        ManualContent(
          id: 'hard_moment_where',
          title: 'Where to find it',
          numberPrefix: '1',
          content:
              'In Chat, tap the attach button and choose "In a hard moment". You get four tools: Take a pause, Repair, Help me apologise and Start a conversation. You can also long-press the send button to open Repair straight away.',
        ),
        ManualContent(
          id: 'hard_moment_never_sends',
          title: '',
          content:
              'Nothing here sends on its own. Repair, apology and conversation tools only fill in your message box — you can change every word, or not send it at all. Take a pause sends one fixed message, and only when you tap Send.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'hard_moment_pause',
      title: 'Take a pause',
      subtitle: 'Step back, with a time to come back',
      icon: Icons.timer_outlined,
      category: 'Hard moments',
      order: 2,
      contents: [
        ManualContent(
          id: 'hard_moment_pause_how',
          title: 'A message that names your return',
          numberPrefix: '1',
          content:
              'Choose one of three short messages and tap Send. Each one says you are stepping back for a set time and that you will come back — for example: "I\'m getting flooded. I\'m stepping back for 30 minutes, not away from you. I\'ll come back." It arrives as an ordinary message.',
        ),
        ManualContent(
          id: 'hard_moment_pause_timer',
          title: 'A timer only you can see',
          numberPrefix: '2',
          content:
              'A small card above your message box counts down your break, with a reminder to do something calming. When the time is up it says "Time to check back in" and offers Start a conversation. Your partner never sees a timer.',
        ),
        ManualContent(
          id: 'hard_moment_pause_reply',
          title: 'One optional reply',
          numberPrefix: '3',
          content:
              'Your partner may see a one-tap reply under your pause: "Okay. I\'ll be here." It is offered once, for up to an hour, and only until they write anything else. They never have to use it.',
        ),
        ManualContent(
          id: 'hard_moment_pause_research',
          title: '',
          content:
              'A break of twenty minutes or more, with a stated return, lets the body settle after a heated moment. Saying when you\'ll be back is what keeps a pause from feeling like walking away.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'hard_moment_repair',
      title: 'Repair',
      subtitle: 'A short line to soften things',
      icon: Icons.healing_outlined,
      category: 'Hard moments',
      order: 3,
      contents: [
        ManualContent(
          id: 'hard_moment_repair_list',
          title: 'Six phrases to start from',
          numberPrefix: '1',
          content: 'Tap one and it is added to your message:',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Can we start over?',
            'I see my part in this.',
            'That came out wrong.',
            'I\'m on your side, even now.',
            'Can we slow down?',
            'I need a minute, then I\'m back.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'hard_moment_apology',
      title: 'Help me apologise',
      subtitle: 'In your own words',
      icon: Icons.edit_note_outlined,
      category: 'Hard moments',
      order: 4,
      contents: [
        ManualContent(
          id: 'hard_moment_apology_fields',
          title: 'Four short prompts',
          numberPrefix: '1',
          content:
              'Fill in as many as you like; the first is the only one you need:',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**What I did**',
            '**What it cost you**',
            '**What I\'ll do to repair it**',
            '**One thing I\'ll do differently**',
          ],
        ),
        ManualContent(
          id: 'hard_moment_apology_action',
          title: '',
          content:
              'A promise isn\'t a repair; an action is. The apology never asks for forgiveness, and your partner is never asked to accept it — there is no "forgiven" button and no record that you apologised.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'hard_moment_start',
      title: 'Start a conversation',
      subtitle: 'What happened, how it felt, what you need',
      icon: Icons.forum_outlined,
      category: 'Hard moments',
      order: 5,
      contents: [
        ManualContent(
          id: 'hard_moment_start_how',
          title: 'A gentler first sentence',
          numberPrefix: '1',
          content:
              'Write what happened ("When…") and how it felt ("I feel…"). Then, if you like, pick a need and say what you\'re asking for. The app joins them into one sentence for your message box.',
        ),
        ManualContent(
          id: 'hard_moment_start_tip',
          title: '',
          content:
              'Describe what happened, not who they are. "When plans change at the last minute, I feel unsettled" opens a conversation; "You always ruin plans" closes one.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'hard_moment_never',
      title: 'What never happens',
      subtitle: 'No counts, no records, no scoreboard',
      icon: Icons.block_flipped,
      category: 'Hard moments',
      order: 6,
      contents: [
        ManualContent(
          id: 'hard_moment_never_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Nothing counts how often either of you paused, repaired or apologised.',
            'Your partner is never told which tool you used.',
            'A pause and its reply are never read by Attune\'s AI and never affect Pulse.',
            'No tool appears on its own or nudges you to use it.',
          ],
        ),
        ManualContent(
          id: 'hard_moment_outside',
          title: '',
          content:
              'If a disagreement keeps coming back, or you feel unsafe, the menu in each tool links to "A trained outside perspective" and to Safety resources.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_hard_moment_partner',
      question: 'Does my partner see that I used one of these tools?',
      answer:
          'Only what you choose to send. A pause arrives as an ordinary message; anything from Repair, Help me apologise or Start a conversation is just text in your message, which you can edit or delete before sending. No label, count or notification says a tool was used.',
      category: 'Hard moments',
      order: 1,
    ),
    FAQModel(
      id: 'faq_hard_moment_reply_missing',
      question:
          'Why don\'t I see "Okay. I\'ll be here." under my partner\'s pause?',
      answer:
          'The reply is offered for an hour after the pause, and only until you write something else. After that it disappears — you can always reply in your own words.',
      category: 'Hard moments',
      order: 2,
    ),
    FAQModel(
      id: 'faq_hard_moment_timer',
      question: 'Can I end my pause early?',
      answer:
          'Yes. Tap "End now" on the card above your message box. The timer lives only on your phone, so nobody else sees it start or stop.',
      category: 'Hard moments',
      order: 3,
    ),
    FAQModel(
      id: 'faq_hard_moment_edit',
      question: 'Can I edit a pause after sending it?',
      answer:
          'No — pause messages and their reply can\'t be edited, so they always say exactly what was chosen. You can delete one, like any message.',
      category: 'Hard moments',
      order: 4,
    ),
  ];
}
