// lib/features/timeline/presentation/screens/timeline_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/moments_list.dart';
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

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(timelineEventsProvider(_focusedMonth));
    final currentUserId = ref.watch(currentUserIdProvider);
    final relationshipIdAsync = ref.watch(currentRelationshipIdProvider);

    return relationshipIdAsync.when(
      data: (relationshipId) {
        if (relationshipId == null) {
          return const Center(child: Text('No active relationship found'));
        }

        return Scaffold(
          floatingActionButton: AppFab(
            icon: Icons.add,
            onPressed: () {
              context.pushNamed('logMomentType').then((refreshNeeded) {
                if (refreshNeeded == true && mounted) {
                  ref.invalidate(timelineEventsProvider(_focusedMonth));
                }
              });
            },
          ),

          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(timelineEventsProvider(_focusedMonth));
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
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
                      if (events.isEmpty) {
                        return SliverToBoxAdapter(
                          child: MomentsList(
                            events: [],
                            currentUserId: currentUserId ?? '',
                            currentMonth: _focusedMonth,
                            onDateSelected: (date) {},
                          ),
                        );
                      }
                      return SliverToBoxAdapter(
                        child: MomentsList(
                          events: events,
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
