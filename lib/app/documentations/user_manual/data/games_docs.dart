// lib/app/documentations/user_manual/data/games_docs.dart
//
// Documents the Games hub — the shared entry point, tone system, and session
// lifecycle behind Attune's games. Sourced from lib/architecture/GAMES.md.
// The individual games (This or That, Truth or Dare, 36 Questions) have
// their own docs elsewhere in this registry with the full play-by-play.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class GamesDocs implements DocumentationModule {
  @override
  int get order => 13;

  @override
  String getTitle(BuildContext context) => 'Games';

  @override
  String get id => 'games';

  @override
  String getSubtitle(BuildContext context) =>
      'Playful ways to connect with your partner';

  @override
  IconData get icon => Icons.stadium_outlined;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'games_overview',
      title: 'What Games are for',
      subtitle: 'Connection, not competition',
      icon: Icons.favorite_border,
      category: 'Games',
      order: 1,
      contents: [
        ManualContent(
          id: 'games_purpose',
          title: 'Play together, learn about each other',
          numberPrefix: '1',
          content:
              'Attune\'s Games are short, structured activities you and your partner play together — answering the same questions, comparing choices, and seeing where you match. They\'re designed to spark real conversation, not to score or rank you.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'games_list',
          title: 'Three games, three feels',
          content: '',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**This or That:** Quick binary choices, 10 rounds, see how often you pick the same thing.',
            '**Truth or Dare:** Alternate turns choosing a truth to answer or a dare to complete.',
            '**36 Questions:** A guided, three-level journey of increasingly personal questions, based on the well-known psychology study on closeness.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'games_tone',
      title: 'Choosing a tone',
      subtitle: 'Every game starts with how deep you want to go',
      icon: Icons.tune,
      category: 'Games',
      order: 2,
      contents: [
        ManualContent(
          id: 'games_tone_list',
          title: 'Five tones to pick from',
          content:
              'Before a game starts, you pick a tone that shapes the kinds of questions or dares you\'ll get:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '💙 **Connecting** — the default, warm and easygoing',
            '❤️ **Romantic** — about your relationship and feelings for each other',
            '😄 **Playful** — light, funny, low-stakes',
            '🔥 **Spicy** — flirtier and bolder',
            '🌙 **Intimate** — the most personal tone, with an extra check-in before it starts',
          ],
        ),
        ManualContent(
          id: 'games_intimate_consent',
          title: '',
          content:
              'Intimate tone always asks for your explicit confirmation before starting. If your partner invites you to an Intimate-tone game and you\'d rather not, you can decline and fall back to Spicy instead — no pressure either way.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'games_playing',
      title: 'How a game session works',
      subtitle: 'From invite to the final reveal',
      icon: Icons.play_circle_outline,
      category: 'Games',
      order: 3,
      contents: [
        ManualContent(
          id: 'games_invite',
          title: 'Starting a game',
          content:
              'Either partner can start a game from the Games hub. You choose the game, pick a tone, and send an invite. Your partner sees the game and tone before accepting, and can accept, decline, or (for Intimate) ask to play a gentler tone instead.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'games_answering',
          title: 'Answering rounds',
          content:
              'You and your partner each answer independently — you won\'t see your partner\'s answer until you\'ve both submitted yours for that round. You can change your answer any time before your partner has also answered.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'games_reveal',
          title: 'The reveal',
          content:
              'Once you\'ve both answered, the round reveals both choices side by side, with a simple indicator showing whether you matched. No score is kept against you — it\'s just a moment to see where you align and where you differ.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'games_remind',
          title: '',
          content:
              'If your partner hasn\'t answered yet, a "remind" button appears after a couple of hours so you can nudge them gently — it\'s limited to once every few hours so it never feels like nagging.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'games_pausing',
      title: 'Pausing and resuming',
      subtitle: 'Life happens — your game waits for you',
      icon: Icons.pause_circle_outline,
      category: 'Games',
      order: 4,
      contents: [
        ManualContent(
          id: 'games_resume',
          title: 'Games save your progress',
          content:
              'If you close the app mid-round, reopening it takes you right back to where you left off — your answer so far is preserved. A game only ends if it\'s been inactive for a full day, at which point it\'s marked as expired rather than lost, and you can simply start a fresh one.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'games_history',
          title: 'Looking back',
          content:
              'Completed games are saved to your history in the Games hub, so you can revisit rounds and reveals later. If you\'d rather not see a particular game in your own history, you can hide it — this only affects your view, never your partner\'s.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_games_score',
        question: 'Do Games keep score or rank us?',
        answer:
            'No. Games are about connection, not competition or scoring you against other couples. Matches are just a fun way to notice where you align — there\'s no leaderboard or grade attached.',
        category: 'Games',
        order: 1,
      ),
      FAQModel(
        id: 'faq_games_intimate_decline',
        question: 'What happens if I don\'t want to play the Intimate tone?',
        answer:
            'You\'re always free to decline. If your partner invites you to an Intimate-tone game, you can choose to play it at the Spicy tone instead, or not play that round at all — there\'s no pressure or penalty.',
        category: 'Games',
        order: 2,
      ),
      FAQModel(
        id: 'faq_games_change_answer',
        question: 'Can I change my answer after submitting?',
        answer:
            'Yes, as long as your partner hasn\'t submitted their answer for that round yet. Once you\'ve both answered, the round reveals and locks in.',
        category: 'Games',
        order: 3,
      ),
      FAQModel(
        id: 'faq_games_see_partner_first',
        question: 'Can I see my partner\'s answer before I submit mine?',
        answer:
            'No — answers stay hidden from each other until you\'ve both submitted for that round. That\'s intentional, so your answer is genuinely yours and not influenced by seeing theirs first.',
        category: 'Games',
        order: 4,
      ),
      FAQModel(
        id: 'faq_games_left_mid_game',
        question: 'What happens if I close the app in the middle of a game?',
        answer:
            'Nothing is lost. Reopening the app returns you right to where you left off, with your progress saved. A game only expires after a full day of no activity.',
        category: 'Games',
        order: 5,
      ),
      FAQModel(
        id: 'faq_games_hide_history',
        question: 'Can I hide a game from my history without my partner knowing?',
        answer:
            'Yes. Hiding a completed game only affects what you see in your own Games hub — your partner\'s view is unaffected.',
        category: 'Games',
        order: 6,
      ),
    ];
  }
}
