// lib/features/timeline/presentation/screens/timeline_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/moments_list.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  void _scrollToDate(DateTime date) {
    // Find the index of the first event on or after this date
    // For now, we'll just refresh the list
    setState(() {
      _selectedDate = date;
    });
    // In a full implementation, you would scroll the list to the event
  }

  Map<DateTime, List<ReminderModel>> _remindersByDate(
    List<ReminderModel> reminders,
  ) {
    final Map<DateTime, List<ReminderModel>> grouped = {};
    for (final reminder in reminders) {
      final occurrence = nextOccurrence(reminder);
      if (occurrence.month != _focusedMonth.month ||
          occurrence.year != _focusedMonth.year) {
        continue;
      }
      final date = DateTime(occurrence.year, occurrence.month, occurrence.day);
      grouped.putIfAbsent(date, () => []).add(reminder);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(timelineEventsProvider(_focusedMonth));
    final currentUserId = ref.watch(currentUserIdProvider);
    final relationshipIdAsync = ref.watch(currentRelationshipIdProvider);
    final remindersAsync = ref.watch(
      reminders_providers.remindersListProvider,
    );

    return relationshipIdAsync.when(
      data: (relationshipId) {
        if (relationshipId == null) {
          return const Center(child: Text('No active relationship found'));
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            actions: [
              AppIconButton(
                icon: Icons.people_outline,
                tooltip: 'Family',
                onPressed: () => context.pushNamed('familyMembers'),
              ),
            ],
          ),
          floatingActionButton: AppFab(
            icon: Icons.add,
            onPressed: () async {
              final choice = await AddMomentOrReminderSheet.show(context);
              if (!mounted || choice == null) return;

              switch (choice) {
                case AddChoice.moment:
                  if (!context.mounted) return;
                  final refreshNeeded = await context.pushNamed(
                    'logMomentType',
                  );
                  if (refreshNeeded == true && mounted) {
                    ref.invalidate(timelineEventsProvider(_focusedMonth));
                  }
                case AddChoice.reminder:
                  if (!context.mounted) return;
                  await BottomSheetUtils.showDocumentationBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).colorScheme.neutral,
                    widget: const AddEditReminderScreen(),
                  );
                  if (mounted) {
                    ref.invalidate(reminders_providers.remindersListProvider);
                  }
              }
            },
          ),

          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(timelineEventsProvider(_focusedMonth));
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: remindersAsync.when(
                    data: (reminders) {
                      if (reminders.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: Spacing.md.w,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Gap(Spacing.md.h),
                            Text(
                              'Upcoming',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Gap(Spacing.sm.h),
                            UpcomingRemindersSection(
                              reminders: reminders,
                              onReminderTap: (reminder) {},
                            ),
                            const Divider(height: 32),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                  ),
                ),
                // Calendar strip as SliverToBoxAdapter
                SliverToBoxAdapter(
                  child: eventsAsync.when(
                    data: (events) {
                      // Group events by date for calendar dots
                      final Map<DateTime, List<TimelineEventModel>>
                      eventsByDate = {};
                      for (final event in events) {
                        final date = DateTime(
                          event.occurredAt.year,
                          event.occurredAt.month,
                          event.occurredAt.day,
                        );
                        if (!eventsByDate.containsKey(date)) {
                          eventsByDate[date] = [];
                        }
                        eventsByDate[date]!.add(event);
                      }

                      return Column(
                        children: [
                          Gap(Spacing.md.h),
                          CalendarStrip(
                            focusedMonth: _focusedMonth,
                            eventsByDate: eventsByDate,
                            remindersByDate: _remindersByDate(
                              remindersAsync.valueOrNull ?? const [],
                            ),
                            selectedDate: _selectedDate,
                            onDaySelected: (date) {
                              _scrollToDate(date);
                            },
                            onMonthChanged: (month) {
                              setState(() {
                                _focusedMonth = month;
                              });
                              ref.invalidate(timelineEventsProvider(month));
                            },
                          ),
                          const Divider(height: 32),
                        ],
                      );
                    },
                    loading:
                        () => const Column(
                          children: [
                            SizedBox(height: 300),
                            Center(child: CircularProgressIndicator()),
                          ],
                        ),
                    error:
                        (error, stack) => Column(
                          children: [
                            const SizedBox(height: 300),
                            Center(
                              child: Text('Error loading calendar: $error'),
                            ),
                          ],
                        ),
                  ),
                ),
                // Moments list as SliverList
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                  sliver: eventsAsync.when(
                    data: (events) {
                      final excludedIds = linkedTimelineEventIds(
                        remindersAsync.valueOrNull ?? const [],
                      );
                      final visibleEvents =
                          events
                              .where((event) => !excludedIds.contains(event.id))
                              .toList();

                      if (visibleEvents.isEmpty) {
                        return SliverToBoxAdapter(
                          child: MomentsList(
                            events: const [],
                            currentUserId: currentUserId ?? '',
                            currentMonth: _focusedMonth,
                            onDateSelected: (date) {},
                          ),
                        );
                      }
                      return SliverToBoxAdapter(
                        child: MomentsList(
                          events: visibleEvents,
                          currentUserId: currentUserId ?? '',
                          currentMonth: _focusedMonth,
                          onDateSelected: _scrollToDate,
                        ),
                      );
                    },
                    loading:
                        () => const SliverToBoxAdapter(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    error:
                        (error, stack) => SliverToBoxAdapter(
                          child: Center(
                            child: Text('Error loading moments: $error'),
                          ),
                        ),
                  ),
                ),
                // Bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        );
      },
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error:
          (error, stack) =>
              Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}
