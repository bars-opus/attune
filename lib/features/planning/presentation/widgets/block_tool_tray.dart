import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

import '../../data/planning_models.dart';

const _tools = <(PlanningBlockType, IconData, String)>[
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
  _ => _tools.firstWhere((t) => t.$1 == type).$3,
};

Future<PlanningBlockType?> showBlockToolTray(BuildContext context) => showModalBottomSheet<PlanningBlockType>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder:
      (c) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: Spacing.allMd,
            child: Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.md,
              children: [
                for (final (type, icon, label) in _tools)
                  SizedBox(
                    width: 96,
                    child: InkWell(
                      borderRadius: BorderRadiusTokens.mdAll,
                      onTap: () => Navigator.of(c).pop(type),
                      child: Padding(
                        padding: Spacing.allSm,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(radius: 24, child: Icon(icon)),
                            const SizedBox(height: Spacing.xs),
                            Text(label),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
);
