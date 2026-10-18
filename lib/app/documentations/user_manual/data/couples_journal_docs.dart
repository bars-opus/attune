// lib/app/documentations/user_manual/data/couples_journal_docs.dart
//
// The couples journal as a whole — why it exists and how couples use it —
// opened by the help button on Planning's home. The parts each keep their
// own topic (Planning, Together calendar, Your map), listed under Related
// and linked from "Read more", so someone who never opens the Related tab
// still finds them. Always listed; the map link shows only while the map is.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class CouplesJournalDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Couples journal';

  @override
  String get id => 'couplesJournal';

  @override
  String getSubtitle(BuildContext context) =>
      'Why you share one, and how to make the most of it';

  @override
  IconData get icon => Icons.menu_book_outlined;

  @override
  int get order => 4;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'couples_journal_why',
      title: 'Why a couples journal',
      subtitle: 'One shared place, so nothing lives in one head',
      icon: Icons.menu_book_outlined,
      category: 'Couples journal',
      order: 1,
      contents: [
        ManualContent(
          id: 'couples_journal_shared',
          title: 'Shared on purpose',
          numberPrefix: '1',
          content:
              'Plans usually end up scattered across chats, screenshots and one person\'s memory. The couples journal keeps them in one place you both own: either of you can add, change or delete anything, and you both see every change.',
        ),
        ManualContent(
          id: 'couples_journal_load',
          title: 'A lighter load',
          numberPrefix: '2',
          content:
              'When the lists, the dates and the money are written down where you can both see them, neither of you has to be the one who remembers everything.',
        ),
        ManualContent(
          id: 'couples_journal_name',
          title: 'It carries your name',
          numberPrefix: '3',
          content:
              'It uses the name you chose for your chat — for example "The Harolds\' journal". Until you choose one, it is just "Couples journal".',
        ),
        ManualContent(
          id: 'couples_journal_private',
          title: '',
          content:
              'Plans here are shared with your partner. For thoughts only you should see, use your **Reflection journal**.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'couples_journal_inside',
      title: 'What\'s inside',
      subtitle: 'Three tabs, one journal',
      icon: Icons.view_week_outlined,
      category: 'Couples journal',
      order: 2,
      contents: [
        ManualContent(
          id: 'couples_journal_tabs',
          title: 'Planning, Calendar and Map',
          numberPrefix: '1',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Planning:** categories like Trips, Groceries and Goals, each holding your plans.',
            '**Calendar:** dates, rituals and plans — and what needs an answer from you.',
            '**Map:** roughly how far apart you are, and the stories you pinned (when available).',
          ],
        ),
        ManualContent(
          id: 'couples_journal_dot',
          title: 'The dot',
          numberPrefix: '2',
          content:
              'A dot on a plan means your partner added or changed it since you last opened it. Its category shows a dot too, and so does the journal in Conversations. Open the plan and the dots go.',
        ),
      ],
    ),
    ManualSection(
      id: 'couples_journal_ways',
      title: 'Ways to use it',
      subtitle: 'However your life together looks',
      icon: Icons.diversity_1_outlined,
      category: 'Couples journal',
      order: 3,
      contents: [
        ManualContent(
          id: 'couples_journal_living',
          title: 'Living together',
          numberPrefix: '1',
          content:
              'Home & bills starts with your usual bills: add each one\'s amount and due date, tick it off once it\'s paid, and the budget adds them up. Groceries is a shared checklist, and "Settle up?" helps you even out. A to-do nobody has taken shows for both of you under "Needs you" in Calendar.',
        ),
        ManualContent(
          id: 'couples_journal_distance',
          title: 'Long distance',
          numberPrefix: '2',
          content:
              'Add a Countdown to your next visit and a Dual clock so you always know the time where the other is. When you have both turned it on, the Map shows roughly how far apart you are.',
        ),
        ManualContent(
          id: 'couples_journal_trip',
          title: 'A trip or a big day',
          numberPrefix: '3',
          content:
              'Start from Trips: each new trip comes with a date poll to agree on dates, a countdown, a budget, shared expenses and a packing list.',
        ),
        ManualContent(
          id: 'couples_journal_dating',
          title: 'Dating, not living together',
          numberPrefix: '4',
          content:
              'Plan the next one in Date nights and note what you loved afterwards. A weekly ritual on the Calendar keeps time for each other without anyone having to ask.',
        ),
        ManualContent(
          id: 'couples_journal_goals',
          title: 'Working toward something',
          numberPrefix: '5',
          content:
              'In Goals, each goal comes with a target date, a place to say why it matters to you, its steps, and a progress bar that fills as you tick them off.',
        ),
        ManualContent(
          id: 'couples_journal_tense',
          title: 'When things feel tense',
          numberPrefix: '6',
          content:
              'If a plan has become a sore point, choose "Put away gently" in its menu: it is archived without telling anyone, and Reopen brings it back when you are ready.',
        ),
        ManualContent(
          id: 'couples_journal_not_for_arguments',
          title: '',
          content:
              'The journal is for doing things together, not for keeping score or settling arguments. Nothing in it ranks who did more.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'couples_journal_habits',
      title: 'Good habits',
      subtitle: 'Small things that keep it working',
      icon: Icons.auto_awesome_outlined,
      category: 'Couples journal',
      order: 4,
      contents: [
        ManualContent(
          id: 'couples_journal_owner',
          title: 'Give to-dos an owner',
          numberPrefix: '1',
          content:
              'A checklist item with someone\'s name on it doesn\'t fall between you.',
        ),
        ManualContent(
          id: 'couples_journal_suggest',
          title: 'Suggest, don\'t decide',
          numberPrefix: '2',
          content:
              'On the Calendar, a plan that involves your partner is a proposal: they pick a time or decline.',
        ),
        ManualContent(
          id: 'couples_journal_templates',
          title: 'Use templates',
          numberPrefix: '3',
          content:
              'Give a category a template, and every new plan in it starts with the blocks you always use.',
        ),
      ],
    ),
    ManualSection(
      id: 'couples_journal_more',
      title: 'Read more',
      subtitle: 'Each part has its own guide',
      icon: Icons.apps_outlined,
      category: 'Couples journal',
      order: 5,
      contents: [
        ManualContent(
          id: 'couples_journal_link_planning',
          title: '',
          content: 'Categories, blocks, polls, money and putting a plan away',
          type: ManualContentType.link,
          linkedModuleId: 'planning',
        ),
        ManualContent(
          id: 'couples_journal_link_together',
          title: '',
          content: 'Dates, rituals, proposals and calendar links',
          type: ManualContentType.link,
          linkedModuleId: 'together',
        ),
        ManualContent(
          id: 'couples_journal_link_map',
          title: '',
          content: 'Distance, approximate areas and story pins',
          type: ManualContentType.link,
          linkedModuleId: 'coupleMap',
        ),
        ManualContent(
          id: 'couples_journal_link_reflection',
          title: '',
          content: 'Your private journal, for thoughts just for you',
          type: ManualContentType.link,
          linkedModuleId: 'reflectionJournal',
        ),
        ManualContent(
          id: 'couples_journal_link_lifecycle',
          title: '',
          content: 'What happens to your shared space if you pause or end it',
          type: ManualContentType.link,
          linkedModuleId: 'relationshipLifecycle',
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_couples_journal_see',
      question: 'Can my partner see everything in it?',
      answer:
          'Plans, lists and money in the couples journal are shared with your partner. On the Calendar you can add a private or surprise event that only you see. For private thoughts, use your Reflection journal.',
      category: 'Couples journal',
      order: 1,
    ),
    FAQModel(
      id: 'faq_couples_journal_reflection',
      question: 'Is this the same as my Reflection journal?',
      answer:
          'No. The couples journal is shared with your partner; your Reflection journal is private, and only you can see it.',
      category: 'Couples journal',
      order: 2,
    ),
    FAQModel(
      id: 'faq_couples_journal_dot',
      question: 'Why is there a dot on a plan or a category?',
      answer:
          'Your partner added or changed a plan since you last opened it. The dot shows on the plan, in Recent and on its category; open the plan and they go. A plan put away gently never shows one.',
      category: 'Couples journal',
      order: 3,
    ),
  ];
}
