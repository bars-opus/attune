// lib/app/documentations/user_manual/data/healing_docs.dart
//
// Documents Healing Mode. Sourced from
// lib/architecture/HEALING_MODE_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class HealingDocs implements DocumentationModule {
  @override
  int get order => 8;

  @override
  String getTitle(BuildContext context) => 'Healing Mode';

  @override
  String get id => 'healing';

  @override
  String getSubtitle(BuildContext context) =>
      'A private, self-paced journey after a relationship ends';

  @override
  IconData get icon => Icons.self_improvement_outlined;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'healing_what_it_is',
      title: 'What Healing Mode is',
      subtitle: 'Not therapy — a private way to make sense of things',
      icon: Icons.spa_outlined,
      category: 'Healing Mode',
      order: 1,
      contents: [
        ManualContent(
          id: 'healing_purpose',
          title: 'A private journey, at your own pace',
          numberPrefix: '1',
          content:
              'Healing Mode helps you make meaning from a relationship that\'s ended — noticing your own patterns, reflecting honestly, and deciding for yourself whether and when you feel ready to date again. It\'s entirely private: your former partner is never notified that you\'ve started it, how far you\'ve gotten, or what you\'ve written.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'healing_not_therapy',
          title: '',
          content:
              'Healing Mode is not therapy, treatment, or a clinical diagnosis. It doesn\'t tell you who was right, assign blame, or guess at what your former partner was thinking or feeling.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'healing_who',
          title: 'Available even without a past Attune relationship',
          content:
              'If you\'re processing a recent breakup that didn\'t happen on Attune, you can still start a journey using a self-reported date. And if you\'re not coming out of a relationship at all, you can take a shorter readiness-only journey instead — it\'s never labeled as "healing" and skips anything that assumes a past relationship.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'healing_stages',
      title: 'The five stages',
      subtitle: 'Sequential, but always at your own pace',
      icon: Icons.timeline,
      category: 'Healing Mode',
      order: 2,
      contents: [
        ManualContent(
          id: 'healing_stage_list',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**1. Reflection:** Three optional private journal prompts — nothing is required, and you can leave any of them blank.',
            '**2. Relationship reflection:** One grounded, non-blaming observation drawn from your own answers — shown only when there\'s genuinely enough to say something meaningful.',
            '**3. Pattern awareness:** A look at your own quiz-based tendencies, clearly labeled as self-report, never presented as a fixed diagnosis.',
            '**4. Personal pattern portrait:** A short, tentative synthesis focused entirely on you — never your former partner.',
            '**5. Readiness check-in:** A short set of self-report questions reflecting how you feel today, not a test you can pass or fail.',
          ],
        ),
        ManualContent(
          id: 'healing_pause',
          title: '',
          content:
              'You can pause and come back to any stage whenever you\'re ready — there\'s no penalty or time pressure for taking a break.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'healing_privacy',
      title: 'What stays private',
      subtitle: 'Strict boundaries, by design',
      icon: Icons.lock_outline,
      category: 'Healing Mode',
      order: 3,
      contents: [
        ManualContent(
          id: 'healing_boundaries',
          title: 'Only your own data, ever',
          content:
              'Healing Mode only ever draws on things that belong to you: your own reflections, your own quiz results, and neutral, de-identified patterns — never your former partner\'s private messages, journal entries, or profile. Nothing here ever enables contact with a former partner, and an ended chat stays exactly as read-only as it already was.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'healing_safety_resources',
          title: '',
          content:
              'Safety resources and the quick-exit gesture remain available on every screen throughout Healing Mode, exactly like everywhere else in the app.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'healing_dating_readiness',
      title: 'When Dating Mode becomes available',
      subtitle: 'A gate, not a race',
      icon: Icons.hourglass_bottom,
      category: 'Healing Mode',
      order: 4,
      contents: [
        ManualContent(
          id: 'healing_gate_explained',
          title: 'Why there\'s a waiting period',
          content:
              'Completing the journey doesn\'t automatically unlock Dating Mode. There\'s a minimum waiting period after your relationship ended (around 8 weeks) and a readiness score that needs to reflect genuine readiness, not just finishing the steps quickly. This exists because rushing back into dating right after a breakup carries real, well-documented risk — the gate exists to protect you, not to slow you down for its own sake.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'healing_score_not_verdict',
          title: '',
          content:
              'Your readiness score reflects how you answered today — it\'s not a permanent verdict on you, and it can change as you do.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'healing_dating_consent_separate',
          title: 'Dating Mode still requires its own consent',
          content:
              'Becoming eligible for Dating Mode is not the same as joining it. If and when Dating Mode is available to you, you\'ll be asked for a separate, explicit opt-in — and your former partner\'s data is never used for matching, no matter what.',
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
        id: 'faq_healing_partner_notified',
        question: 'Will my former partner know I\'m using Healing Mode?',
        answer:
            'No, never. Your former partner is never told that you\'ve started a journey, how far along you are, what you\'ve written, or your readiness score.',
        category: 'Healing Mode',
        order: 1,
      ),
      FAQModel(
        id: 'faq_healing_no_attune_relationship',
        question:
            'Can I use Healing Mode for a breakup that didn\'t happen on Attune?',
        answer:
            'Yes. You can self-report the date of a recent breakup and start a journey — some stages will rely on your own reflection rather than couple-based evidence, since there\'s no Attune relationship data to draw from.',
        category: 'Healing Mode',
        order: 2,
      ),
      FAQModel(
        id: 'faq_healing_never_partnered',
        question:
            'I\'ve never had a relationship on Attune — can I still use this?',
        answer:
            'Yes, through the readiness-only journey. It\'s a shorter path that skips anything assuming a past relationship, and it\'s never labeled as "healing" since there\'s nothing to heal from.',
        category: 'Healing Mode',
        order: 3,
      ),
      FAQModel(
        id: 'faq_healing_diagnosis',
        question: 'Does Healing Mode diagnose me or my relationship?',
        answer:
            'No. It never uses clinical labels, never assigns blame, and never claims to know what your former partner was thinking or feeling. It offers tentative, evidence-grounded observations about you, always with room for you to disagree.',
        category: 'Healing Mode',
        order: 4,
      ),
      FAQModel(
        id: 'faq_healing_skip',
        question: 'What if I don\'t want to answer some of the prompts?',
        answer:
            'That\'s completely fine. Reflection prompts are optional, and you can complete a stage with empty answers after confirming. Nothing is required to move forward.',
        category: 'Healing Mode',
        order: 5,
      ),
      FAQModel(
        id: 'faq_healing_dating_automatic',
        question: 'Does finishing the journey put me straight into Dating Mode?',
        answer:
            'No. Completing all five stages makes you potentially eligible, but entering Dating Mode always requires a separate, explicit opt-in and its own consent — nothing happens automatically.',
        category: 'Healing Mode',
        order: 6,
      ),
    ];
  }
}
