// lib/app/documentations/user_manual/data/community_questions_docs.dart
//
// Documents Community Questions. Sourced from
// lib/architecture/COMMUNITY_QUESTIONS.md.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class CommunityQuestionsDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Community Questions';

  @override
  String get id => 'communityQuestions';

  @override
  String getSubtitle(BuildContext context) =>
      'Borrow a great game question from the community, or share your own';

  @override
  IconData get icon => Icons.public_outlined;

  @override
  int get order => 18;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'community_what_it_is',
      title: 'What it is',
      subtitle: 'A shared bank of custom game questions',
      icon: Icons.public_outlined,
      category: 'Community Questions',
      order: 1,
      contents: [
        ManualContent(
          id: 'community_intro',
          title: 'Questions other users chose to share',
          numberPrefix: '1',
          content:
              'When you write a custom Truth, Dare, or This or That question, you can choose to share it with the wider Attune community instead of keeping it private to you and your partner. Community Questions is where you can browse everyone\'s shared questions and save the ones you like into your own bank.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'community_optional',
          title: '',
          content:
              'Sharing to the community is entirely your choice — custom questions default to private, and sharing them further with the whole community is a separate, deliberate step beyond just sharing with your partner.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'community_browsing',
      title: 'Finding a question',
      subtitle: 'Search, filter, and save',
      icon: Icons.search,
      category: 'Community Questions',
      order: 2,
      contents: [
        ManualContent(
          id: 'community_filters',
          title: 'Filtering by type and tone',
          content:
              'You can filter the community feed by question type (Truth, Dare, or This or That) and by tone, or search directly for something specific.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'community_save',
          title: 'Saving a question',
          content:
              'Each question shows how many times it\'s been used across the community. Tap "Save" to add a question you like into your own personal bank, ready to come up in your own games.',
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
        id: 'faq_community_who_wrote',
        question: 'Can I see who wrote a community question?',
        answer:
            'No — shared community questions don\'t show who wrote them, consistent with how custom questions work everywhere else in the app.',
        category: 'Community Questions',
        order: 1,
      ),
      FAQModel(
        id: 'faq_community_share_default',
        question:
            'Are my custom questions shared with the community automatically?',
        answer:
            'No. Custom questions start private to you, and sharing to the wider community is a separate, deliberate choice beyond just sharing with your partner.',
        category: 'Community Questions',
        order: 2,
      ),
      FAQModel(
        id: 'faq_community_save_effect',
        question: 'What happens when I save a community question?',
        answer:
            'It\'s added to your own personal question bank, so it can come up during your own future game sessions — just like a question you wrote yourself.',
        category: 'Community Questions',
        order: 3,
      ),
      FAQModel(
        id: 'faq_community_report',
        question: 'What if I see an inappropriate community question?',
        answer:
            'You can report it the same way you\'d report any custom question elsewhere in the app — reported questions are pulled from circulation for review.',
        category: 'Community Questions',
        order: 4,
      ),
    ];
  }
}
