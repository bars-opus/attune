import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    as planning_providers;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/reminder_icons.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/calendar_all_months_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// No stories on any day (the day sheet asks).
class _NoStories implements StoryReadGateway {
  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
    String? authorId,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  // Change signals never fire; channel clean-up is a no-op.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #watchChangeSignal ? const Stream<void>.empty() : null;
}

class _Reminders extends RemindersListNotifier {
  _Reminders(this.items);
  final List<ReminderModel> items;
  @override
  Future<List<ReminderModel>> build() async => items;
}

ReminderModel _reminder(DateTime at, {String? linkedTo, String type = 'birthday', String id = 'rem-1'}) => ReminderModel(
  id: id,
  relationshipId: 'r1',
  createdBy: 'ama',
  reminderType: type,
  title: "Ama's birthday",
  remindAt: at,
  recurrence: 'none',
  sent: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  linkedTimelineEventId: linkedTo,
);

/// The memory the reminder sheet's "Add to your Timeline too?" logs.
TimelineEventModel _linkedMoment(DateTime at) => TimelineEventModel(
  id: 'moment-1',
  relationshipId: 'r1',
  loggedBy: 'ama',
  eventType: 'anniversary',
  title: "Ama's birthday",
  occurredAt: at,
  createdAt: DateTime(2026),
);

Widget _app(
  Widget home, {
  List<ReminderModel> reminders = const [],
  List<TimelineEventModel> moments = const [],
}) => ProviderScope(
  overrides: [
    timelineEventsProvider.overrideWith((ref, month) async => moments),
    currentUserIdProvider.overrideWithValue('ama'),
    remindersListProvider.overrideWith(() => _Reminders(reminders)),
    planning_providers.planningCalendarEntriesProvider.overrideWith((ref, a) async => []),
    togetherRangeProvider.overrideWith((ref, a) async => []),
    storyDayCountsProvider.overrideWith((ref, key) async => []),
    togetherMeProvider.overrideWithValue('ama'),
    currentUserProvider.overrideWithValue(null),
    storyReadGatewayProvider.overrideWithValue(_NoStories()),
  ],
  child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: home)),
);

void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month);
  String title(DateTime m) => DateFormat('MMMM yyyy').format(m);

  testWidgets('the calendar card offers All months', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    var opened = 0;
    await t.pumpWidget(
      _app(
        Scaffold(
          body: CalendarStrip(
            focusedMonth: thisMonth,
            eventsByDate: const {},
            onDaySelected: (_) {},
            onMonthChanged: (_) {},
            onShowAll: () => opened++,
          ),
        ),
      ),
    );
    await t.tap(find.byTooltip('All months'));
    expect(opened, 1);
  });

  testWidgets('All months opens on this month and runs downwards; no arrows', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const CalendarAllMonthsScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    expect(find.text(title(thisMonth)), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    // The current month is on screen as it opens, with next month below it.
    final next = DateTime(now.year, now.month + 1);
    await t.scrollUntilVisible(find.text(title(next)), 200, scrollable: find.byType(Scrollable).first);
    expect(t.getTopLeft(find.text(title(next))).dy, greaterThan(t.getTopLeft(find.text(title(thisMonth)), warnIfMissed: false).dy));
  });

  testWidgets('months sit on the page, an AppDivider between them (no cards)', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const CalendarAllMonthsScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    expect(find.byType(CardInkWell), findsNothing);
    final next = DateTime(now.year, now.month + 1);
    await t.scrollUntilVisible(find.text(title(next)), 200, scrollable: find.byType(Scrollable).first);
    final thisBottom = t.getBottomLeft(find.text(title(thisMonth)), warnIfMissed: false).dy;
    final nextTop = t.getTopLeft(find.text(title(next))).dy;
    final between = t.widgetList(find.byType(AppDivider)).map((w) => t.getTopLeft(find.byWidget(w)).dy).where((y) => y > thisBottom && y < nextTop);
    expect(between, isNotEmpty);
  });

  testWidgets('a birthday day shows its cake, and opens its day', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final day = now.day == 28 ? 27 : 28;
    final at = DateTime(now.year, now.month, day);
    await t.pumpWidget(_app(const CalendarAllMonthsScreen(relationshipId: 'r1'), reminders: [_reminder(at)]));
    await t.pumpAndSettle();
    final mark = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Birthday');
    expect(mark, findsWidgets);
    expect(find.descendant(of: mark.first, matching: find.byIcon(reminderOccasionIcon('birthday'))), findsOneWidget);
    await t.tap(find.text('$day').first);
    await t.pumpAndSettle();
    expect(find.text(DateFormat('EEEE, MMMM d, yyyy').format(at)), findsOneWidget);
    expect(find.text("Ama's birthday"), findsWidgets);
  });

  testWidgets('a reminder and the memory it logged show once on their day', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final day = now.day == 28 ? 27 : 28;
    final at = DateTime(now.year, now.month, day);
    await t.pumpWidget(
      _app(
        const CalendarAllMonthsScreen(relationshipId: 'r1'),
        reminders: [_reminder(at, linkedTo: 'moment-1')],
        moments: [_linkedMoment(at)],
      ),
    );
    await t.pumpAndSettle();
    // The day shows the birthday, not also a moment.
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Birthday'), findsWidgets);
    expect(find.byIcon(Icons.favorite), findsNothing);
    await t.tap(find.text('$day').first);
    await t.pumpAndSettle();
    expect(find.text("Ama's birthday"), findsOneWidget);
    expect(find.text('Moments'), findsNothing);
  });

  testWidgets('a memory whose reminder now falls on another day still shows', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final at = DateTime(now.year, now.month, now.day == 28 ? 27 : 28);
    final moved = DateTime(now.year, now.month, now.day == 20 ? 21 : 20);
    await t.pumpWidget(
      _app(
        const CalendarAllMonthsScreen(relationshipId: 'r1'),
        reminders: [_reminder(moved, linkedTo: 'moment-1')],
        moments: [_linkedMoment(at)],
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('${at.day}').first);
    await t.pumpAndSettle();
    expect(find.text('Moments'), findsOneWidget);
  });

  testWidgets("the key names our reminders' occasions, above the months", (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app(
        const CalendarAllMonthsScreen(relationshipId: 'r1'),
        reminders: [
          _reminder(DateTime(2020, 3, 4), type: 'birthday'),
          _reminder(DateTime(2020, 5, 6), type: 'anniversary', id: 'rem-2'),
          _reminder(DateTime(2020, 7, 8), type: 'custom', id: 'rem-3'),
        ],
      ),
    );
    await t.pumpAndSettle();
    final key = find.byType(CalendarLegend);
    for (final label in ['Story', 'Upcoming', 'Birthday', 'Anniversary', 'Reminder']) {
      expect(find.descendant(of: key, matching: find.text(label)), findsOneWidget);
    }
    // Wrapping as it needs, whole, above the first month.
    expect(
      t.getBottomLeft(key).dy,
      lessThanOrEqualTo(t.getTopLeft(find.text(title(thisMonth))).dy),
    );
  });

  testWidgets('a day offers Add to this day, starting the flows on it', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const CalendarAllMonthsScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    final day = DateTime(now.year, now.month, now.day);
    await t.tap(find.text('${day.day}').first);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Add to this day'));
    await t.pumpAndSettle();
    expect(find.text('Add to ${MyDateFormat.toDate(day)}'), findsOneWidget);
    await t.tap(find.text('Add a reminder'));
    await t.pumpAndSettle();
    expect(find.text(MyDateFormat.toDate(day)), findsOneWidget); // the reminder's date row
  });
}
