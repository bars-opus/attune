// lib/features/timeline/presentation/widgets/calendar_strip.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';



class CalendarStrip extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<DateTime, List<TimelineEventModel>> eventsByDate;
  final Map<DateTime, List<dynamic>> remindersByDate;
  final Map<DateTime, List<dynamic>> planningEntriesByDate;
  final Function(DateTime) onDaySelected;
  final Function(DateTime) onMonthChanged;
  final DateTime? selectedDate;

  /// Needed to read this month's per-author story counts for the date
  /// cells. Null simply renders no story avatars — the calendar still
  /// works for events and scheduled items.
  final String? relationshipId;

  const CalendarStrip({
    super.key,
    required this.focusedMonth,
    required this.eventsByDate,
    this.remindersByDate = const {},
    this.planningEntriesByDate = const {},
    required this.onDaySelected,
    required this.onMonthChanged,
    this.selectedDate,
    this.relationshipId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get days in month
    final daysInMonth = _getDaysInMonth(focusedMonth);
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final startingWeekday = firstDayOfMonth.weekday; // Monday = 1, Sunday = 7
    final offsetDays = startingWeekday - 1; // Convert to Monday-based offset

    return Column(
      children: [
        // Month header with navigation arrows
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.w, vertical: Spacing.sm.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  final prevMonth = DateTime(focusedMonth.year, focusedMonth.month - 1);
                  onMonthChanged(prevMonth);
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(focusedMonth),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  final nextMonth = DateTime(focusedMonth.year, focusedMonth.month + 1);
                  onMonthChanged(nextMonth);
                },
              ),
            ],
          ),
        ),
        // Weekday headers
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
              return SizedBox(
                width: 40,
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Gap(Spacing.sm.h),
        // Calendar grid
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.0,
            ),
            itemCount: 42, // 6 rows × 7 days
            itemBuilder: (context, index) {
              final dayNumber = index - offsetDays + 1;
              final isValidDay = dayNumber >= 1 && dayNumber <= daysInMonth;
              
              if (!isValidDay) {
                return const SizedBox.shrink();
              }
              
              final date = DateTime(focusedMonth.year, focusedMonth.month, dayNumber);
              final isToday = _isSameDay(date, DateTime.now());
              final isSelected = selectedDate != null && _isSameDay(date, selectedDate!);
              final eventsOnDate = eventsByDate[date] ?? [];
              final remindersOnDate = remindersByDate[date] ?? [];
              final planningOnDate = planningEntriesByDate[date] ?? [];

              // Distinct event types on this date, drawn as filled,
              // color-keyed circular avatars carrying the type's own
              // glyph (see calendar_day_indicators.dart). Reminders and
              // Planning entries share a single hollow ring instead —
              // "this date has something upcoming" is the only signal
              // the strip needs for them, not which kind.
              final eventTypes =
                  eventsOnDate.map((e) => e.eventType).toSet().toList();
              final hasUpcoming =
                  remindersOnDate.isNotEmpty || planningOnDate.isNotEmpty;

              return GestureDetector(
                onTap: () => onDaySelected(date),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? colorScheme.primary.withOpacity(0.1)
                        : isToday
                            ? colorScheme.primary.withOpacity(0.05)
                            : Colors.transparent,
                    border: isToday
                        ? Border.all(
                            color: colorScheme.primary,
                            width: BorderWidthTokens.hairline,
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.primary
                              : isToday
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                        ),
                      ),
                      CalendarDayIndicators(
                        relationshipId: relationshipId,
                        date: date,
                        eventTypes: eventTypes,
                        hasUpcoming: hasUpcoming,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // A key to what is actually on screen this month, not a static
        // list of every type the app supports.
        CalendarLegend(
          eventTypes: _visibleEventTypes(),
          hasStories: relationshipId != null,
          hasUpcoming: _hasAnyUpcoming(),
        ),
      ],
    );
  }

  int _getDaysInMonth(DateTime date) {
    final firstDayOfMonth = DateTime(date.year, date.month, 1);
    final nextMonth = DateTime(date.year, date.month + 1, 1);
    return nextMonth.difference(firstDayOfMonth).inDays;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Distinct event types present anywhere in the focused month.
  List<String> _visibleEventTypes() {
    final types = <String>{};
    for (final entry in eventsByDate.entries) {
      if (entry.key.year == focusedMonth.year &&
          entry.key.month == focusedMonth.month) {
        types.addAll(entry.value.map((e) => e.eventType));
      }
    }
    return types.toList()..sort();
  }

  bool _hasAnyUpcoming() {
    bool inMonth(DateTime d) =>
        d.year == focusedMonth.year && d.month == focusedMonth.month;
    return remindersByDate.entries.any(
          (e) => inMonth(e.key) && e.value.isNotEmpty,
        ) ||
        planningEntriesByDate.entries.any(
          (e) => inMonth(e.key) && e.value.isNotEmpty,
        );
  }
}
