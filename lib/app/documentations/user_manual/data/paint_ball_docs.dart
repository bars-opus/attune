// lib/app/documentations/user_manual/data/paint_ball_docs.dart
//
// Documents the Paint Ball game. Sourced from
// lib/architecture/PAINT_BALL_GAME_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class PaintBallDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Paint Ball';

  @override
  String get id => 'paintBall';

  @override
  String getSubtitle(BuildContext context) =>
      'A playful guessing game about reading your partner';

  @override
  IconData get icon => Icons.sports_esports_outlined;

  @override
  int get order => 17;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'paintball_what_it_is',
      title: 'What it is',
      subtitle: 'Fast, light, and a little suspenseful',
      icon: Icons.sports_esports_outlined,
      category: 'Paint Ball',
      order: 1,
      contents: [
        ManualContent(
          id: 'paintball_intro',
          title: 'A quick turn-based match',
          numberPrefix: '1',
          content:
              'Paint Ball is a playful prediction game. Each of you starts with 3 lives. On every turn you choose where to hide and where you think your partner hid, then the server reveals whether you read them correctly. It is asynchronous, so you do not need to be online at the same time.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'paintball_tone',
          title: 'A playful game by default',
          content:
              'Paint Ball defaults to Playful, with Connecting and Romantic available for a warmer ending prompt. Spicy and Intimate are not offered here.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'paintball_playing',
      title: 'How to play',
      subtitle: 'Hide, predict, and learn their pattern',
      icon: Icons.shield_outlined,
      category: 'Paint Ball',
      order: 2,
      contents: [
        ManualContent(
          id: 'paintball_firing',
          title: 'Choose two positions',
          content:
              'On your turn, choose one of three shields to hide behind and one of your partner\'s three shields to target. Both choices are submitted together. Your shot hits only when it matches the place your partner chose on their previous turn.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'paintball_lives',
          title: 'Opening move and lives',
          content:
              'The first shot is a free opening because your partner has not hidden yet. After that, a hit removes one life and a miss removes none. The reveal tells you where your partner really was, giving you a clue for your next guess.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'paintball_penalty',
      title: 'The penalty',
      subtitle: 'A fun consequence, never a forced one',
      icon: Icons.card_giftcard_outlined,
      category: 'Paint Ball',
      order: 3,
      contents: [
        ManualContent(
          id: 'paintball_penalty_what',
          title: 'One Truth or Dare prompt',
          content:
              'Whoever runs out of lives receives one Truth or Dare prompt drawn from Attune\'s existing prompt system, with the same tone and moderation rules used everywhere else in the app.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'paintball_declinable',
          title: '',
          content:
              'You can always decline the penalty with zero consequence — there\'s no punishment, no note, and nothing tracked against you for skipping it. It\'s there for fun, never as pressure.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_paintball_online',
        question: 'Do we both need to be online at the same time to play?',
        answer:
            'No — Paint Ball is asynchronous. You take turns whenever it\'s convenient, and you\'ll see the result the next time you check the game, whether or not your partner is currently online.',
        category: 'Paint Ball',
        order: 1,
      ),
      FAQModel(
        id: 'faq_paintball_decline_penalty',
        question: 'What happens if I decline the penalty prompt?',
        answer:
            'Nothing bad — declining is always an option with no consequence attached. The penalty is meant to be a fun moment, not something you\'re forced into.',
        category: 'Paint Ball',
        order: 2,
      ),
      FAQModel(
        id: 'faq_paintball_intimate_tone',
        question: 'Can we play Paint Ball at the Spicy or Intimate tone?',
        answer:
            'No. Paint Ball offers Playful, Connecting, and Romantic. Its final prompt is always optional, but Spicy and Intimate are still kept out of this game.',
        category: 'Paint Ball',
        order: 3,
      ),
      FAQModel(
        id: 'faq_paintball_lose_progress',
        question: 'What happens if I close the app mid-match?',
        answer:
            'Your progress is safe — lives and turns are tracked on the server, so reopening the app shows you exactly where the match stands.',
        category: 'Paint Ball',
        order: 4,
      ),
    ];
  }
}
