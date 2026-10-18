import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/presentation/widgets/conversations_home_cards.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart' as timeline;
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';

class _Journal extends JournalEntriesNotifier {
  _Journal(this.entries);
  final List<JournalEntry> entries;
  @override
  Future<List<JournalEntry>> build() async => entries;
}

final _edited = DateTime(2026, 10, 13, 9);
final _entry = JournalEntry(
  id: 'j1',
  userId: 'ama',
  content: 'A long walk',
  createdAt: _edited,
  updatedAt: _edited,
  title: 'Sunday thoughts',
);

PlanningRecentPage _recent(List<String> titles, DateTime at) => PlanningRecentPage(
  entries: [
    for (final t in titles)
      PlanningRecentEntry(
        entry: PlanningEntrySummary(
          id: 'e-$t',
          title: t,
          status: 'active',
          lastActivityAt: at,
          dateStart: null,
          dateEnd: null,
          checklistDone: 0,
          checklistTotal: 0,
        ),
        categoryId: 'c1',
        categoryName: 'Trips',
        categoryIcon: 'plane',
        categoryColor: 'teal',
      ),
  ],
  nextCursorAt: null,
  nextCursorId: null,
);

TogetherItem _item(String id, String title, DateTime day, {TogetherItemKind kind = TogetherItemKind.event}) =>
    TogetherItem(
      kind: kind,
      id: id,
      date: DateTime(day.year, day.month, day.day),
      allDay: true,
      title: title,
      participantIds: const ['ama', 'kofi'],
    );

PlanningCategory _category({bool hasNew = false, bool hidden = false}) =>
    PlanningCategory(
      id: 'c-$hasNew-$hidden',
      seedKey: null,
      name: 'Trips',
      icon: 'flight',
      color: 'blue',
      sortKey: 'a',
      hidden: hidden,
      templateEntryId: null,
      entryCount: 1,
      hasNew: hasNew,
    );

