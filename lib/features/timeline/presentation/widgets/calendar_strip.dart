import 'package:attune/features/reminders/data/models/reminder_model.dart';
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

  /// Opens the All months view; shows a button at the header's end when set.
  final VoidCallback? onShowAll;

  /// The previous / next month arrows (hidden in the All months list).
  final bool showNavigation;

  /// The key under the grid (the All months list shows one at the top).
  final bool showLegend;

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
    this.onShowAll,
    this.showNavigation = true,
    this.showLegend = true,
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
          padding: EdgeInsets.symmetric(
            horizontal: Spacing.md.w,
            vertical: Spacing.sm.h,
          ),
          child: Row(
            children: [
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final prevMonth = DateTime(
                      focusedMonth.year,
                      focusedMonth.month - 1,
                    );
                    onMonthChanged(prevMonth);
                  },
                ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(focusedMonth),
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showNavigation)
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final nextMonth = DateTime(
                      focusedMonth.year,
                      focusedMonth.month + 1,
                    );
                    onMonthChanged(nextMonth);
                  },
                ),
              if (onShowAll != null)
                IconButton(
                  tooltip: 'All months',
                  icon: const Icon(Icons.calendar_view_month_rounded),
                  onPressed: onShowAll,
                ),
            ],
          ),
        ),
        // Weekday headers
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children:
                ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
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
            // Only the weeks this month spans (four to six), so no empty
            // row sits between the last dates and the key.
            itemCount: ((offsetDays + daysInMonth) / 7).ceil() * 7,
            itemBuilder: (context, index) {
              final dayNumber = index - offsetDays + 1;
              final isValidDay = dayNumber >= 1 && dayNumber <= daysInMonth;

              if (!isValidDay) {
                return const SizedBox.shrink();
              }

              final date = DateTime(
                focusedMonth.year,
                focusedMonth.month,
                dayNumber,
              );
              final isToday = _isSameDay(date, DateTime.now());
              final eventsOnDate = eventsByDate[date] ?? [];
              final remindersOnDate = remindersByDate[date] ?? [];
              final planningOnDate = planningEntriesByDate[date] ?? [];

              // Distinct event types on this date, drawn as filled,
              // color-keyed circular avatars carrying the type's own
              // glyph (see calendar_day_indicators.dart). A reminder shows
              // its occasion icon, as its Upcoming row does; plans and
              // anything else ahead share a solid primary dot.
              final eventTypes =
                  eventsOnDate.map((e) => e.eventType).toSet().toList();
              final reminderTypes = _occasions(remindersOnDate);
              final hasUpcoming =
                  planningOnDate.isNotEmpty ||
                  remindersOnDate.any((r) => r is! ReminderModel);

              return GestureDetector(
                onTap: () => onDaySelected(date),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Only today is highlighted; tapping a day opens it
                    // without marking it.
                    color:
                        isToday
                            ? colorScheme.primary.withValues(alpha: 0.05)
                            : Colors.transparent,
                    border:
                        isToday
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
                          fontWeight:
                              isToday ? FontWeight.w600 : FontWeight.normal,
                          color:
                              isToday
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                        ),
                      ),
                      CalendarDayIndicators(
                        relationshipId: relationshipId,
                        date: date,
                        eventTypes: eventTypes,
                        reminderTypes: reminderTypes,
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
        if (showLegend) ...[
          CalendarLegend(
            eventTypes: _visibleEventTypes(),
            reminderTypes: _visibleOccasions(),
            hasStories: relationshipId != null,
            hasUpcoming: _hasAnyUpcoming(),
          ),
          // Room under the key before the card's edge.
          Gap(Spacing.sm.h),
        ],
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

  /// Distinct reminder occasions among [items], in order.
  List<String?> _occasions(List<dynamic> items) =>
      items
          .whereType<ReminderModel>()
          .map((r) => r.reminderType)
          .toSet()
          .toList();

  /// Distinct reminder occasions anywhere in the focused month.
  List<String?> _visibleOccasions() {
    final types = <String?>{};
    for (final entry in remindersByDate.entries) {
      if (entry.key.year == focusedMonth.year &&
          entry.key.month == focusedMonth.month) {
        types.addAll(_occasions(entry.value));
      }
    }
    return types.toList();
  }

  /// Whether the month has a plain dot to key: a plan, or anything ahead
  /// that isn't a reminder with an occasion.
  bool _hasAnyUpcoming() {
    bool inMonth(DateTime d) =>
        d.year == focusedMonth.year && d.month == focusedMonth.month;
    return remindersByDate.entries.any(
          (e) => inMonth(e.key) && e.value.any((r) => r is! ReminderModel),
        ) ||
        planningEntriesByDate.entries.any(
          (e) => inMonth(e.key) && e.value.isNotEmpty,
        );
  }
}
