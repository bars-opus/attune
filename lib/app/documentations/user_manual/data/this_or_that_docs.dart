// lib/app/documentations/user_manual/data/this_or_that_docs.dart
//
// Documents the This or That game. Sourced from
// lib/architecture/THIS_OR_THAT.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ThisOrThatDocs implements DocumentationModule {
  @override
  int get order => 15;

  @override
  String getTitle(BuildContext context) => 'This or That';

  @override
  String get id => 'thisOrThat';

  @override
  String getSubtitle(BuildContext context) =>
      'Fast, fun binary choices — see how you match';

  @override
  IconData get icon => Icons.compare_arrows;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'tot_how_it_works',
      title: 'How it works',
      subtitle: 'Ten quick rounds, no wrong answers',
      icon: Icons.swap_horiz,
      category: 'This or That',
      order: 1,
      contents: [
        ManualContent(
          id: 'tot_intro',
          title: 'Pick one, see if you match',
          numberPrefix: '1',
          content:
              'Each round shows a simple either-or question — like "Pizza or Pasta?" You and your partner each pick independently, without seeing the other\'s choice first. Once you\'ve both answered, the reveal shows both picks side by side, with a simple indicator if you matched.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tot_length',
          title: 'Quick by design',
          content:
              'A full session is 10 rounds, usually around 5 minutes — short enough to play during a coffee break, with no pressure to get things "right." There are no wrong answers here.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tot_change_answer',
          title: '',
          content:
              'You can change your answer any time before your partner has also submitted theirs for that round.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'tot_choosing_source',
      title: 'Choosing what\'s next',
      subtitle: 'Preset questions or your own',
      icon: Icons.shuffle,
      category: 'This or That',
      order: 2,
      contents: [
        ManualContent(
          id: 'tot_source_turn',
          title: 'Taking turns choosing',
          content:
              'Between rounds, whoever\'s turn it is picks where the next question comes from: a random preset question, or a custom question — either your own or your partner\'s (if either of you has written and shared any).',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tot_source_fallback',
          title: '',
          content:
              'If you pick "custom" but there aren\'t any custom questions available for that choice, the app quietly falls back to a preset question and lets you know why — nothing gets stuck.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'tot_custom_questions',
      title: 'Writing your own questions',
      subtitle: 'Make the game personal',
      icon: Icons.edit_note,
      category: 'This or That',
      order: 3,
      contents: [
        ManualContent(
          id: 'tot_custom_what',
          title: 'Two options, your way',
          content:
              'You can create your own binary question with two custom options (and optional emoji for each) to make the game feel personal to your relationship — inside jokes, shared memories, anything you like.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tot_custom_sharing',
          title: 'Sharing and privacy',
          content:
              'By default, a custom question you create is shared with your partner so it can come up during play. You can choose to make one private instead, keeping it just for your own reference.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'tot_ending',
      title: 'Finishing a session',
      subtitle: 'Your match count, and one moment worth remembering',
      icon: Icons.flag_outlined,
      category: 'This or That',
      order: 4,
      contents: [
        ManualContent(
          id: 'tot_end_screen',
          title: 'The end screen',
          content:
              'After all 10 rounds, you\'ll see how many times you matched, plus one "most interesting pick" — usually the round where your answers differed most, or an especially memorable one. From there you can play again or try another game.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'tot_one_active',
          title: '',
          content:
              'You can only have one active This or That session with your partner at a time. If you try to start a new one while another is in progress, you\'ll be asked whether to resume the existing game or abandon it and start fresh.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_tot_see_partner_first',
        question: 'Can I see my partner\'s answer before I pick mine?',
        answer:
            'No — you each answer independently, and the reveal only happens once you\'ve both submitted. That keeps your pick genuinely your own.',
        category: 'This or That',
        order: 1,
      ),
      FAQModel(
        id: 'faq_tot_change_mind',
        question: 'Can I change my answer after picking?',
        answer:
            'Yes, as long as your partner hasn\'t submitted their answer yet for that round. Once you\'ve both answered, the round locks in and reveals.',
        category: 'This or That',
        order: 2,
      ),
      FAQModel(
        id: 'faq_tot_low_match',
        question: 'What if we don\'t match very often?',
        answer:
            'That\'s completely normal, and there\'s no penalty for it. This or That isn\'t about scoring high — differing answers are often the most interesting conversation starters.',
        category: 'This or That',
        order: 3,
      ),
      FAQModel(
        id: 'faq_tot_custom_default',
        question: 'Are my custom questions shared with my partner automatically?',
        answer:
            'By default, yes — custom questions are shared so they can appear during play. You can mark one as private if you\'d rather keep it to yourself.',
        category: 'This or That',
        order: 4,
      ),
      FAQModel(
        id: 'faq_tot_second_game',
        question: 'Can we play a second game while one is already going?',
        answer:
            'Not for This or That specifically — only one session can be active with your partner at a time. You\'ll be offered the choice to resume the existing one or abandon it and start a new game.',
        category: 'This or That',
        order: 5,
      ),
    ];
  }
}
