import 'package:flutter/material.dart';

import '../../data/planning_models.dart';

/// Every block a plan can hold, in the order Insert offers them.
const planningBlockTools = <(PlanningBlockType, IconData, String)>[
  (PlanningBlockType.text, Icons.notes_rounded, 'Text'),
  (PlanningBlockType.checklist, Icons.checklist_rounded, 'Checklist'),
  (PlanningBlockType.date, Icons.event_rounded, 'Date'),
  (PlanningBlockType.table, Icons.table_chart_outlined, 'Table'),
  (PlanningBlockType.photo, Icons.photo_library_outlined, 'Photos'),
  (PlanningBlockType.link, Icons.link_rounded, 'Link'),
  (PlanningBlockType.place, Icons.place_outlined, 'Place'),
  (PlanningBlockType.expenses, Icons.receipt_long_outlined, 'Expenses'),
  (PlanningBlockType.budget, Icons.savings_outlined, 'Budget'),
  (PlanningBlockType.datePoll, Icons.how_to_vote_outlined, 'Date poll'),
  (PlanningBlockType.countdown, Icons.hourglass_bottom_rounded, 'Countdown'),
  (PlanningBlockType.progress, Icons.trending_up_rounded, 'Progress'),
  (PlanningBlockType.dualClock, Icons.schedule_rounded, 'Dual clock'),
];

String planningBlockLabel(PlanningBlockType type) => switch (type) {
  PlanningBlockType.unsupported => 'Block',
  _ => planningBlockTools.firstWhere((t) => t.$1 == type).$3,
};