Future<void> _pump(
  WidgetTester t,
  Widget child, {
  String? relationshipId = 'rel-1',
  List<JournalEntry> journal = const [],
  PlanningRecentPage? recent,
  List<PlanningCategory> home = const [],
  void Function()? onHomeRead,
  List<TogetherItem> together = const [],
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        timeline.currentRelationshipIdProvider.overrideWith((ref) async => relationshipId),
        journalEntriesProvider.overrideWith(() => _Journal(journal)),
        planningRecentProvider.overrideWith(
          (ref, id) async => recent ?? _recent(const [], DateTime.now()),
        ),
        planningHomeProvider.overrideWith((ref, id) async {
          onHomeRead?.call();
          return home;
        }),
        coupleNameProvider.overrideWith((ref, id) async => 'The Harolds'),
        togetherRangeProvider.overrideWith((ref, a) async => together),
        togetherMeProvider.overrideWithValue('ama'),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  group('the journals card', () {
    testWidgets('reflection on top, a divider, then the couples journal; each shows its latest', (t) async {
      final now = DateTime.now();
      await _pump(t, const JournalsCard(), journal: [_entry], recent: _recent(['Lisbon'], now));
      final reflection = find.widgetWithText(InfoRowWidget, 'Sunday thoughts');
      final couples = find.widgetWithText(InfoRowWidget, 'Lisbon');
      expect(reflection, findsOneWidget);
      expect(couples, findsOneWidget);
      expect(t.getTopLeft(reflection).dy, lessThan(t.getTopLeft(couples).dy));
      expect(t.widget<InfoRowWidget>(reflection).showDivider, isTrue);
      expect(find.text(MyDateFormat.join(['Reflection journal', MyDateFormat.toDate(_edited)])), findsOneWidget);
      expect(
        find.text(MyDateFormat.join(["The Harolds' journal", 'Trips', planningRowDate(now, DateTime.now())])),
        findsOneWidget,
      );
    });

    testWidgets('nothing planned yet: an invitation, under the journal\'s name', (t) async {
      await _pump(t, const JournalsCard(), journal: [_entry]);
      expect(find.text('Start planning together'), findsOneWidget);
      expect(find.text("The Harolds' journal"), findsOneWidget);
    });

    // The same dot as Planning's category rows: something new from the
    // partner in a plan this person hasn't opened since.
    testWidgets('new from the partner: the couples journal row carries the dot', (t) async {
      final now = DateTime.now();
      await _pump(t, const JournalsCard(),
          journal: [_entry], recent: _recent(['Lisbon'], now), home: [_category(), _category(hasNew: true)]);
      expect(
        find.descendant(of: find.widgetWithText(InfoRowWidget, 'Lisbon'), matching: find.byType(PlanningNewDot)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.widgetWithText(InfoRowWidget, 'Lisbon'), matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    });

    testWidgets('nothing new: no dot, just the arrow', (t) async {
      final now = DateTime.now();
      await _pump(t, const JournalsCard(), journal: [_entry], recent: _recent(['Lisbon'], now), home: [_category()]);
      expect(find.byType(PlanningNewDot), findsNothing);
      expect(
        find.descendant(of: find.widgetWithText(InfoRowWidget, 'Lisbon'), matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
    });

    // The home RPC seeds the starter categories; with no plan yet, nothing
    // can be new, so Conversations leaves that to Planning's first visit.
    testWidgets('no plans yet: Planning\'s categories are not asked for', (t) async {
      var reads = 0;
      await _pump(t, const JournalsCard(), journal: [_entry], onHomeRead: () => reads++);
      expect(find.text('Start planning together'), findsOneWidget);
      expect(reads, 0);
    });

    testWidgets('a hidden category never lights the dot', (t) async {
      final now = DateTime.now();
      await _pump(t, const JournalsCard(),
          journal: [_entry], recent: _recent(['Lisbon'], now), home: [_category(hasNew: true, hidden: true)]);
      expect(find.byType(PlanningNewDot), findsNothing);
    });

    testWidgets('without a couple, just the reflection journal', (t) async {
      await _pump(t, const JournalsCard(), relationshipId: null, journal: [_entry]);
      expect(find.text('Sunday thoughts'), findsOneWidget);
      expect(find.textContaining('journal - Trips'), findsNothing);
      expect(find.text('Start planning together'), findsNothing);
      expect(t.widget<InfoRowWidget>(find.widgetWithText(InfoRowWidget, 'Sunday thoughts')).showDivider, isFalse);
    });
  });

  group('the together card', () {
    DateTime inDays(int n) {
      final today = DateTime.now();
      return DateTime(today.year, today.month, today.day + n);
    }

    testWidgets('the big number, with "days" over "together" small at its right; Calendar on the right', (t) async {
      await _pump(t, const TogetherCard());
      final days = daysTogether(DateTime.now());
      final number = find.text('$days');
      final daysWord = find.text('days');
      final together = find.text('together');
      expect(number, findsOneWidget);
      // Stacked, tight, their left edges lined up, just right of the number.
      expect(t.getTopLeft(together).dy, greaterThan(t.getTopLeft(daysWord).dy));
      expect(t.getTopLeft(together).dy - t.getBottomLeft(daysWord).dy, lessThanOrEqualTo(2));
      expect(t.getTopLeft(daysWord).dx, t.getTopLeft(together).dx);
      expect(t.getTopLeft(daysWord).dx - t.getTopRight(number).dx, inInclusiveRange(0, 8));
      // Smaller than the number.
      expect(t.getSize(daysWord).height * 1.5, lessThan(t.getSize(number).height + t.getSize(daysWord).height));
      expect(t.widget<Text>(daysWord).style!.fontSize!, lessThan(t.widget<Text>(number).style!.fontSize!));
      final calendar = find.widgetWithText(TextButton, 'Calendar');
      expect(calendar, findsOneWidget);
      expect(t.getCenter(calendar).dx, greaterThan(t.getCenter(together).dx));
    });

    testWidgets('only the dates to be reminded of, at most three, soonest first', (t) async {
      await _pump(
        t,
        const TogetherCard(),
        together: [
          _item('ev', 'Dinner', inDays(0)),
          _item('plan', 'Pack for Lisbon', inDays(1), kind: TogetherItemKind.planningItem),
          _item('date', 'Lisbon', inDays(2), kind: TogetherItemKind.planningDate),
          _item('m', 'A memory', inDays(0), kind: TogetherItemKind.moment),
          _item('r1', 'Our anniversary', inDays(3), kind: TogetherItemKind.reminder),
          _item('r2', "Mum's birthday", inDays(10), kind: TogetherItemKind.reminder),
          _item('r3', "Kofi's birthday", inDays(20), kind: TogetherItemKind.reminder),
          _item('r4', 'Far off', inDays(40), kind: TogetherItemKind.reminder),
        ],
      );
      expect(find.byType(TogetherItemRow), findsNWidgets(3));
      for (final shown in ['Our anniversary', "Mum's birthday", "Kofi's birthday"]) {
        expect(find.text(shown), findsOneWidget, reason: shown);
      }
      for (final hidden in ['Dinner', 'Pack for Lisbon', 'Lisbon', 'A memory', 'Far off']) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      expect(find.textContaining('In 3 days'), findsOneWidget);
    });

    testWidgets('nothing to be reminded of: just the days together', (t) async {
      await _pump(t, const TogetherCard(), together: [_item('ev', 'Dinner', inDays(1))]);
      expect(find.text('together'), findsOneWidget);
      expect(find.byType(TogetherItemRow), findsNothing);
    });

    test('the days count up from the start date, one a day', () {
      final since = togetherSincePlaceholder;
      expect(daysTogether(DateTime(since.year, since.month, since.day)), 0);
      expect(daysTogether(DateTime(since.year, since.month, since.day + 1, 23)), 1);
      expect(daysTogether(DateTime(since.year, since.month, since.day + 400)), 400);
    });

    testWidgets('without a couple, no together card', (t) async {
      await _pump(t, const TogetherCard(), relationshipId: null);
      expect(find.text('together'), findsNothing);
    });
  });

  group('tapping the together card', () {
    Future<void> pumpRouted(WidgetTester t, List<TogetherItem> together) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: SingleChildScrollView(child: TogetherCard()))),
          GoRoute(path: '/together', name: 'together', builder: (_, __) => const Scaffold(body: Text('Together screen'))),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            timeline.currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
            coupleNameProvider.overrideWith((ref, id) async => 'The Harolds'),
            togetherRangeProvider.overrideWith((ref, a) async => together),
            togetherMeProvider.overrideWithValue('ama'),
            quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
            remindersListProvider.overrideWith(_NoReminders.new),
          ],
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('anywhere but an event opens the calendar', (t) async {
      await pumpRouted(t, const []);
      await t.tap(find.text('together'));
      await t.pumpAndSettle();
      expect(find.text('Together screen'), findsOneWidget);
    });

    testWidgets('an event row opens the event, not the calendar', (t) async {
      final today = DateTime.now();
      await pumpRouted(t, [
        _item('r1', 'Our anniversary', DateTime(today.year, today.month, today.day + 3), kind: TogetherItemKind.reminder),
      ]);
      await t.tap(find.text('Our anniversary'));
      await t.pumpAndSettle();
      expect(find.text('Together screen'), findsNothing);
    });
  });
}

class _NoReminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}
