import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    as planning_providers;
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_month_data.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Months either side of this one in the All months view.
const kAllMonthsSpan = 12;

/// Every month, scrolling vertically — like the date-range picker — with
/// the same marks as the Month calendar: occasion icons for reminders,
/// filled dots for plans, outlined rings for stories, coloured circles for
/// moments. Opens on this
/// month; each month loads only when it scrolls into view.
class CalendarAllMonthsScreen extends ConsumerWidget {
  const CalendarAllMonthsScreen({super.key, required this.relationshipId});
  final String relationshipId;

  static const _thisMonthKey = ValueKey('all-months-this-month');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    DateTime month(int offset) => DateTime(now.year, now.month + offset);
    // Each month on the page, an AppDivider under it (none after the last).
    Widget section(int offset) => Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.sm.h),
          child: _MonthSection(
            relationshipId: relationshipId,
            month: month(offset),
          ),
        ),
        if (offset < kAllMonthsSpan) AppDivider(),
      ],
    );
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    // Every occasion our reminders carry, so the key explains each icon.
    final occasions =
        (ref.watch(reminders_providers.remindersListProvider).valueOrNull ??
                const [])
            .map((r) => r.reminderType)
            .toSet()
            .toList();
    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          'All months',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body: Column(
        children: [
          // One key for the whole list, fixed above it; it wraps onto a
          // second line when our reminders carry many occasions.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.xs.w),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CalendarLegend(
                eventTypes: const [],
                reminderTypes: occasions,
                hasStories: true,
                hasUpcoming: true,
              ),
            ),
          ),
          // Months before this one grow upwards from it, months after it
          // grow downwards, so the list opens right on this month.
          Expanded(
            child: CustomScrollView(
              center: _thisMonthKey,
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => section(-(i + 1)),
                    childCount: kAllMonthsSpan,
                  ),
                ),
                SliverList(
                  key: _thisMonthKey,
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => section(i),
                    childCount: kAllMonthsSpan + 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One month's grid with its marks, loading its own moments, plans and
/// Together events (reminders are shared); a tap opens the day.
class _MonthSection extends ConsumerWidget {
  const _MonthSection({required this.relationshipId, required this.month});
  final String relationshipId;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = timelineMonthKey(month);
    final range = (
      relationshipId: relationshipId,
      start: DateTime(month.year, month.month, 1),
      end: DateTime(month.year, month.month + 1, 0),
    );
    final reminders = remindersByDateInMonth(
      ref.watch(reminders_providers.remindersListProvider).valueOrNull ??
          const [],
      month,
    );
    final moments = momentsByDay(
      ref.watch(timelineEventsProvider(key)).valueOrNull ?? const [],
      remindersByDate: reminders,
    );
    final scheduled = scheduledByDay(
      ref
              .watch(planning_providers.planningCalendarEntriesProvider(range))
              .valueOrNull ??
          const <PlanningCalendarEntry>[],
      ref.watch(togetherRangeProvider(range)).valueOrNull ??
          const <TogetherItem>[],
    );
    return CalendarStrip(
      focusedMonth: key,
      relationshipId: relationshipId,
      eventsByDate: moments,
      remindersByDate: reminders,
      planningEntriesByDate: scheduled,
      showNavigation: false,
      showLegend: false,
      onMonthChanged: (_) {},
      onDaySelected:
          (date) => showCalendarDaySheet(
            context: context,
            relationshipId: relationshipId,
            date: date,
            events: moments[date] ?? const [],
            reminders: reminders[date] ?? const [],
            planningEntries: scheduled[date] ?? const [],
          ),
    );
  }
}
