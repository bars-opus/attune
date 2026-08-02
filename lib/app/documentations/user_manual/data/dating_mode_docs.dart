// lib/app/documentations/user_manual/data/dating_mode_docs.dart
//
// Documents Dating Mode. Sourced from lib/architecture/DATING_MODE_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class DatingModeDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Dating Mode';

  @override
  String get id => 'datingMode';

  @override
  String getSubtitle(BuildContext context) =>
      'A small number of thoughtful introductions, never a swipe deck';

  @override
  IconData get icon => Icons.favorite_border;

  @override
  int get order => 21;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'dating_what_it_is',
      title: 'What Dating Mode is',
      subtitle: 'Psychology-first, not a browsing pool',
      icon: Icons.explore_outlined,
      category: 'Dating Mode',
      order: 1,
      contents: [
        ManualContent(
          id: 'dating_intro',
          title: 'A small set of curated introductions',
          numberPrefix: '1',
          content:
              'Dating Mode offers a small number of thoughtful candidate introductions, drawn from your own eligible data — never an endless swipeable feed. There\'s no browsing pool, no match counters, and no streaks or scarcity timers pushing you to act.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_not_prediction',
          title: '',
          content:
              'Dating Mode is not a clinical assessment. It doesn\'t predict chemistry, safety, or whether a relationship will work — it offers a starting point, grounded in real data, and nothing more.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'dating_who',
          title: 'Who can access it',
          content:
              'Dating Mode only becomes available once you\'re eligible through Healing Mode — a genuine waiting period and readiness check-in, not something you can skip. Being eligible still requires a separate, explicit opt-in of its own before anything activates.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_alignment_preview',
      title: 'The Alignment preview',
      subtitle: 'Bands, not a fake percentage',
      icon: Icons.insights_outlined,
      category: 'Dating Mode',
      order: 2,
      contents: [
        ManualContent(
          id: 'dating_alignment_what',
          title: 'What it shows',
          content:
              'Before a photo, each introduction shows an Alignment preview — plain-language observations like "you both described preferring direct communication," always sourced to your own data, never invented.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_no_percentage',
          title: '',
          content:
              'You won\'t see a made-up compatibility percentage like "84% match." Instead, alignment is shown in honest bands — such as "promising shared ground" — because a precise-looking number would imply more certainty than the data can actually support.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'dating_love_language_excluded',
          title: '',
          content:
              'Love language results are never used to judge compatibility here — they might personalize your own first-date guide, but they\'re never treated as evidence that two people fit.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_interest',
      title: 'Expressing interest',
      subtitle: 'Double-blind, so rejection is never public',
      icon: Icons.visibility_off_outlined,
      category: 'Dating Mode',
      order: 3,
      contents: [
        ManualContent(
          id: 'dating_double_blind',
          title: 'No one sees a rejection',
          content:
              'When you mark someone as "Interested" or "Not for me," that response is private. Neither of you can see whether the other person has responded, and there are no "they liked you" teasers or admirer queues to unlock. A match only ever appears once both people have independently expressed interest.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_former_partner',
          title: 'Former partners are excluded',
          content:
              'A former Attune partner is never shown to you as a dating introduction — this exclusion is designed to hold even if they later delete and recreate their account.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_after_match',
      title: 'After a mutual match',
      subtitle: 'A guide, real safety reminders, and your own pace',
      icon: Icons.handshake_outlined,
      category: 'Dating Mode',
      order: 4,
      contents: [
        ManualContent(
          id: 'dating_match_reveal',
          title: 'When it happens',
          content:
              'Once you\'ve both expressed interest, you\'re notified simultaneously and can open a dedicated conversation — separate from your regular Attune chat, with its own block, report, and unmatch controls always available.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_first_date_guide',
          title: 'A guide for your first conversation',
          content:
              'After matching, you can open a private guide with neutral conversation starters and one gentle area worth approaching with curiosity — never labeled as "something to avoid" or hinting at anything private about the other person.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_safety_reminders',
          title: '',
          content:
              'The guide also includes real safety reminders: meeting in public first, keeping your own transport, letting someone you trust know your plans — and a direct warning to never send money or account details to someone you haven\'t met in person, no matter the story. Romance scams are a real risk, and Attune takes it seriously.',
          type: ManualContentType.warning,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_control',
      title: 'You\'re always in control',
      subtitle: 'Pause, block, or leave whenever you want',
      icon: Icons.pause_circle_outline,
      category: 'Dating Mode',
      order: 5,
      contents: [
        ManualContent(
          id: 'dating_pause',
          title: 'Pausing or leaving',
          content:
              'You can pause Dating Mode at any time — this immediately stops you from being shown as a new introduction to anyone. Leaving entirely removes friction-free; there\'s no retention step designed to talk you out of it.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_blocking',
          title: '',
          content:
              'Blocking someone is immediate and quiet — the other person is never told they\'ve been blocked, and it prevents any future pairing between you.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'dating_not_auto_relationship',
          title: '',
          content:
              'A mutual match on its own never creates an official Attune relationship — moving from Dating Mode into Couples Mode is always a separate, mutual, deliberate step.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_dating_when_available',
        question: 'When can I access Dating Mode?',
        answer:
            'Only after you\'re eligible through Healing Mode — which requires a genuine waiting period after a breakup and a readiness check-in reflecting real readiness, not just finishing steps quickly. Eligibility alone doesn\'t enroll you either; you\'ll still need to explicitly opt in.',
        category: 'Dating Mode',
        order: 1,
      ),
      FAQModel(
        id: 'faq_dating_swipe',
        question: 'Is Dating Mode a swiping app?',
        answer:
            'No. There\'s no swipe deck, no browsable pool, and no match counters or streaks. You receive a small number of curated introductions instead.',
        category: 'Dating Mode',
        order: 2,
      ),
      FAQModel(
        id: 'faq_dating_percentage',
        question: 'Why don\'t I see a compatibility percentage?',
        answer:
            'A precise number like "84% match" would claim more certainty than the underlying data can actually support. Instead, alignment is shown in honest bands, like "promising shared ground."',
        category: 'Dating Mode',
        order: 3,
      ),
      FAQModel(
        id: 'faq_dating_rejection_visible',
        question: 'Will someone know if I passed on their introduction?',
        answer:
            'No — interest is double-blind. Neither person can see whether the other responded, and there\'s no rejection notification. A match only appears when you\'ve both independently expressed interest.',
        category: 'Dating Mode',
        order: 4,
      ),
      FAQModel(
        id: 'faq_dating_ex_shown',
        question: 'Could I be introduced to a former Attune partner?',
        answer:
            'No — former partners are specifically excluded from your introductions, by design, even accounting for the case where they leave and rejoin Attune later.',
        category: 'Dating Mode',
        order: 5,
      ),
      FAQModel(
        id: 'faq_dating_love_language',
        question:
            'Does my love language affect who I\'m matched with?',
        answer:
            'No. Love language results are never used as evidence of compatibility — they may personalize your own guidance, but they never factor into who you\'re introduced to.',
        category: 'Dating Mode',
        order: 6,
      ),
      FAQModel(
        id: 'faq_dating_money_request',
        question:
            'A match is asking me to send money — is that normal?',
        answer:
            'No — never send money, account details, or mobile-money transfers to someone you haven\'t met in person, regardless of the reason given. Please report it immediately using the report option in your conversation.',
        category: 'Dating Mode',
        order: 7,
      ),
      FAQModel(
        id: 'faq_dating_auto_relationship',
        question:
            'Does matching automatically start an Attune relationship?',
        answer:
            'No. A mutual match only opens a dating conversation. Moving into an official Couples relationship on Attune always requires a separate, deliberate step from both of you.',
        category: 'Dating Mode',
        order: 8,
      ),
    ];
  }
}
