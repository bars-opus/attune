// lib/features/timeline/presentation/screens/timeline_screen.dart

import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    as planning_providers;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/moments_list.dart';
import 'package:attune/features/timeline/presentation/widgets/planning_day_section.dart';
import 'package:attune/features/timeline/presentation/screens/calendar_all_months_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_month_data.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({
    super.key,
    this.showAppBar = false,
    this.showOwnAppBar = true,
  });

  /// Whether this instance owns its own Scaffold/scroll controller rather
  /// than relying on an ancestor `NestedScrollView` (see the controller
  /// note below).
  final bool showAppBar;

  /// Whether to render the timeline's own `AppBar` when [showAppBar] is
  /// true. Embedded as a tab under a host screen that already supplies an
  /// `AppBar` (Planning's Calendar tab), this is false so the two do not
  /// stack — while the standalone `/couples-calendar` route keeps its own
  /// bar, and with it the only entry point to the Family screen.
  final bool showOwnAppBar;

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen>
    with AutomaticKeepAliveClientMixin {
  DateTime _focusedMonth = timelineMonthKey(DateTime.now());
  DateTime? _selectedDate;
  final ScrollController _scrollController = ScrollController();

  // Keeps this tab's state (focused month, selected date, scroll position)
  // alive when TabBarView scrolls it off-screen switching tabs, instead of
  // disposing and rebuilding from scratch every time the user comes back
  // to Timeline.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  void _selectDate(DateTime date) => setState(() => _selectedDate = date);

  /// Tapping a date opens that day in a sheet: its stories as a
  /// tappable row, plus the moments and scheduled items on it.
  void _openDaySheet({
    required DateTime date,
    required List<TimelineEventModel> events,
    required List<dynamic> reminders,
    required List<dynamic> planningEntries,
    required String? relationshipId,
  }) {
    showCalendarDaySheet(
      context: context,
      relationshipId: relationshipId,
      date: date,
      events: events,
      reminders: reminders,
      planningEntries: planningEntries,
    );
  }

  /// Every month, vertically, with the same marks (the calendar card's
  /// All months button).
  void _openAllMonths(String relationshipId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CalendarAllMonthsScreen(relationshipId: relationshipId),
    ),
  );

  Map<DateTime, List<ReminderModel>> _remindersByDate(
    List<ReminderModel> reminders,
  ) => remindersByDateInMonth(reminders, _focusedMonth);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Planning dates and to-dos plus this month's Together events, by day:
  /// the calendar's "scheduled" rings and the day sheet's Scheduled list.
  Map<DateTime, List<Object>> _scheduledByDate(
    List<PlanningCalendarEntry> entries,
    List<TogetherItem> together,
  ) => scheduledByDay(entries, together);

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin requirement
    final eventsAsync = ref.watch(timelineEventsProvider(_focusedMonth));
    final currentUserId = ref.watch(currentUserIdProvider);
    final partnerName =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final relationshipIdAsync = ref.watch(currentRelationshipIdProvider);
    final remindersAsync = ref.watch(reminders_providers.remindersListProvider);
    // Range is exactly the focused month's first-to-last day — the ONLY
    // dates CalendarStrip's grid actually renders day numbers for; its
    // leading/trailing offset cells for adjacent months are
    // SizedBox.shrink() and never show a dot, so fetching entries for
    // those dates would fetch data that's never displayed. This also
    // keeps every range comfortably under the 42-day cap (Plan A).
    final planningEntriesAsync =
        relationshipIdAsync.valueOrNull == null
            ? const AsyncValue<List<PlanningCalendarEntry>>.data([])
            : ref.watch(
              planning_providers.planningCalendarEntriesProvider((
                relationshipId: relationshipIdAsync.valueOrNull!,
                start: DateTime(_focusedMonth.year, _focusedMonth.month, 1),
                end: DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0),
              )),
            );

    // This month's Together events, for the calendar and its day sheet.
    final togetherEventsAsync =
        relationshipIdAsync.valueOrNull == null
            ? const AsyncValue<List<TogetherItem>>.data([])
            : ref.watch(
              togetherRangeProvider((
                relationshipId: relationshipIdAsync.valueOrNull!,
                start: DateTime(_focusedMonth.year, _focusedMonth.month, 1),
                end: DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0),
              )),
            );
    final togetherEvents =
        togetherEventsAsync.valueOrNull ?? const <TogetherItem>[];

    return relationshipIdAsync.when(
      data: (relationshipId) {
        if (relationshipId == null) {
          return const Center(child: Text('No active relationship found'));
        }

        // Live: a partner's new moment or reminder refetches this screen.
        ref.watch(timelineAutoRefreshProvider(relationshipId));

        return Scaffold(
          appBar:
              widget.showAppBar && widget.showOwnAppBar
                  ? AppBar(
                    backgroundColor: Colors.transparent,
                    actions: [
                      AppIconButton(
                        icon: Icons.people_outline,
                        tooltip: 'Family',
                        onPressed: () => showFamilySheet(context),
                      ),
                    ],
                  )
                  : null,
          floatingActionButton: AppFab(
            icon: Icons.add,
            onPressed:
                () => openAddFlow(context, relationshipId: relationshipId),
          ),

          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(timelineEventsProvider);
              ref.invalidate(reminders_providers.remindersListProvider);
              ref.invalidate(togetherRangeProvider);
              ref.invalidate(
                planning_providers.planningCalendarEntriesProvider,
              );
            },
            child: CustomScrollView(
              // Standalone (showAppBar: true, own route/Scaffold) keeps its
              // own explicit controller. Embedded (showAppBar: false, the
              // only way PulseTab hosts this) must NOT pass one:
              // NestedScrollView's own doc is explicit that its `body` is
              // built expecting descendants to default to the
              // PrimaryScrollController it provides — an explicit
              // controller here would opt this scrollable out of that
              // coordination entirely, silently reproducing the exact
              // "header doesn't scroll with this tab" bug being fixed.
              controller: widget.showAppBar ? _scrollController : null,
              slivers: [
                if (!widget.showAppBar)
                  // Required only when embedded inside PulseTab's
                  // NestedScrollView — calling this with no NestedScrollView
                  // ancestor (the standalone route) would assert.
                  SliverOverlapInjector(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: remindersAsync.when(
                    data: (reminders) {
                      if (upcomingReminders(reminders).isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return UpcomingRemindersSection(
                        reminders: reminders,
                        onReminderTap: (reminder) async {
                          await showReminderSheet(context, reminder: reminder);
                          if (mounted) {
                            ref.invalidate(
                              reminders_providers.remindersListProvider,
                            );
                          }
                        },
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
                      // Moments by day for the calendar, less any a
                      // reminder on the same day already stands for.
                      final eventsByDate = momentsByDay(
                        events,
                        remindersByDate: _remindersByDate(
                          remindersAsync.valueOrNull ?? const [],
                        ),
                      );

                      return CardInkWell(
                        padding: const EdgeInsets.only(top: Spacing.lg),
                        child: CalendarStrip(
                          focusedMonth: _focusedMonth,
                          relationshipId: relationshipId,
                          eventsByDate: eventsByDate,
                          remindersByDate: _remindersByDate(
                            remindersAsync.valueOrNull ?? const [],
                          ),
                          planningEntriesByDate: _scheduledByDate(
                            planningEntriesAsync.valueOrNull ?? const [],
                            togetherEvents,
                          ),
                          selectedDate: _selectedDate,
                          onShowAll: () => _openAllMonths(relationshipId),
                          onDaySelected: (date) {
                            _selectDate(date);
                            _openDaySheet(
                              date: date,
                              events: eventsByDate[date] ?? const [],
                              reminders:
                                  _remindersByDate(
                                    remindersAsync.valueOrNull ?? const [],
                                  )[date] ??
                                  const [],
                              planningEntries:
                                  _scheduledByDate(
                                    planningEntriesAsync.valueOrNull ??
                                        const [],
                                    togetherEvents,
                                  )[date] ??
                                  const [],
                              relationshipId: relationshipId,
                            );
                          },
                          onMonthChanged: (month) {
                            setState(() {
                              _focusedMonth = timelineMonthKey(month);
                            });
                            ref.invalidate(
                              timelineEventsProvider(timelineMonthKey(month)),
                            );
                          },
                        ),
                      );
                    },
                    loading:
                        () => CardInkWell(
                          padding: const EdgeInsets.only(top: Spacing.lg),
                          child: CalendarStrip(
                            focusedMonth: _focusedMonth,
                            relationshipId: relationshipId,
                            remindersByDate: _remindersByDate(
                              remindersAsync.valueOrNull ?? const [],
                            ),
                            planningEntriesByDate: _scheduledByDate(
                              planningEntriesAsync.valueOrNull ?? const [],
                              togetherEvents,
                            ),
                            selectedDate: _selectedDate,
                            onShowAll: () => _openAllMonths(relationshipId),
                            onDaySelected: (date) {
                              _selectDate(date);
                            },
                            onMonthChanged: (month) {
                              setState(() {
                                _focusedMonth = timelineMonthKey(month);
                              });
                              ref.invalidate(
                                timelineEventsProvider(timelineMonthKey(month)),
                              );
                            },
                            eventsByDate: {},
                          ),
                        ),
                    error:
                        (error, stack) => Center(
                          child: ErrorStateWidget(
                            title: '',
                            subtitle: 'Error loading calendar: $error',
                          ),
                        ),
                  ),
                ),
                // A selected day's stories and past moments now live in
                // the day sheet that tapping a date opens
                // (calendar_day_sheet.dart) — the inline sections below
                // the calendar carry UPCOMING items only, so the screen
                // answers "what is coming" without having to scroll past
                // a day that already happened.
                if (_selectedDate != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                      child: PlanningDaySection(
                        relationshipId: relationshipId,
                        entries:
                            planningEntriesAsync.valueOrNull
                                ?.where(
                                  (e) =>
                                      _isSameDay(e.date, _selectedDate!) &&
                                      !e.date.isBefore(
                                        DateTime(
                                          DateTime.now().year,
                                          DateTime.now().month,
                                          DateTime.now().day,
                                        ),
                                      ),
                                )
                                .toList() ??
                            const [],
                      ),
                    ),
                  ),
                // Moments list as SliverList
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                  sliver: eventsAsync.when(
                    data: (events) {
                      final excludedIds = linkedTimelineEventIds(
                        upcomingReminders(
                          remindersAsync.valueOrNull ?? const [],
                        ),
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
                            partnerName: partnerName,
                            onDateSelected: (date) {},
                          ),
                        );
                      }
                      return SliverToBoxAdapter(
                        child: MomentsList(
                          events: visibleEvents,
                          currentUserId: currentUserId ?? '',
                          currentMonth: _focusedMonth,
                          partnerName: partnerName,
                          onDateSelected: _selectDate,
                        ),
                      );
                    },
                    loading:
                        () => const SliverToBoxAdapter(
                          child: Center(child: CircularLoadingIndicator()),
                        ),
                    error:
                        (error, stack) => SliverToBoxAdapter(
                          child: Center(
                            child: ErrorStateWidget(
                              title: '',
                              subtitle: 'Error loading moments: $error',
                            ),
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
