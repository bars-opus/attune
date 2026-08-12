import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// Month-grid calendar for the couple's reminders + timeline anniversaries.
/// UI/config (row height, gestures, header, marker styling) is unchanged
/// from the original pasted implementation — only the input/data plumbing
/// was rewired from that app's shop-booking model onto this app's
/// ReminderModel/TimelineEventModel.
class CalendarMonthView extends ConsumerWidget {
  final DateTime focusedMonth;
  final List<ReminderModel> reminders;
  final List<TimelineEventModel> timelineEvents;
  final Function(DateTime) onDaySelected;
  final Function(DateTime) onMonthChanged;

  const CalendarMonthView({
    super.key,
    required this.focusedMonth,
    required this.reminders,
    required this.timelineEvents,
    required this.onDaySelected,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Each day maps to a mixed list of ReminderModel/TimelineEventModel —
    // recurring reminders are plotted on every year's occurrence within
    // this month, not just their original remindAt year.
    //
    // A reminder created via "Add to Timeline too?" (add_edit_reminder_
    // screen.dart's _offerTimelineLink) produces TWO rows for the same
    // real-world event — a ReminderModel and a linked TimelineEventModel,
    // same date. Looping both lists independently double-counted it as two
    // markers on one day; linkedIds tracks which timeline events already
    // have a reminder representing them so they're skipped below.
    final linkedTimelineEventIds =
        reminders
            .map((reminder) => reminder.linkedTimelineEventId)
            .whereType<String>()
            .toSet();

    final events = <DateTime, List<dynamic>>{};
    for (final reminder in reminders) {
      final occurrence = _occurrenceInMonth(reminder, focusedMonth);
      if (occurrence == null) continue;
      final date = DateTime.utc(
        occurrence.year,
        occurrence.month,
        occurrence.day,
      );
      events.putIfAbsent(date, () => []).add(reminder);
    }
    for (final event in timelineEvents) {
      if (linkedTimelineEventIds.contains(event.id)) continue;
      final date = DateTime.utc(
        event.occurredAt.year,
        event.occurredAt.month,
        event.occurredAt.day,
      );
      events.putIfAbsent(date, () => []).add(event);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 30.0),
      child: Listener(
        onPointerMove: (event) {
          if (event.delta.dy.abs() > event.delta.dx.abs()) {
            // Allow parent to scroll
          }
        },
        behavior: HitTestBehavior.opaque,
        child: TableCalendar(
          rowHeight: 40.h,
          daysOfWeekHeight: 25.h,
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: focusedMonth,
          pageAnimationCurve: Curves.easeInOut,
          availableGestures: AvailableGestures.horizontalSwipe,
          selectedDayPredicate: (day) => false,
          onDaySelected: (selectedDay, focusedDay) {
            final normalizedDay = DateTime.utc(
              selectedDay.year,
              selectedDay.month,
              selectedDay.day,
            );
            final dayEvents = events[normalizedDay] ?? [];
            if (dayEvents.isNotEmpty) {
              _showDayEventsSheet(context, selectedDay, dayEvents);
            }
            onDaySelected(selectedDay);
          },
          onPageChanged: (focusedDay) {
            HapticFeedback.lightImpact();
            onMonthChanged(focusedDay);
          },
          eventLoader: (day) {
            final normalizedDay = DateTime.utc(day.year, day.month, day.day);
            return events[normalizedDay] ?? [];
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, _) {
              final normalizedDate = DateTime.utc(
                date.year,
                date.month,
                date.day,
              );
              final dayEvents = events[normalizedDate] ?? [];
              if (dayEvents.isEmpty) return const SizedBox();

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children:
                    dayEvents.take(3).map((event) {
                      final statusColor = _getMarkerColor(event, colorScheme);

                      return AnimatedScaleFade(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutBack,
                        child: Container(
                          width: 12.h,
                          height: 12.w,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                          ),
                        ),
                      );
                    }).toList(),
              );
            },
          ),
          calendarStyle: CalendarStyle(
            defaultTextStyle: theme.textTheme.bodyMedium!.copyWith(
              color: colorScheme.onSurface,
            ),
            cellMargin: EdgeInsets.all(0),
            todayDecoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: .2),
              shape: BoxShape.circle,
            ),
            markersMaxCount: 0,
          ),
          headerStyle: HeaderStyle(
            titleTextStyle: theme.textTheme.bodyMedium!.copyWith(
              color: colorScheme.onSurface,
            ),
            headerMargin: EdgeInsets.symmetric(vertical: 20.h, horizontal: 20),
            titleCentered: false,
            leftChevronVisible: false,
            rightChevronVisible: false,
            formatButtonVisible: false,
            leftChevronIcon: Icon(
              Icons.chevron_left,
              color: colorScheme.primary,
            ),
            rightChevronIcon: Icon(
              Icons.chevron_right,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// A recurring (yearly) reminder repeats every year on the same
  /// month/day — this returns its occurrence within [month] specifically
  /// (or null if this reminder doesn't fall in this month at all), so the
  /// marker shows up on every month the calendar pages to, not just the
  /// reminder's original creation year.
  DateTime? _occurrenceInMonth(ReminderModel reminder, DateTime month) {
    if (!reminder.isRecurring) {
      return reminder.remindAt.year == month.year &&
              reminder.remindAt.month == month.month
          ? reminder.remindAt
          : null;
    }
    return reminder.remindAt.month == month.month
        ? DateTime(month.year, reminder.remindAt.month, reminder.remindAt.day)
        : null;
  }

  /// Reminders and timeline anniversaries get distinct marker colors so a
  /// day with both reads as two different kinds of event at a glance —
  /// recurring reminders in primary, one-off reminders in info, timeline
  /// anniversaries in success.
  Color _getMarkerColor(dynamic event, ColorScheme colorScheme) {
    if (event is TimelineEventModel) return colorScheme.success;
    if (event is ReminderModel) {
      return event.isRecurring ? colorScheme.primary : colorScheme.info;
    }
    return colorScheme.onSurfaceVariant;
  }

  /// Same tile styles CouplesCalendarScreen's own "Upcoming" tab already
  /// uses for reminders (Container card, repeat/event icon) and timeline
  /// events (plain ListTile, history icon) — the tap-a-day sheet is meant
  /// to read as "the same events, filtered to this one day," not a new
  /// visual language.
  void _showDayEventsSheet(
    BuildContext context,
    DateTime day,
    List<dynamic> dayEvents,
  ) {
    final textTheme = Theme.of(context).textTheme;
    BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      widget: _DayEventsSheet(
        day: day,
        events: dayEvents,
        textTheme: textTheme,
      ),
    );
  }
}

class _DayEventsSheet extends StatelessWidget {
  const _DayEventsSheet({
    required this.day,
    required this.events,
    required this.textTheme,
  });

  final DateTime day;
  final List<dynamic> events;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat.yMMMd().format(day), style: textTheme.titleMedium),
        Gap(Spacing.md.h),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: events.length,
            separatorBuilder: (_, __) => Gap(Spacing.sm.h),
            itemBuilder: (context, index) {
              final event = events[index];
              if (event is TimelineEventModel) {
                return ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: Text(event.title),
                  contentPadding: EdgeInsets.zero,
                );
              }
              if (event is ReminderModel) {
                return Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        event.isRecurring ? Icons.repeat : Icons.event_outlined,
                      ),
                      Gap(Spacing.sm.w),
                      Expanded(
                        child: Text(event.title, style: textTheme.titleSmall),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}
