// lib/app/documentations/user_manual/data/couple_map_docs.dart
//
// The couple map (Planning → Map; lib/features/couple_map; spec
// docs/superpowers/specs/2026-10-16-couple-map-design.md). Listed only while
// couple_map_enabled is on (DocumentationRegistry).

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class CoupleMapDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Your map';

  @override
  String get id => 'coupleMap';

  @override
  String getSubtitle(BuildContext context) =>
      'How far apart you are, and the stories you chose to pin — never your address';

  @override
  IconData get icon => Icons.map_outlined;

  @override
  int get order => 4;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'map_area',
      title: 'Sharing your area',
      subtitle: 'Your neighbourhood, never your address',
      icon: Icons.location_searching,
      category: 'Map',
      order: 1,
      contents: [
        ManualContent(
          id: 'map_area_how',
          title: 'Both of you choose',
          numberPrefix: '1',
          content:
              'Tap the chip at the top left of the map and turn on "Share my approximate area". You each see the other only when you have both turned it on.',
        ),
        ManualContent(
          id: 'map_area_rough',
          title: 'Rough on purpose',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Your area shows as a soft circle about a kilometre or more across — never a dot or a street.',
            'It updates only when you open Attune. Nothing tracks you in the background.',
            'After a few hours it fades; after 8 hours it disappears until you open the app again.',
          ],
        ),
        ManualContent(
          id: 'map_area_distance',
          title: 'How far apart',
          numberPrefix: '3',
          content:
              'A card shows roughly how far apart you are, the time where they are, and the days until you\'re together if you\'ve planned it. When you\'re close it just says "Together".',
        ),
      ],
    ),
    ManualSection(
      id: 'map_pause',
      title: 'Pausing and stopping',
      subtitle: 'Silent, and both ways',
      icon: Icons.pause_circle_outline,
      category: 'Map',
      order: 2,
      contents: [
        ManualContent(
          id: 'map_pause_how',
          title: 'Pause for a while',
          numberPrefix: '1',
          content:
              'Pause for 1 hour, 8 hours or until you resume. While either of you is paused, neither sees the other.',
        ),
        ManualContent(
          id: 'map_pause_silent',
          title: '',
          content:
              'Nobody is told. When one of you pauses or stops, the other just sees "Just you on the map right now" — the same as when an area is simply out of date.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'map_pins',
      title: 'Story pins',
      subtitle: 'Only the places you choose',
      icon: Icons.push_pin_outlined,
      category: 'Map',
      order: 3,
      contents: [
        ManualContent(
          id: 'map_pins_how',
          title: 'Pin a story when you post it',
          numberPrefix: '1',
          content:
              'Turn on "Pin to our map" in the camera before posting. It starts off the first time, then remembers your last choice. Older stories are never pinned for you.',
        ),
        ManualContent(
          id: 'map_pins_remove',
          title: 'Remove a pin any time',
          numberPrefix: '2',
          content:
              'Open your story and tap "Remove from map" — the story stays, its place is gone for good. Or use "Remove all my places" in the sharing sheet.',
        ),
        ManualContent(
          id: 'map_pins_home',
          title: 'Warn me near home',
          numberPrefix: '3',
          content:
              'Set your home area and pins near it start off, so you don\'t pin your front door by accident. Your home area is kept on this phone only.',
        ),
      ],
    ),
    ManualSection(
      id: 'map_widget',
      title: 'On your home screen',
      subtitle: 'Distance, discreetly',
      icon: Icons.widgets_outlined,
      category: 'Map',
      order: 4,
      contents: [
        ManualContent(
          id: 'map_widget_how',
          title: 'An optional widget',
          numberPrefix: '1',
          content:
              'Turn on "Show distance on my home screen" in the sharing sheet, then add the Attune widget from your phone\'s widget list. It shows roughly how far apart you are — no names or places — and quick exit clears it.',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_map_history',
      question: 'Can my partner see where I\'ve been?',
      answer:
          'No. Only your current rough area is kept, and it is replaced each time you open the app. There is no history, no "last seen" and no arrive or leave alerts.',
      category: 'Map',
      order: 1,
    ),
    FAQModel(
      id: 'faq_map_end',
      question: 'What happens to the map if our relationship ends?',
      answer: 'Both areas and every story pin are removed from the shared map.',
      category: 'Map',
      order: 2,
    ),
  ];
}
