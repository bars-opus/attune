// lib/app/documentations/user_manual/data/pulse_docs.dart
//
// Documents Pulse (score + Timeline). Sourced from
// lib/architecture/PULSE.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class PulseDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Pulse';

  @override
  String get id => 'pulse';

  @override
  String getSubtitle(BuildContext context) =>
      'Your relationship\'s weekly health picture, built from real moments';

  @override
  IconData get icon => Icons.favorite_outline;

  @override
  int get order => 5;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'pulse_score_what',
      title: 'What Pulse Score is',
      subtitle: 'Five dimensions, one weekly picture',
      icon: Icons.monitor_heart_outlined,
      category: 'Pulse',
      order: 1,
      contents: [
        ManualContent(
          id: 'pulse_intro',
          title: 'A picture built from real data',
          numberPrefix: '1',
          content:
              'Your Pulse Score is a weekly snapshot of your relationship, built from things that actually happened — moments you\'ve logged, check-ins you\'ve completed, and (over time) more sources as you use the app. It\'s recalculated every week, so it reflects where things stand now, not a permanent grade.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'pulse_dimensions',
          title: 'The five dimensions',
          content: '',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Communication** — how clearly and kindly you express things and respond to each other.',
            '**Connection** — emotional closeness and active investment in the relationship.',
            '**Conflict Health** — not whether you disagree, but how well disagreements get handled.',
            '**Alignment** — whether you feel like you\'re moving in the same direction.',
            '**Emotional Safety** — whether you both feel safe being vulnerable and being yourselves.',
          ],
        ),
        ManualContent(
          id: 'pulse_confidence',
          title: '',
          content:
              'Early on, some dimensions show lower confidence simply because there isn\'t much data yet — that\'s honesty, not a bad score. Confidence grows naturally as you use the app more.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'timeline_what',
      title: 'The Timeline',
      subtitle: 'Your shared relationship story',
      icon: Icons.timeline,
      category: 'Pulse',
      order: 2,
      contents: [
        ManualContent(
          id: 'timeline_intro',
          title: 'A shared, visible log',
          content:
              'The Timeline is where you and your partner log moments — milestones, highlights, conflicts you\'ve worked through, firsts, anniversaries. Every moment either of you logs is visible to both of you right away; there are no private moments here.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'timeline_types',
          title: 'Types of moments',
          content: '',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Milestone** — a meaningful step forward together',
            '**Highlight** — a moment worth remembering',
            '**Conflict** — a disagreement, especially one you worked through',
            '**First** — the first time something happened',
            '**Anniversary** — a date worth marking',
          ],
        ),
        ManualContent(
          id: 'timeline_edit',
          title: '',
          content:
              'Only the person who logged a moment can edit or delete it. Deleting is permanent and always asks for confirmation first.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'pulse_checkin',
      title: 'The weekly check-in',
      subtitle: 'A quick, honest pulse-taking',
      icon: Icons.checklist_outlined,
      category: 'Pulse',
      order: 3,
      contents: [
        ManualContent(
          id: 'checkin_what',
          title: 'A few minutes, once a week',
          content:
              'A short weekly check-in feeds directly into your Pulse Score — it\'s the most direct way to make sure the score reflects how things actually feel to you, not just what got logged on the Timeline.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'checkin_optional',
          title: '',
          content:
              'The check-in is entirely optional. Skipping it doesn\'t penalize your relationship — it just means that week\'s score leans more on Timeline activity alone.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_pulse_low_score',
        question: 'What does a low Pulse Score mean?',
        answer:
            'It\'s a reflection of the data from a specific week, not a permanent judgment on your relationship. Scores naturally move week to week — a lower week doesn\'t erase the ones before it, and a difficult week that gets logged honestly (including conflicts worked through) is exactly what the score is meant to capture.',
        category: 'Pulse',
        order: 1,
      ),
      FAQModel(
        id: 'faq_pulse_partner_edit',
        question: 'Can my partner edit or delete a moment I logged?',
        answer:
            'No — only the person who logged a moment can edit or delete it. Your partner can see it, but the entry stays under your control.',
        category: 'Pulse',
        order: 2,
      ),
      FAQModel(
        id: 'faq_pulse_private_moment',
        question: 'Can I log a moment privately, just for myself?',
        answer:
            'No — everything on the Timeline is shared and visible to both partners immediately. If you want something private, the Reflection Journal is the right place for that instead.',
        category: 'Pulse',
        order: 3,
      ),
      FAQModel(
        id: 'faq_pulse_when_computed',
        question: 'When is my Pulse Score updated?',
        answer:
            'It recalculates weekly. You can also tap refresh to recompute on demand, though this is limited to once every 24 hours.',
        category: 'Pulse',
        order: 4,
      ),
      FAQModel(
        id: 'faq_pulse_no_data',
        question: 'Why don\'t I see a Pulse Score yet?',
        answer:
            'You\'ll need at least a week of activity and one completed check-in before your first score appears. This ensures the score reflects something real rather than guessing from nothing.',
        category: 'Pulse',
        order: 5,
      ),
      FAQModel(
        id: 'faq_pulse_confidence_low',
        question: 'Why does a dimension show "low confidence"?',
        answer:
            'Some dimensions rely on data sources — like ongoing chat analysis — that build up gradually as you use the app. Low confidence just means there isn\'t much evidence yet, not that anything is wrong.',
        category: 'Pulse',
        order: 6,
      ),
    ];
  }
}
