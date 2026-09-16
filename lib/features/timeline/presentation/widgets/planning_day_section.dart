// lib/features/timeline/presentation/widgets/planning_day_section.dart
import 'package:flutter/material.dart';

import '../../../planning/data/models/planning_calendar_entry_model.dart';

/// Planning's own rendering for the Timeline screen's selected-day area
/// — never coerced into TimelineEventModel (spec §7's explicit rule:
/// that would need fake loggedBy/eventType/moodScore/occurredAt
/// values). Sits BESIDE the existing moments/reminders rendering for
/// that day, not merged into either.
class PlanningDaySection extends StatelessWidget {
  const PlanningDaySection({super.key, required this.entries});
  final List<PlanningCalendarEntryModel> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          ListTile(
            dense: true,
            leading: Icon(
              entry.kind == PlanningCalendarEntryKind.event
                  ? Icons.event_outlined
                  : Icons.check_box_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              entry.title,
              style: entry.isComplete
                  ? TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
