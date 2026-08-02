// lib/app/documentations/user_manual/data/verdict_docs.dart
//
// Documents the Verdict system. Sourced from
// lib/architecture/VERDICT_SYSTEM_SPEC.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class VerdictDocs implements DocumentationModule {
  @override
  int get order => 6;

  @override
  String getTitle(BuildContext context) => 'The Verdict';

  @override
  String get id => 'verdict';

  @override
  String getSubtitle(BuildContext context) =>
      'A monthly, sourced summary of your relationship — never a judgment';

  @override
  IconData get icon => Icons.summarize_outlined;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'verdict_what_it_is',
      title: 'What the Verdict is',
      subtitle: 'A summary, not a grade',
      icon: Icons.fact_check_outlined,
      category: 'Verdict',
      order: 1,
      contents: [
        ManualContent(
          id: 'verdict_intro',
          title: 'What your data actually shows',
          numberPrefix: '1',
          content:
              'Once a month, the Verdict pulls together everything already known about your relationship — your Pulse history, shared patterns, and recent activity — into a short, sourced summary. It tells you what the data shows, offers one conversation starter, and stops there.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'verdict_not_judgment',
          title: '',
          content:
              'The Verdict never judges, diagnoses, scores, or ranks your relationship. It never tells you whether to stay together, and it\'s never compared against other couples.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'verdict_shared',
          title: 'Shared, and only about the relationship',
          content:
              'Both of you see the same Verdict. It only ever describes relationship-level patterns — never which of you specifically did what. If it mentions a pattern like pursuing and withdrawing, it won\'t say who was doing which.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'verdict_contents',
      title: 'What\'s inside a Verdict',
      subtitle: 'Headline, strengths, one thing to watch',
      icon: Icons.article_outlined,
      category: 'Verdict',
      order: 2,
      contents: [
        ManualContent(
          id: 'verdict_structure',
          title: '',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**A headline** — a short, factual observation about the month.',
            '**Strengths** — one to three things that went well, each backed by specific evidence.',
            '**Watch areas** — one to three things worth paying attention to, also evidence-backed.',
            '**One action** — a single optional conversation starter, phrased as an invitation, never an instruction.',
          ],
        ),
        ManualContent(
          id: 'verdict_sources',
          title: '',
          content:
              'Every claim in a Verdict links back to something specific — a Pulse score trend, a pattern that showed up in shared sessions, or a logged event. You can always tap to see exactly what a claim is based on.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'verdict_confidence',
      title: 'How confidence works',
      subtitle: 'Always labeled, never hidden',
      icon: Icons.verified_outlined,
      category: 'Verdict',
      order: 3,
      contents: [
        ManualContent(
          id: 'verdict_confidence_visible',
          title: 'Confidence is always shown',
          content:
              'Every Verdict shows how much data it\'s based on — for example, "Based on 9 weeks of data." This is never hidden, so you always know how much to weigh a given month\'s summary.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'verdict_hedging',
          title: 'Language matches the evidence',
          content:
              'Stronger claims are only stated directly when there\'s genuinely strong evidence behind them. Weaker evidence gets hedged language, like "some patterns suggest" — the Verdict is always honest about how sure it actually is.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'verdict_eligibility',
      title: 'When you\'ll get one',
      subtitle: 'Only when there\'s enough real data',
      icon: Icons.calendar_month_outlined,
      category: 'Verdict',
      order: 4,
      contents: [
        ManualContent(
          id: 'verdict_eligibility_explain',
          title: 'A real minimum, not a guess',
          content:
              'A Verdict is only generated once your relationship has built up enough history — several weeks of Pulse scores and a handful of analyzed sessions. Below that threshold, you\'ll see an honest empty state rather than a Verdict stretched thin from too little data.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'verdict_once_per_month',
          title: '',
          content:
              'One Verdict is generated per calendar month, at the start of the following month. You can\'t regenerate or create multiple versions of the same month\'s Verdict.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'verdict_no_safety',
          title: '',
          content:
              'The Verdict never includes anything related to safety detections or crisis resources — that\'s handled entirely separately, and independently accessible whenever you need it.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_verdict_grade',
        question: 'Is the Verdict a score or grade for our relationship?',
        answer:
            'No. There\'s no overall score, ranking, or grade — the Verdict describes specific, sourced patterns from your data and stops there. It never scores your relationship\'s worth or health.',
        category: 'Verdict',
        order: 1,
      ),
      FAQModel(
        id: 'faq_verdict_who_did_what',
        question: 'Does the Verdict say which of us did something specific?',
        answer:
            'No. It only ever describes relationship-level patterns, never attributing a specific behavior to one partner by name. That kind of personal detail stays in your own private insights, never the shared Verdict.',
        category: 'Verdict',
        order: 2,
      ),
      FAQModel(
        id: 'faq_verdict_no_verdict',
        question: 'Why haven\'t we gotten a Verdict yet?',
        answer:
            'A Verdict requires a minimum amount of relationship history — several weeks of Pulse scores and analyzed sessions. Until that threshold is reached, you\'ll see an honest empty state instead of a thin, unreliable summary.',
        category: 'Verdict',
        order: 3,
      ),
      FAQModel(
        id: 'faq_verdict_regenerate',
        question: 'Can we regenerate this month\'s Verdict?',
        answer:
            'No — one Verdict exists per calendar month, generated once. It reflects a fixed snapshot of your data from that period rather than being regenerable on demand.',
        category: 'Verdict',
        order: 4,
      ),
      FAQModel(
        id: 'faq_verdict_evidence',
        question: 'Can I see what a Verdict claim is actually based on?',
        answer:
            'Yes — every claim links to specific evidence, and you can tap it to see the source, the time window, and how much data supports it.',
        category: 'Verdict',
        order: 5,
      ),
      FAQModel(
        id: 'faq_verdict_tells_decide',
        question: 'Will the Verdict tell us whether to stay together?',
        answer:
            'No, never. The Verdict describes what the data shows and offers one optional conversation starter — it never tells you what to decide about your relationship.',
        category: 'Verdict',
        order: 6,
      ),
    ];
  }
}
