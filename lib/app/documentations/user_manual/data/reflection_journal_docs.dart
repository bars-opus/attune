// lib/app/documentations/user_manual/data/reflection_journal_docs.dart
//
// Documents the Reflection Journal. Sourced from
// docs/superpowers/specs/2026-08-02-reflection-journal-design.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ReflectionJournalDocs implements DocumentationModule {
  @override
  int get order => 4;

  @override
  String getTitle(BuildContext context) => 'Reflection Journal';

  @override
  String get id => 'reflectionJournal';

  @override
  String getSubtitle(BuildContext context) =>
      'A private space to write, always available';

  @override
  IconData get icon => Icons.book_outlined;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'journal_why_it_exists',
      title: 'Why it exists',
      subtitle: 'Not a consolation prize — a place for everyone',
      icon: Icons.lightbulb_outline,
      category: 'Reflection Journal',
      order: 1,
      contents: [
        ManualContent(
          id: 'journal_why_gap',
          title: 'Somewhere to write, regardless of relationship status',
          numberPrefix: '1',
          content:
              'Before this existed, anyone not in an active couple got routed toward Healing Mode by default — a journey built specifically for processing a breakup. That made no sense for someone who\'s single by choice, waiting on a partner to join, or simply wants to reflect on an ordinary day. The Reflection Journal closes that gap: a real writing space for Personal-mode users, not a fallback screen.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'journal_why_not_download_one',
          title: 'Why use this instead of a dedicated journaling app?',
          numberPrefix: '2',
          content:
              'A standalone journal app will usually beat Attune on raw journaling features — tags, search, exports, themes. What it can\'t offer is the connection to the rest of your relational picture. Your entries here are read for tone and communication patterns using the same NVC-informed lens Attune applies elsewhere, so what you write becomes part of understanding how you relate to others over time — never sent anywhere, never seen by anyone else, but not writing into a void either.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'journal_why_honesty',
          title: '',
          content:
              'Every claim the AI makes is sourced to your own words, confidence is always hedged, and there are no streaks or engagement mechanics pushing you to write. That restraint is deliberate — most journaling apps compete on features or gamification; this one competes on trustworthiness.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'journal_what_it_is',
      title: 'What it is',
      subtitle: 'Always available, whoever you are',
      icon: Icons.book_outlined,
      category: 'Reflection Journal',
      order: 2,
      contents: [
        ManualContent(
          id: 'journal_intro',
          title: 'A private journal, not tied to a relationship',
          numberPrefix: '1',
          content:
              'The Reflection Journal is your own private space to write — available to anyone using Attune, whether you\'re single, between relationships, waiting on a partner invite, or in an active relationship. It has nothing to do with your relationship status.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'journal_never_shared',
          title: '',
          content:
              'Nothing you write here is ever shown to a partner, used as evidence, or combined into any couple-level view. It stays yours.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'journal_vs_healing',
          title: 'How this differs from Healing Mode',
          content:
              'Healing Mode is a structured, multi-stage journey specifically for processing a breakup. The Reflection Journal is simpler and always available — a place to write freely about anything, any day, with no stages or eligibility requirements.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'journal_writing',
      title: 'Writing an entry',
      subtitle: 'Freeform, with an optional nudge',
      icon: Icons.create_outlined,
      category: 'Reflection Journal',
      order: 3,
      contents: [
        ManualContent(
          id: 'journal_freeform',
          title: 'Write whatever\'s on your mind',
          content:
              'There\'s no required format or length. Each time you sit down to write, you\'ll see an optional daily prompt for inspiration — you can write from it, ignore it, or dismiss it entirely. It\'s never required.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'journal_saved_immediately',
          title: '',
          content:
              'Once you save, your entry appears right away. A gentle reflection may follow shortly after — there\'s no need to wait for it before moving on.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'journal_how_to_use_well',
          title: 'Getting the most out of it',
          content:
              'Write like nobody\'s reading — because nobody is. The reflections and patterns get more useful the more honestly and regularly you write, but "regularly" is whatever pace suits you: there\'s no schedule to keep. A few real sentences about what actually happened beats a polished paragraph every time; the analysis works from specifics, not summaries.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'journal_reflections',
      title: 'What the reflections are',
      subtitle: 'Grounded in your own words, never a verdict',
      icon: Icons.psychology_outlined,
      category: 'Reflection Journal',
      order: 4,
      contents: [
        ManualContent(
          id: 'journal_ai_scope',
          title: 'Sourced only from what you wrote',
          content:
              'After an entry with enough content, you may see a short, warm reflection — noticing a tone or a feeling that came through in your own words. It never diagnoses you, never tells you what to do, and never uses clinical labels.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'journal_short_entries',
          title: '',
          content:
              'Very short entries don\'t get a reflection — there\'s simply not enough there to say anything meaningful, so nothing is forced.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'journal_patterns',
          title: 'Patterns across entries',
          content:
              'Once you\'ve written a handful of entries, a Patterns view becomes available, gently pointing out themes that have shown up more than once across your writing — always sourced to specific entries, never invented.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'journal_control',
      title: 'You\'re always in control',
      subtitle: 'Edit, delete, and nothing else',
      icon: Icons.tune,
      category: 'Reflection Journal',
      order: 5,
      contents: [
        ManualContent(
          id: 'journal_edit',
          title: 'Editing an entry',
          content:
              'You can edit any entry at any time. Editing regenerates its reflection to match the new content — the old reflection is never left dangling on text you\'ve since changed.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'journal_delete',
          title: 'Deleting an entry',
          content:
              'Deleting is permanent — you\'ll be asked to confirm first, and there\'s no way to undo it afterward. Once confirmed, the entry and its reflection are both gone.',
          numberPrefix: '2',
          type: ManualContentType.warning,
        ),
        ManualContent(
          id: 'journal_no_gamification',
          title: '',
          content:
              'There are no streaks, no badges, and no reminders nagging you to write. Writing here is entirely on your own terms.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_journal_who_can_use',
        question: 'Who can use the Reflection Journal?',
        answer:
            'Anyone. It\'s not tied to relationship status — single, waiting on a partner invite, or in an active relationship, the journal is always available to you.',
        category: 'Reflection Journal',
        order: 1,
      ),
      FAQModel(
        id: 'faq_journal_why_needed',
        question: 'Why does Attune have a journal at all?',
        answer:
            'Before this existed, anyone outside an active couple was routed toward Healing Mode by default — a journey built specifically for breakups. That left no real writing space for someone who\'s single by choice, waiting on a partner, or just wants to reflect on an ordinary day. The Reflection Journal fills that gap.',
        category: 'Reflection Journal',
        order: 2,
      ),
      FAQModel(
        id: 'faq_journal_vs_other_apps',
        question:
            'Why use this instead of a journaling app from the App Store or Play Store?',
        answer:
            'A dedicated journaling app will usually have more features — tags, search, exports, themes. What it won\'t have is the connection to the rest of your relational picture: your entries here are read for tone and communication patterns using the same lens Attune applies elsewhere, so your writing becomes part of understanding how you relate to others over time, without ever leaving your account. If you just want a feature-rich standalone journal, a dedicated app may serve you better — Attune\'s journal is about that connection, not about out-featuring them.',
        category: 'Reflection Journal',
        order: 3,
      ),
      FAQModel(
        id: 'faq_journal_partner_sees',
        question: 'Can my partner see what I write?',
        answer:
            'No, never. Entries are completely private to you and are never shown to a partner, used as evidence, or combined into any shared view.',
        category: 'Reflection Journal',
        order: 4,
      ),
      FAQModel(
        id: 'faq_journal_no_reflection',
        question: 'Why didn\'t I get a reflection on my entry?',
        answer:
            'Very short entries don\'t get one — there simply isn\'t enough written to say something meaningful. Write a bit more and a reflection is more likely to appear.',
        category: 'Reflection Journal',
        order: 5,
      ),
      FAQModel(
        id: 'faq_journal_edit_reflection',
        question: 'What happens to the reflection if I edit my entry?',
        answer:
            'Editing regenerates the reflection to match your updated content, so it never stays attached to text you\'ve since changed.',
        category: 'Reflection Journal',
        order: 6,
      ),
      FAQModel(
        id: 'faq_journal_delete_undo',
        question: 'Can I undo a deleted entry?',
        answer:
            'No — deletion is permanent once confirmed. You\'ll always be asked to confirm first, precisely because there\'s no way to bring it back afterward.',
        category: 'Reflection Journal',
        order: 7,
      ),
      FAQModel(
        id: 'faq_journal_vs_healing',
        question:
            'What\'s the difference between this and Healing Mode?',
        answer:
            'Healing Mode is a structured, multi-stage journey specifically for processing a breakup. The Reflection Journal is simpler, always available regardless of relationship status, and has no stages or eligibility requirements.',
        category: 'Reflection Journal',
        order: 8,
      ),
      FAQModel(
        id: 'faq_journal_streaks',
        question: 'Does the journal track streaks or remind me to write daily?',
        answer:
            'No. There are no streaks, badges, or nagging reminders — writing here is entirely optional and on your own schedule.',
        category: 'Reflection Journal',
        order: 9,
      ),
    ];
  }
}
