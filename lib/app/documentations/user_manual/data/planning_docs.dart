// lib/app/documentations/user_manual/data/planning_docs.dart
//
// Planning — the couple's shared journal of plans (lib/features/planning).
// Always listed; the Map tab is described in couple_map_docs.dart.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class PlanningDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Planning';

  @override
  String get id => 'planning';

  @override
  String getSubtitle(BuildContext context) =>
      'One shared place for trips, lists, money and everything you\'re planning';

  @override
  IconData get icon => Icons.event_note_outlined;

  @override
  int get order => 4;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'planning_what',
      title: 'What Planning is',
      subtitle: 'Shared between the two of you',
      icon: Icons.event_note_outlined,
      category: 'Planning',
      order: 1,
      contents: [
        ManualContent(
          id: 'planning_shared',
          title: 'Your couple\'s journal',
          numberPrefix: '1',
          content:
              'Planning is shared: either of you can add, change or delete anything in it. It carries the name you chose for your chat.',
        ),
        ManualContent(
          id: 'planning_tabs',
          title: 'Three tabs',
          numberPrefix: '2',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Planning:** your categories and plans, with what you worked on recently at the top.',
            '**Calendar:** your Together calendar — dates, rituals, plans and memories.',
            '**Map:** where you both roughly are, and the stories you pinned (when available).',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'planning_plans',
      title: 'Categories and plans',
      subtitle: 'Start blank or from an idea',
      icon: Icons.folder_open_outlined,
      category: 'Planning',
      order: 2,
      contents: [
        ManualContent(
          id: 'planning_categories',
          title: 'Categories',
          numberPrefix: '1',
          content:
              'Group your plans into categories like Trips or Home. Create one from scratch or start from an idea, then reorder, hide or rename it from its menu.',
        ),
        ManualContent(
          id: 'planning_entries',
          title: 'Plans',
          numberPrefix: '2',
          content:
              'Inside a category, swipe a plan right to delete it (with Undo) or left to pin it. In a plan\'s menu you can mark it done, reopen it, or start the next one.',
        ),
        ManualContent(
          id: 'planning_new_dot',
          title: 'New from your partner',
          numberPrefix: '3',
          content:
              'A dot on a plan means your partner changed it since you last opened it; its category and Recent show one too. Opening the plan clears them.',
        ),
        ManualContent(
          id: 'planning_put_away',
          title: 'Put away gently',
          numberPrefix: '4',
          content:
              'For a plan you no longer want in front of you, choose "Put away gently" in its menu. It moves to Done & archived without a sound: no notice to anyone, its countdown reminders stop, and it leaves Recent and the calendar. Reopen it any time.',
        ),
        ManualContent(
          id: 'planning_template',
          title: '',
          content:
              'Each category can have a template, so every new plan in it starts with the same blocks.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'planning_blocks',
      title: 'Building a plan',
      subtitle: 'Add the blocks you need',
      icon: Icons.view_agenda_outlined,
      category: 'Planning',
      order: 3,
      contents: [
        ManualContent(
          id: 'planning_blocks_list',
          title: 'Blocks',
          numberPrefix: '1',
          content: 'A plan is made of blocks you add and arrange:',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Text, Checklist, Table, Photos, Link and Place.',
            'Date, Date poll, Countdown and Dual clock.',
            'Expenses, Budget and Progress.',
          ],
        ),
        ManualContent(
          id: 'planning_todos',
          title: 'To-dos nobody has taken',
          numberPrefix: '2',
          content:
              'A checklist item with no owner, due within a week, shows for both of you under "Needs you" in Calendar until someone takes it on.',
        ),
        ManualContent(
          id: 'planning_polls',
          title: 'Date polls',
          numberPrefix: '3',
          content:
              'Offer a few dates and each pick the ones that work. Until you vote, the poll waits for you under "Needs you".',
        ),
        ManualContent(
          id: 'planning_links',
          title: '',
          content:
              'A countdown counts to one date and a checklist progress bar tracks one checklist. Each says which ("Counts to", "Tracks"); with more than one to choose from, tap it to pick another. Adding or moving blocks never changes it.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'planning_money',
          title: 'Money, without a scoreboard',
          numberPrefix: '4',
          content:
              'Expenses can be split, and "Settle up?" helps you even out — but Attune never ranks who paid more.',
        ),
        ManualContent(
          id: 'planning_budget',
          title: 'Budgets',
          numberPrefix: '5',
          content:
              'A budget counts all of the plan\'s expenses, or just one Expenses block or table — tap "Counts" to choose. A new budget follows the plan\'s only expenses or money table by itself, so a plan can have one budget for flights and another for food. Its Breakdown tab shows what it counts as a chart: paid, not yet paid, and what\'s left.',
        ),
        ManualContent(
          id: 'planning_bills',
          title: 'Bills',
          numberPrefix: '6',
          content:
              'Give an expense a due date and it shows on the Calendar that day, marked as a bill. "Start the next one" carries your bills into a new plan, unpaid, with past due dates moved to the next month.',
        ),
        ManualContent(
          id: 'planning_table_total',
          title: '',
          content:
              'A table with a money column shows its total in a row underneath. With two or more money columns, a total of all of them follows.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => const [
    FAQModel(
      id: 'faq_planning_partner_edit',
      question: 'Can my partner change a plan I made?',
      answer:
          'Yes. Planning is shared, so either of you can add, edit or delete anything in it.',
      category: 'Planning',
      order: 1,
    ),
    FAQModel(
      id: 'faq_planning_offline',
      question: 'What if I edit while offline?',
      answer:
          'Your changes are kept and sent when you\'re back online. A plan shows when a change is still waiting, with a way to retry.',
      category: 'Planning',
      order: 2,
    ),
  ];
}
