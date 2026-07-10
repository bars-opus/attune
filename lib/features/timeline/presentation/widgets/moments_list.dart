// lib/features/timeline/presentation/widgets/moments_list.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'moment_card.dart';

class MomentsList extends StatelessWidget {
  final List<TimelineEventModel> events;
  final String currentUserId;
  final DateTime currentMonth;
  final Function(DateTime) onDateSelected;

  const MomentsList({
    super.key,
    required this.events,
    required this.currentUserId,
    required this.currentMonth,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _buildEmptyState(context);
    }

    // Group events by month
    final Map<String, List<TimelineEventModel>> groupedEvents = {};
    for (final event in events) {
      final monthKey = DateFormat('MMMM yyyy').format(event.occurredAt);
      if (!groupedEvents.containsKey(monthKey)) {
        groupedEvents[monthKey] = [];
      }
      groupedEvents[monthKey]!.add(event);
    }

    // Sort months descending (newest first)
    final sortedMonths = groupedEvents.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('MMMM yyyy').parse(a);
        final dateB = DateFormat('MMMM yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedMonths.length,
      itemBuilder: (context, index) {
        final month = sortedMonths[index];
        final monthEvents = groupedEvents[month]!;
        
        // Sort events within month by date (newest first)
        monthEvents.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) Gap(Spacing.lg.h),
            Padding(
              padding: EdgeInsets.only(bottom: Spacing.md.h),
              child: Text(
                month,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...monthEvents.map((event) => Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm.h),
              child: MomentCard(
                event: event,
                currentUserId: currentUserId,
                currentMonth: currentMonth,
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 48,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
          Gap(Spacing.md.h),
          Text(
            'Your relationship story starts here.',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.sm.h),
          Text(
            'Log your first moment — a milestone,\na highlight, or even a conflict you\nworked through together.',
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.lg.h),
          ElevatedButton.icon(
            onPressed: () {
              // Navigate to log moment flow
              // This will be handled by the parent screen
              onDateSelected(DateTime.now());
            },
            icon: const Icon(Icons.add),
            label: const Text('Log your first moment'),
          ),
        ],
      ),
    );
  }
}
