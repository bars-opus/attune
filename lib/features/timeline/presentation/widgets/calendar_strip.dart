// lib/features/timeline/presentation/widgets/calendar_strip.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';



class CalendarStrip extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<DateTime, List<TimelineEventModel>> eventsByDate;
  final Function(DateTime) onDaySelected;
  final Function(DateTime) onMonthChanged;
  final DateTime? selectedDate;

  const CalendarStrip({
    super.key,
    required this.focusedMonth,
    required this.eventsByDate,
    required this.onDaySelected,
    required this.onMonthChanged,
    this.selectedDate,
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
              final hasEvents = eventsOnDate.isNotEmpty;
              
              // Get unique event types for dots
              final eventTypes = eventsOnDate.map((e) => e.eventType).toSet().toList();
              final dotColors = eventTypes.map((type) => _getEventTypeColor(type, colorScheme)).toList();
              
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
                      if (hasEvents)
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: dotColors.take(3).map((color) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
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

  Color _getEventTypeColor(String eventType, ColorScheme colorScheme) {
    switch (eventType) {
      case 'milestone': return colorScheme.primary;
      case 'conflict': return Colors.red;
      case 'highlight': return Colors.amber;
      case 'first': return Colors.purple;
      case 'anniversary': return Colors.pink;
      default: return colorScheme.primary;
    }
  }
}
