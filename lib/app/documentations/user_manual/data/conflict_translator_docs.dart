// lib/app/documentations/user_manual/data/conflict_translator_docs.dart
//
// Documents the Conflict Translator ("Help me say this"). Sourced from
// lib/architecture/CONFLICT_TRANSLATOR.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class ConflictTranslatorDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Conflict Translator';

  @override
  String get id => 'conflictTranslator';

  @override
  String getSubtitle(BuildContext context) =>
      'Help finding clearer words for a hard message';

  @override
  IconData get icon => Icons.translate_outlined;

  @override
  int get order => 7;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'ct_what_it_is',
      title: 'What it is',
      subtitle: 'A private thinking tool, not autocorrect',
      icon: Icons.lightbulb_outline,
      category: 'Conflict Translator',
      order: 1,
      contents: [
        ManualContent(
          id: 'ct_intro',
          title: 'Help expressing a hard feeling clearly',
          numberPrefix: '1',
          content:
              'When you\'re composing a message and it\'s hitting an accusatory or heated note, you can tap "Help me say this" to see an alternative phrasing — one that tries to express what you actually need, rather than what you\'re frustrated about.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'ct_pull_only',
          title: '',
          content:
              'This tool only ever appears when you ask for it. Attune never pops it up automatically or suggests you should rephrase something — the composer stays exactly as quiet as always unless you tap the button yourself.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'ct_using',
      title: 'How to use it',
      subtitle: 'Compare, then choose',
      icon: Icons.compare_arrows,
      category: 'Conflict Translator',
      order: 2,
      contents: [
        ManualContent(
          id: 'ct_sheet',
          title: 'Side by side',
          content:
              'Tapping "Help me say this" opens a sheet showing what you wrote next to one suggested rewrite — not several options to pick from, just one clear alternative. Below it, you may see a short note about the underlying need behind your message, like "underlying need: to be heard."',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'ct_choices',
          title: 'Three choices, all yours',
          content: '',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Send mine** — send your original message, unchanged.',
            '**Send this** — send the suggested rewrite instead.',
            '**Edit this** — take the rewrite as a starting point and adjust it yourself before sending.',
          ],
        ),
        ManualContent(
          id: 'ct_low_confidence',
          title: 'When the rewrite isn\'t confident',
          content:
              'If the suggestion isn\'t especially confident, you\'ll see a note saying so — a reminder to trust your own instinct over the suggestion when it doesn\'t quite land.',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'ct_privacy',
      title: 'Complete privacy',
      subtitle: 'Your partner never knows you used it',
      icon: Icons.visibility_off_outlined,
      category: 'Conflict Translator',
      order: 3,
      contents: [
        ManualContent(
          id: 'ct_recipient_unaware',
          title: 'No trace, no label',
          content:
              'Whichever message you end up sending — original, rewrite, or your own edit — it arrives as a completely ordinary message. There\'s no label, no indicator, no "polished with Attune" badge. Your partner has no way to tell the translator was ever involved.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'ct_no_record',
          title: '',
          content:
              'Your draft and the suggested rewrite aren\'t kept as a saved record once you\'ve made your choice — the tool is for that one moment of composing, not a running log.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'ct_meaning',
      title: 'It won\'t change what you mean',
      subtitle: 'Clearer, not softer',
      icon: Icons.record_voice_over_outlined,
      category: 'Conflict Translator',
      order: 4,
      contents: [
        ManualContent(
          id: 'ct_preserves_meaning',
          title: 'Your actual concern stays intact',
          content:
              'The rewrite is built to preserve what you\'re genuinely trying to say — it won\'t soften a real concern into nothing, or make you sound like you\'re apologizing for something you haven\'t decided you\'re sorry for. If what you wrote is already clear, the "rewrite" may simply be your own message back to you.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_ct_partner_knows',
        question: 'Will my partner know I used "Help me say this"?',
        answer:
            'No, never. Whatever you choose to send — your original, the rewrite, or your own edit — arrives as a completely ordinary message with no label or indicator attached.',
        category: 'Conflict Translator',
        order: 1,
      ),
      FAQModel(
        id: 'faq_ct_automatic',
        question: 'Does the app ever suggest a rewrite automatically?',
        answer:
            'No. This tool only ever appears when you explicitly tap "Help me say this" — Attune never interrupts your typing to suggest a rephrase on its own.',
        category: 'Conflict Translator',
        order: 2,
      ),
      FAQModel(
        id: 'faq_ct_multiple_options',
        question: 'Can I get more than one rewrite option?',
        answer:
            'No — you\'ll see one suggested rewrite at a time. If it doesn\'t feel right, you can edit it yourself or simply send your original message instead.',
        category: 'Conflict Translator',
        order: 3,
      ),
      FAQModel(
        id: 'faq_ct_soften_concern',
        question: 'Will it soften a real concern I have?',
        answer:
            'It\'s built not to. The rewrite aims to preserve your actual meaning and shouldn\'t turn a legitimate concern into nothing, or add false warmth that isn\'t genuinely yours.',
        category: 'Conflict Translator',
        order: 4,
      ),
      FAQModel(
        id: 'faq_ct_limit',
        question: 'Is there a limit on how often I can use it?',
        answer:
            'No — you can use "Help me say this" as often as you\'d like, whenever you\'re composing a message.',
        category: 'Conflict Translator',
        order: 5,
      ),
      FAQModel(
        id: 'faq_ct_saved',
        question: 'Is my draft or the rewrite saved anywhere?',
        answer:
            'No — once you\'ve made your choice and sent (or dismissed) the sheet, the draft and suggested rewrite aren\'t kept as a stored record.',
        category: 'Conflict Translator',
        order: 6,
      ),
    ];
  }
}
