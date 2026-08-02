// lib/app/documentations/user_manual/data/truth_or_dare_docs.dart
//
// Documents the Truth or Dare game. Sourced from
// lib/architecture/TRUTH_OR_DARE.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class TruthOrDareDocs implements DocumentationModule {
  @override
  int get order => 14;

  @override
  String getTitle(BuildContext context) => 'Truth or Dare';

  @override
  String get id => 'truthOrDare';

  @override
  String getSubtitle(BuildContext context) =>
      'A classic game, reimagined for two people';

  @override
  IconData get icon => Icons.style_outlined;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'tod_how_it_works',
      title: 'How it works',
      subtitle: 'The app decides — not you',
      icon: Icons.casino_outlined,
      category: 'Truth or Dare',
      order: 1,
      contents: [
        ManualContent(
          id: 'tod_intro',
          title: 'The card decides',
          numberPrefix: '1',
          content:
              'Each round, you tap a face-down card. The app then randomly picks Truth or Dare for you — a genuine 50/50 chance, with no way to choose or re-roll. That unpredictability is the whole point: no more always picking Truth to play it safe.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_turns',
          title: 'Taking turns',
          content:
              'You and your partner alternate — one of you gets a card, completes it, then it\'s the other\'s turn. Ten rounds make up a full session, about 15 minutes.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_truth',
          title: 'If you get a Truth',
          content:
              'You\'ll see a question and a text box. Write your answer (up to 200 characters) and submit — your partner will see what you wrote once you do.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_dare',
          title: 'If you get a Dare',
          content:
              'You\'ll see an instruction to complete in real life. Once you\'ve done it, tap "Done" — your partner sees that you completed it, not a video or photo proof.',
          numberPrefix: '4',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'tod_skip',
      title: 'The skip',
      subtitle: 'One per person, and it\'s private',
      icon: Icons.visibility_off_outlined,
      category: 'Truth or Dare',
      order: 2,
      contents: [
        ManualContent(
          id: 'tod_skip_what',
          title: 'You get one skip per session',
          content:
              'If you get a Dare you\'d rather not do, you can skip it once per session — it swaps in a different Truth question instead, in the same tone.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_skip_private',
          title: '',
          content:
              'Your partner is never told you used a skip. They just see a Truth appear, no explanation attached. There\'s no skip count shown anywhere, even on the end screen — so using it never feels like it\'s being tracked against you.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'tod_custom',
      title: 'Writing your own',
      subtitle: 'Custom Truths and Dares, private by default',
      icon: Icons.edit_note,
      category: 'Truth or Dare',
      order: 3,
      contents: [
        ManualContent(
          id: 'tod_custom_create',
          title: 'Create your own questions',
          content:
              'You can write your own Truths or Dares (up to 200 characters) and choose a tone for them. When you create one, it starts out private to you — your partner won\'t see it unless you explicitly choose to share it.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_custom_report',
          title: 'Reporting a question',
          content:
              'If your partner shares a custom question you\'d rather not see again, you can report it. Since only the two of you ever see it, a single report is enough to pull it out of rotation right away — the creator gets a generic notice, not the specifics of why.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'tod_safety_privacy',
      title: 'Safety and your history',
      subtitle: 'What\'s kept, and what looks out for you',
      icon: Icons.shield_outlined,
      category: 'Truth or Dare',
      order: 4,
      contents: [
        ManualContent(
          id: 'tod_safety_check',
          title: 'A light safety check on Truth answers',
          content:
              'Truth answers pass through the same safety check used elsewhere in Attune. If something concerning comes up, the game doesn\'t interrupt or flag it to you — but the reader may quietly be shown supportive resources. This is a light-touch safety net, not moderation of your answers.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_history',
          title: 'What your session history shows',
          content:
              'Your Games history for Truth or Dare shows only the shape of a past session — date, tone, and how many Truths versus Dares — not the full answers themselves. Right after a session, you can still review the round details before moving on.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tod_disclosure',
          title: '',
          content:
              'Before you submit a Truth answer, the screen tells you plainly that it\'s stored in your game history and your partner will see it — no surprises about where your words go.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_tod_choose_type',
        question: 'Can I choose Truth or Dare myself?',
        answer:
            'No — the app picks randomly, 50/50, every time you tap the card. That\'s intentional: it removes the easy habit of always picking Truth and keeps things genuinely surprising.',
        category: 'Truth or Dare',
        order: 1,
      ),
      FAQModel(
        id: 'faq_tod_skip_visible',
        question: 'Will my partner know if I used my skip?',
        answer:
            'No. Skips are completely private — your partner just sees a Truth appear where a Dare would have been, with no indication a skip happened. Skip counts are never shown, even at the end of the session.',
        category: 'Truth or Dare',
        order: 2,
      ),
      FAQModel(
        id: 'faq_tod_skip_count',
        question: 'How many skips do I get?',
        answer:
            'One per person, per session. It can only be used on a Dare, and it swaps in a different Truth question at the same tone.',
        category: 'Truth or Dare',
        order: 3,
      ),
      FAQModel(
        id: 'faq_tod_custom_private',
        question: 'Are my custom questions visible to my partner automatically?',
        answer:
            'No. Every custom Truth or Dare you write starts private to you. Your partner only sees it if you explicitly choose to share it.',
        category: 'Truth or Dare',
        order: 4,
      ),
      FAQModel(
        id: 'faq_tod_dare_proof',
        question: 'Do I need to send proof I completed a Dare?',
        answer:
            'No. You just tap "Done" once you\'ve completed it in real life. Your partner sees a completion confirmation, not a required photo or video.',
        category: 'Truth or Dare',
        order: 5,
      ),
      FAQModel(
        id: 'faq_tod_history_full',
        question: 'Can I go back and read old Truth answers later?',
        answer:
            'Your saved session history shows only counts and tone, not the full answers. You can review full round details right after finishing a session, but the history list itself keeps only the metadata, not the content.',
        category: 'Truth or Dare',
        order: 6,
      ),
    ];
  }
}
