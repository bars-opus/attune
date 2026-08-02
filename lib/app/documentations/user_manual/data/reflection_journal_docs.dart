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
      id: 'journal_what_it_is',
      title: 'What it is',
      subtitle: 'Always available, whoever you are',
      icon: Icons.edit_outlined,
      category: 'Reflection Journal',
      order: 1,
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
      order: 2,
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
      ],
    ),
    ManualSection(
      id: 'journal_reflections',
      title: 'What the reflections are',
      subtitle: 'Grounded in your own words, never a verdict',
      icon: Icons.psychology_outlined,
      category: 'Reflection Journal',
      order: 3,
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
      order: 4,
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
        id: 'faq_journal_partner_sees',
        question: 'Can my partner see what I write?',
        answer:
            'No, never. Entries are completely private to you and are never shown to a partner, used as evidence, or combined into any shared view.',
        category: 'Reflection Journal',
        order: 2,
      ),
      FAQModel(
        id: 'faq_journal_no_reflection',
        question: 'Why didn\'t I get a reflection on my entry?',
        answer:
            'Very short entries don\'t get one — there simply isn\'t enough written to say something meaningful. Write a bit more and a reflection is more likely to appear.',
        category: 'Reflection Journal',
        order: 3,
      ),
      FAQModel(
        id: 'faq_journal_edit_reflection',
        question: 'What happens to the reflection if I edit my entry?',
        answer:
            'Editing regenerates the reflection to match your updated content, so it never stays attached to text you\'ve since changed.',
        category: 'Reflection Journal',
        order: 4,
      ),
      FAQModel(
        id: 'faq_journal_delete_undo',
        question: 'Can I undo a deleted entry?',
        answer:
            'No — deletion is permanent once confirmed. You\'ll always be asked to confirm first, precisely because there\'s no way to bring it back afterward.',
        category: 'Reflection Journal',
        order: 5,
      ),
      FAQModel(
        id: 'faq_journal_vs_healing',
        question:
            'What\'s the difference between this and Healing Mode?',
        answer:
            'Healing Mode is a structured, multi-stage journey specifically for processing a breakup. The Reflection Journal is simpler, always available regardless of relationship status, and has no stages or eligibility requirements.',
        category: 'Reflection Journal',
        order: 6,
      ),
      FAQModel(
        id: 'faq_journal_streaks',
        question: 'Does the journal track streaks or remind me to write daily?',
        answer:
            'No. There are no streaks, badges, or nagging reminders — writing here is entirely optional and on your own schedule.',
        category: 'Reflection Journal',
        order: 7,
      ),
    ];
  }
}
