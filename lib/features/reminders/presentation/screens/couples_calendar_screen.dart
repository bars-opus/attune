// lib/features/reminders/presentation/screens/couples_calendar_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/reminders/presentation/screens/calendar_month_view.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';

class CouplesCalendarScreen extends ConsumerStatefulWidget {
  const CouplesCalendarScreen({super.key});

  @override
  ConsumerState<CouplesCalendarScreen> createState() =>
      _CouplesCalendarScreenState();
}

class _CouplesCalendarScreenState extends ConsumerState<CouplesCalendarScreen> {
  DateTime _focusedMonth = DateTime.now();

  DateTime _nextOccurrence(ReminderModel reminder) {
    if (!reminder.isRecurring) return reminder.remindAt;
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      reminder.remindAt.month,
      reminder.remindAt.day,
    );
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(
        now.year + 1,
        reminder.remindAt.month,
        reminder.remindAt.day,
      );
    }
    return next;
  }

  String _countdownLabel(DateTime occurrence) {
    final today = DateTime.now();
    final days =
        DateTime(
          occurrence.year,
          occurrence.month,
          occurrence.day,
        ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }

  Widget _buildListTab(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersListProvider);
    final textTheme = Theme.of(context).textTheme;

    return remindersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, stack) => Center(
            child: ErrorStateWidget(
              title: 'Something went wrong',
              subtitle:
                  'We couldn\'t load your calendar right now. Please try again in a moment.',
            ),
          ),
      data: (reminders) {
        final timelineAsync = ref.watch(timelineAnniversariesThisMonthProvider);
        final sorted = [...reminders]
          ..sort((a, b) => _nextOccurrence(a).compareTo(_nextOccurrence(b)));

        if (reminders.isEmpty) {
          return timelineAsync.maybeWhen(
            data:
                (timelineEvents) =>
                    timelineEvents.isEmpty
                        ? Center(
                          child: EmptyStateWidget(
                            title: 'No events yet',
                            subtitle:
                                'Add an anniversary, birthday, or any date you want to remember together.',
                          ),
                        )
                        : _buildList(
                          context,
                          sorted,
                          timelineEvents,
                          textTheme,
                        ),
            orElse:
                () => Center(
                  child: EmptyStateWidget(
                    title: 'No events yet',
                    subtitle:
                        'Add an anniversary, birthday, or any date you want to remember together.',
                  ),
                ),
          );
        }

        return timelineAsync.maybeWhen(
          data:
              (timelineEvents) =>
                  _buildList(context, sorted, timelineEvents, textTheme),
          orElse: () => _buildList(context, sorted, const [], textTheme),
        );
      },
    );
  }

  Widget _buildCalendarTab(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersListProvider);
    final timelineAsync = ref.watch(timelineEventsProvider(_focusedMonth));

    return remindersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (error, stack) => Center(
            child: ErrorStateWidget(
              title: 'Something went wrong',
              subtitle:
                  'We couldn\'t load your calendar right now. Please try again in a moment.',
            ),
          ),
      data: (reminders) {
        return CalendarMonthView(
          focusedMonth: _focusedMonth,
          reminders: reminders,
          timelineEvents: timelineAsync.valueOrNull ?? const [],
          onDaySelected: (day) {},
          onMonthChanged: (month) => setState(() => _focusedMonth = month),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final docs = HealingDocs();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Calendar',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        actions: [
          AppIconButton(
            icon: Icons.people_outline,
            tooltip: 'Family',
            onPressed: () => context.pushNamed('familyMembers'),
          ),

          AppIconButton(
            icon: Icons.notes_rounded,
            tooltip: 'Docs',
            onPressed: () {
              BottomSheetUtils.showDocumentationBottomSheet(
                context: context,
                showButtons: false,
                widget: DocumentationTabView(
                  module: docs,
                  showDocumentationFirst: true,
                ),
              );
            },
          ),
        ],
      ),
      body: TabsWithContent(
        showContent: true,
        initialIndex: 0,
        scrollable: false,

        tabs: [
          AppTabItem(
            label: 'Upcoming',
            icon: Icons.arrow_upward,
            content: Consumer(
              builder: (context, ref, _) => _buildListTab(context, ref),
            ),
          ),
          AppTabItem(
            label: 'Calendar',
            icon: Icons.calendar_month,
            content: Consumer(
              builder: (context, ref, _) => _buildCalendarTab(context, ref),
            ),
          ),
        ],
      ),
      floatingActionButton: AppFab(
        icon: Icons.add,
        onPressed: () {
          BottomSheetUtils.showDocumentationBottomSheet(
            context: context,
            backgroundColor: colorScheme.neutral,
            widget: AddEditReminderScreen(),
          );
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<ReminderModel> reminders,
    List<TimelineEventModel> timelineEvents,
    TextTheme textTheme,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.all(Spacing.md.w),
      children: [
        if (timelineEvents.isNotEmpty) ...[
          SemanticContainerWidget(
            content: 'This month in your Timeline',
            icon: Icons.notifications_active_outlined,
            title: '',
            backgroundColor: colorScheme.info.withOpacity(0.1),
            borderColor: colorScheme.info,
            iconColor: colorScheme.info,
            textTheme: textTheme,
          ),
          // Text('This month in your Timeline', style: textTheme.titleSmall),
          Gap(Spacing.sm.h),
          for (final event in timelineEvents)
            CardInkWell(
              child: InfoRowWidget(
                subtitle: '',
                title: event.title,
                icon: Icons.history_outlined,
                iconSize: 20.h,
                onTap: () {},
                disableTrailing: true,
                showAvatar: false,
                showDivider: false,
                showTrailingArrow: false,
              ),
            ),
          Gap(Spacing.lg.h),
        ],
        for (final reminder in reminders)
          CardInkWell(
            child: InfoRowWidget(
              subtitle: _countdownLabel(_nextOccurrence(reminder)),
              title: reminder.title,
              icon:
                  reminder.isRecurring
                      ? FontAwesomeIcons.repeat
                      : Icons.event_outlined,
              iconSize: 20.h,
              onTap: () {},
              disableTrailing: true,
              showAvatar: false,
              showDivider: false,
              showTrailingArrow: false,
            ),
          ),
      ],
    );
  }
}
