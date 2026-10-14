// lib/features/timeline/presentation/widgets/planning_day_section.dart
import 'package:flutter/material.dart';

import '../../../planning/data/planning_models.dart';
import '../../../planning/presentation/planning_ui.dart';
import '../../../planning/presentation/screens/planning_entry_screen.dart';

/// Planning's own rendering for the Timeline screen's selected-day area
/// — never coerced into TimelineEventModel (that would need fake
/// loggedBy/eventType/moodScore/occurredAt values). Sits BESIDE the
/// existing moments/reminders rendering for that day. A tap opens the plan.
class PlanningDaySection extends StatelessWidget {
  const PlanningDaySection({
    super.key,
    required this.relationshipId,
    required this.entries,
  });
  final String relationshipId;
  final List<PlanningCalendarEntry> entries;

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
              entry.kind == PlanningCalendarKind.date
                  ? Icons.event_outlined
                  : Icons.check_box_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              entry.title,
              style:
                  entry.isComplete
                      ? TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: colorScheme.onSurfaceVariant,
                      )
                      : null,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap:
                () => Navigator.of(context).push(
                  planningRoute(
                    PlanningEntryScreen(
                      relationshipId: relationshipId,
                      entryId: entry.entryId,
                    ),
                  ),
                ),
          ),
      ],
    );
  }
}
