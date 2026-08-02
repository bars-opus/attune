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
      'A quick, playful showdown with a fun twist at the end';

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
      icon: Icons.flash_on_outlined,
      category: 'Paint Ball',
      order: 1,
      contents: [
        ManualContent(
          id: 'paintball_intro',
          title: 'A quick turn-based match',
          numberPrefix: '1',
          content:
              'Paint Ball is a fast, playful game — each of you starts with 3 lives, and you take turns firing paint splashes at each other. It\'s asynchronous, so you don\'t need to be online at the same time; each turn is recorded and you\'ll see the result whenever you check back in.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'paintball_tone',
          title: 'A playful game by default',
          content:
              'Paint Ball defaults to the Playful tone, with Connecting also available for a warmer feel. Spicy and Intimate tones aren\'t offered here — the combat framing combined with a forced prompt just isn\'t the right container for that level of content.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'paintball_playing',
      title: 'How to play',
      subtitle: 'Tap at the right moment',
      icon: Icons.touch_app_outlined,
      category: 'Paint Ball',
      order: 2,
      contents: [
        ManualContent(
          id: 'paintball_firing',
          title: 'Timing your shot',
          content:
              'On your turn, a target sweeps across the screen — tap while it\'s in the right window to land a hit. Miss the timing and your shot misses. It\'s a simple, forgiving mechanic built to keep the game feeling fast, not fiddly.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'paintball_lives',
          title: 'Losing lives',
          content:
              'A hit removes one of your opponent\'s three lives. Once someone reaches zero lives, that round is over.',
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
              'Whoever runs out of lives gets a single Truth or Dare-style prompt to complete — drawn from Attune\'s existing Truth or Dare content, keeping the same warm, familiar tone.',
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
            'No — those tones aren\'t offered for this game. Paint Ball\'s combat framing paired with a forced-choice moment isn\'t the right setting for that level of content, so it stays at Playful or Connecting.',
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
