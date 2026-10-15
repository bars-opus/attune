import 'package:attune/core/widgets/card_inkwell.dart';
import 'dart:async';

import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline;
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy_sync_test.dart' show FakeBusySource;
import 'together_calendar_mirror_test.dart' show FakeMirrorCalendar;
import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_widget_sync_test.dart' show FakeWidgetStore;
import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _row(
  String id,
  String date, {
  String kind = 'event',
  String? startsAt,
  String title = '',
}) => {
  'item_kind': kind,
  'item_id': id,
  'item_date': date,
  'starts_at': startsAt,
  'ends_at': null,
  'all_day': startsAt == null,
  'tz': startsAt == null ? null : 'UTC',
  'title': title.isEmpty ? id : title,
  'participant_ids': ['ama', 'kofi'],
  'owner_id': null,
  'created_by': 'ama',
  'visibility': 'shared',
  'status': 'confirmed',
  'source_ref': {'kind': 'event'},
};

Future<FakeTogetherGateway> _pump(
  WidgetTester t, {
  List<Map<String, dynamic>> upcoming = const [],
  List<Map<String, dynamic>> past = const [],
  String? relationshipId = 'r1',
  bool failFirst = false,
  List<Map<String, dynamic>> needs = const [],
  List<Map<String, dynamic>> rituals = const [],
  List<Map<String, dynamic>> prompts = const [],
  List<Map<String, dynamic>> onThisDay = const [],
  List<Map<String, dynamic>> windows = const [],
  List<Map<String, dynamic>> strips = const [],
  FakeLiveStore? live,
  FakeMirrorCalendar? mirror,
  bool embedded = false,
  String? coupleName,
}) async {
  // Never the real lock-screen channel or phone calendar in tests.
  TogetherLiveActivity.store = live ?? FakeLiveStore();
  TogetherMirror.calendar = mirror ?? FakeMirrorCalendar();
  var failing = failFirst;
  final g = FakeTogetherGateway({
    'list_together_items': (p) {
      if (failing) throw Exception('offline');
      return p['p_start'] == '2026-11-02' ? upcoming : past;
    },
    'list_together_needs_you': (_) => needs,
    'list_together_rituals': (_) => rituals,
    'list_together_memory_prompts': (_) => prompts,
    'list_together_on_this_day': (_) => onThisDay,
    'dismiss_memory_prompt': (_) => null,
    'list_together_moments': (_) => const [],
    'list_together_free_windows': (_) => windows,
    'list_together_busy_strips': (_) => strips,
    'get_together_overlay': (_) => {'level': 'free_windows'},
    'replace_my_busy_blocks': (_) => 0,
    'set_planning_timezone': (_) => {'timezone': 'UTC'},
  });
  _stopFailing = () => failing = false;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherClockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9)),
        togetherMeProvider.overrideWithValue('ama'),
        deviceBusySourceProvider.overrideWithValue(
          FakeBusySource(access: false),
        ),
        togetherPartnerIdProvider.overrideWith((ref) async => 'kofi'),
        togetherDeviceTimezoneProvider.overrideWith((ref) async => 'UTC'),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        coupleNameProvider.overrideWith((ref, id) async => coupleName),
        familyMembersListProvider.overrideWith((ref) async => const []),
        timeline.currentRelationshipIdProvider.overrideWith(
          (ref) async => relationshipId,
        ),
        timeline.togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        planningChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        remindersListProvider.overrideWith(_Reminders.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(home: TogetherScreen(embedded: embedded)),
      ),
    ),
  );
  await t.pumpAndSettle();
  return g;
}

void Function() _stopFailing = () {};

class _Reminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => [
    ReminderModel(
      id: 'rem-1',
      relationshipId: 'r1',
      createdBy: 'ama',
      reminderType: 'birthday',
      title: "Mum's birthday",
      remindAt: DateTime(2020, 11, 6),
      recurrence: 'yearly',
      sent: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
}

void main() {
  for (final embedded in [false, true])
    testWidgets(
      'the header above the tabs: Together, a welcome line, settings and family'
      '${embedded ? ' (Planning\'s Calendar tab)' : ' (empty app bar)'}',
      (t) async {
        await _pump(t, embedded: embedded);
        expect(find.text('Together'), findsOneWidget);
        expect(togetherTagline, 'Your plans, rituals and moments, side by side. A journey through time.');
        expect(find.text(togetherTagline), findsOneWidget);
        final settings = find.byTooltip('Together settings');
        final family = find.byTooltip('Family');
        expect(settings, findsOneWidget);
        expect(family, findsOneWidget);
        // Side by side, settings at the far end, both above the Agenda/Month tabs.
        expect(t.getCenter(settings).dy, closeTo(t.getCenter(family).dy, 1));
        expect(t.getCenter(family).dx, lessThan(t.getCenter(settings).dx));
        // Room between the words and the icons.
        expect(
          t.getTopLeft(family).dx - t.getTopRight(find.text(togetherTagline)).dx,
          greaterThanOrEqualTo(16),
        );
        expect(t.getBottomLeft(settings).dy, lessThanOrEqualTo(t.getTopLeft(find.text('Agenda')).dy));
        // Nothing left in the app bar.
        expect(find.descendant(of: find.byType(AppBar), matching: find.text('Together')), findsNothing);
        expect(find.descendant(of: find.byType(AppBar), matching: family), findsNothing);
      },
    );

  testWidgets('an empty section\'s card still spans the full width', (t) async {
    await _pump(t, upcoming: [_row('lisbon', '2026-11-20', title: 'Lisbon')]);
    final empty = find.ancestor(of: find.text('Nothing planned today.'), matching: find.byType(CardInkWell));
    final full = find.ancestor(of: find.text('Lisbon'), matching: find.byType(CardInkWell));
    expect(t.getSize(empty).width, t.getSize(full).width);
  });

  testWidgets('Family opens as a sheet over Together, not a new screen', (t) async {
    await _pump(t);
    await t.tap(find.byTooltip('Family'));
    await t.pumpAndSettle();
    expect(find.text('Add family member'), findsOneWidget);
    expect(find.byType(TogetherScreen), findsOneWidget); // still underneath
  });

  testWidgets('sections: today, this week, coming up, our story', (t) async {
    await _pump(
      t,
      upcoming: [
        _row('rent', '2026-11-02', title: 'Rent'),
        _row('gym', '2026-11-04', title: 'Gym'),
        _row('lisbon', '2026-11-20', title: 'Lisbon'),
      ],
      past: [_row('beach', '2026-10-20', kind: 'moment', title: 'Beach day')],
    );
    expect(find.text('Together'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Beach day'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.textContaining('In 18 days'), findsOneWidget);
    expect(find.text('Our story'), findsOneWidget);
  });

  testWidgets('an empty today says so, quietly', (t) async {
    await _pump(t, upcoming: [_row('gym', '2026-11-04', title: 'Gym')]);
    expect(find.text('Nothing planned today.'), findsOneWidget);
  });

  testWidgets('a new couple sees three ways to start', (t) async {
    await _pump(t);
    expect(find.text('Your life together starts here'), findsOneWidget);
    expect(find.text('Add your anniversary'), findsOneWidget);
    expect(find.text('Add a birthday'), findsOneWidget);
    expect(find.text('Set up a ritual'), findsOneWidget);
  });

  testWidgets('tapping an event opens its editor', (t) async {
    await _pump(t, upcoming: [_row('rent', '2026-11-02', title: 'Rent')]);
    await t.tap(find.text('Rent'));
    await t.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
  });

  testWidgets('this week: dividers run between every row, across days', (
    t,
  ) async {
    await _pump(
      t,
      upcoming: [
        _row('a', '2026-11-03', title: 'A'),
        _row('b', '2026-11-04', title: 'B'),
        _row('c', '2026-11-04', title: 'C', startsAt: '2026-11-04T10:00:00Z'),
      ],
    );
    final rows =
        t
            .widgetList<InfoRowWidget>(find.byType(InfoRowWidget))
            .where((w) => ['A', 'B', 'C'].contains(w.title))
            .map((w) => w.showDivider)
            .toList();
    expect(rows, [true, true, false]);
  });

  testWidgets('a failed load offers Try again, and trying again refetches', (
    t,
  ) async {
    await _pump(
      t,
      upcoming: [_row('rent', '2026-11-02', title: 'Rent')],
      failFirst: true,
    );
    expect(find.text('Try again'), findsOneWidget);
    _stopFailing();
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('no active relationship says so instead of loading forever', (
    t,
  ) async {
    await _pump(t, relationshipId: null);
    expect(find.text('No active relationship found'), findsOneWidget);
  });

  testWidgets('tapping a reminder opens it, even on the first tap', (t) async {
    final row = _row(
      'rem-1',
      '2026-11-02',
      kind: 'reminder',
      title: "Mum's birthday",
    );
    row['source_ref'] = {'reminder_type': 'birthday'};
    await _pump(t, upcoming: [row]);
    await t.tap(find.text("Mum's birthday"));
    await t.pumpAndSettle();
    expect(find.text('Edit reminder'), findsOneWidget);
  });
  testWidgets('needs you sits on top and opens the right sheet', (t) async {
    await _pump(
      t,
      upcoming: [_row('rent', '2026-11-02', title: 'Rent')],
      needs: [
        {
          'need_kind': 'proposal',
          'item_id': 'e1',
          'title': 'Dinner at Buka',
          'due_date': null,
          'created_by': 'kofi',
          'detail': {
            'all_day': true,
            'proposed_to': 'ama',
            'expires_at': '2026-11-09T10:00:00+00:00',
            'options': [
              {
                'id': 'o1',
                'position': 1,
                'start_date': '2026-11-06',
                'end_date': null,
                'starts_at': null,
                'ends_at': null,
              },
            ],
          },
        },
      ],
    );
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.tap(find.text('Dinner at Buka'));
    await t.pumpAndSettle();
    expect(find.text('Kofi suggested'), findsOneWidget);
  });

  testWidgets('needs you shows three and a More row, never a count of misses', (
    t,
  ) async {
    Map<String, dynamic> todo(int i) => {
      'need_kind': 'unowned_todo',
      'item_id': 't$i',
      'title': 'Task $i',
      'due_date': '2026-11-0${i + 2}',
      'created_by': null,
      'detail': {'entry_id': 'p1'},
    };
    await _pump(t, needs: [for (var i = 1; i <= 5; i++) todo(i)]);
    expect(find.text('Task 1'), findsOneWidget);
    expect(find.text('Task 3'), findsOneWidget);
    expect(find.text('Task 4'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('with nothing waiting, there is no Needs you section', (t) async {
    await _pump(t, upcoming: [_row('rent', '2026-11-02', title: 'Rent')]);
    expect(find.text('Needs you'), findsNothing);
  });
  testWidgets("my partner's big day shows a care card in Today", (t) async {
    final row = _row(
      'b1',
      '2026-11-02',
      title: 'Interview',
      startsAt: '2026-11-02T23:00:00Z',
    );
    row['participant_ids'] = ['kofi'];
    row['created_by'] = 'kofi';
    row['source_ref'] = {'kind': 'big_day'};
    await _pump(t, upcoming: [row]);
    expect(find.text("Kofi's big day: Interview"), findsOneWidget);
    expect(find.text('Send a word of luck'), findsOneWidget);
  });

  testWidgets('opening Together reports my time zone, so 8am means my 8am', (
    t,
  ) async {
    final g = await _pump(
      t,
      upcoming: [_row('rent', '2026-11-02', title: 'Rent')],
    );
    final call = g.calls.where((c) => c.$1 == 'set_planning_timezone');
    expect(call, isNotEmpty);
    expect(call.first.$2, {'p_relationship_id': 'r1', 'p_timezone': 'UTC'});
  });
  testWidgets(
    'rituals sit on the Agenda with their next time, and one can be added',
    (t) async {
      await _pump(
        t,
        upcoming: [_row('rent', '2026-11-02', title: 'Rent')],
        rituals: [
          {
            'ritual_id': 'rit-1',
            'template': 'date_night',
            'title': 'Date night',
            'cadence': 'weekly',
            'weekday': 5,
            'local_time': '19:00',
            'duration_min': 120,
            'tz': 'UTC',
            'status': 'active',
            'created_by': 'ama',
            'proposed_to': null,
            'next_event_id': 'e9',
            'next_starts_at': '2026-11-06T19:00:00+00:00',
          },
        ],
      );
      await t.scrollUntilVisible(
        find.text('Add a ritual'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Rituals'), findsOneWidget);
      expect(find.text('Date night'), findsOneWidget);
      await t.tap(find.text('Add a ritual'));
      await t.pumpAndSettle();
      expect(find.text('A ritual for couples'), findsOneWidget); // no name chosen yet
      // A divider sits right under the sheet's title.
      final title = t.getBottomLeft(find.text('A ritual for couples')).dy;
      final dividers = t.widgetList(find.byType(AppDivider)).map((w) => t.getTopLeft(find.byWidget(w)).dy);
      expect(dividers.any((y) => y >= title && y - title < 40), isTrue);
    },
  );

  testWidgets('the ritual sheet is for the couple, by the name they chose', (t) async {
    await _pump(
        t,
        coupleName: 'The Harolds',
        upcoming: [_row('rent', '2026-11-02', title: 'Rent')],
        rituals: [
          {
            'ritual_id': 'rit-1',
            'template': 'date_night',
            'title': 'Date night',
            'cadence': 'weekly',
            'weekday': 5,
            'local_time': '19:00',
            'duration_min': 120,
            'tz': 'UTC',
            'status': 'active',
            'created_by': 'ama',
            'proposed_to': null,
            'next_event_id': 'e9',
            'next_starts_at': '2026-11-06T19:00:00+00:00',
          },
        ],
      );
    await t.scrollUntilVisible(find.text('Add a ritual'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Add a ritual'));
    await t.pumpAndSettle();
    expect(find.text('A ritual for The Harolds'), findsOneWidget);
  });

  testWidgets('my unanswered ritual suggestion opens to withdraw it', (
    t,
  ) async {
    await _pump(
      t,
      upcoming: [_row('rent', '2026-11-02', title: 'Rent')],
      rituals: [
        {
          'ritual_id': 'rit-5',
          'template': 'date_night',
          'title': 'Date night',
          'cadence': 'weekly',
          'weekday': 5,
          'local_time': '19:00',
          'duration_min': 120,
          'tz': 'UTC',
          'status': 'proposed',
          'created_by': 'ama',
          'proposed_to': 'kofi',
          'next_event_id': null,
          'next_starts_at': null,
        },
      ],
    );
    await t.scrollUntilVisible(
      find.text('Date night'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Date night'));
    await t.pumpAndSettle();
    expect(find.text('Withdraw'), findsOneWidget);
  });

  testWidgets('a lived event asks for one line in Today; Not now hides it', (
    t,
  ) async {
    final g = await _pump(
      t,
      prompts: [
        {
          'event_id': 'e1',
          'title': 'Dinner at Buka',
          'event_day': '2026-11-01',
          'ended_at': '2026-11-01T20:00:00+00:00',
          'ritual_id': null,
        },
      ],
    );
    expect(find.text('Add a line about yesterday?'), findsOneWidget);
    // Narrow phones: the question wraps rather than being cut to "Add…".
    expect(
      t.widget<Text>(find.text('Add a line about yesterday?')).maxLines,
      2,
    );
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(g.calls.last.$1, 'dismiss_memory_prompt');
    expect(find.text('Add a line about yesterday?'), findsNothing);
  });

  testWidgets('On this day opens Our story, without a count', (t) async {
    await _pump(
      t,
      onThisDay: [
        {
          'item_kind': 'moment',
          'item_id': 'm1',
          'item_date': '2025-11-02',
          'title': 'First date',
          'note': null,
          'event_type': 'first',
          'years_ago': 1,
        },
      ],
    );
    await t.scrollUntilVisible(
      find.text('First date'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Our story'), findsOneWidget);
    expect(find.text('On this day - 1 year ago'), findsOneWidget);
  });

  testWidgets('All memories opens the archive', (t) async {
    t.view.physicalSize = const Size(1170, 4200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await _pump(
      t,
      past: [_row('m1', '2026-10-30', kind: 'moment', title: 'Beach day')],
    );
    await t.scrollUntilVisible(
      find.text('All memories'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('All memories'));
    await t.pumpAndSettle();
    expect(find.text('Your relationship story starts here.'), findsOneWidget);
  });

  testWidgets("today's free window shows both clocks and opens a suggestion", (
    t,
  ) async {
    await _pump(
      t,
      windows: [
        {
          'starts_at': DateTime(2026, 11, 2, 19).toUtc().toIso8601String(),
          'ends_at': DateTime(2026, 11, 2, 22).toUtc().toIso8601String(),
          'partner_from': '14:00',
          'partner_to': '17:00',
          'partner_differs': true,
        },
        {
          'starts_at': DateTime(2026, 11, 4, 18).toUtc().toIso8601String(),
          'ends_at': DateTime(2026, 11, 4, 21).toUtc().toIso8601String(),
          'partner_from': '13:00',
          'partner_to': '16:00',
          'partner_differs': true,
        },
      ],
    );
    expect(find.textContaining('Both free'), findsWidgets);
    expect(find.text("That's 14:00–17:00 for Kofi"), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Free together'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Free together'), findsOneWidget);
  });

  testWidgets("at the strips level I see when my partner is busy today", (
    t,
  ) async {
    await _pump(
      t,
      strips: [
        {
          'is_mine': false,
          'starts_at': DateTime(2026, 11, 2, 9).toUtc().toIso8601String(),
          'ends_at': DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
        },
      ],
    );
    expect(find.textContaining('Kofi is busy'), findsOneWidget);
  });

  testWidgets('with the home-screen card on, the hub fills it with my plans', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_widget_enabled': true});
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    await _pump(
      t,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(store.saved.where((s) => s != null).last, contains('Dinner'));
  });

  testWidgets('turning the card on fills it straight away', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    await _pump(
      t,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(store.saved, isEmpty);
    final container = ProviderScope.containerOf(
      t.element(find.byType(TogetherScreen)),
    );
    await container.read(togetherWidgetEnabledProvider.notifier).set(true);
    await t.pumpAndSettle();
    expect(store.saved.where((s) => s != null).last, contains('Dinner'));
  });

  testWidgets('with the card off (the default), nothing is written', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    await _pump(
      t,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(store.saved, isEmpty);
  });

  testWidgets(
    'with the lock-screen plan on, the hub shows tonight’s shared plan',
    (t) async {
      SharedPreferences.setMockInitialValues({'together_live_enabled': true});
      final live = FakeLiveStore();
      await _pump(
        t,
        live: live,
        upcoming: [
          _row(
            'd',
            '2026-11-02',
            // 12:00 local; the clock says 09:00, so it's within 4 hours.
            startsAt: DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
            title: 'Lunch',
          ),
        ],
      );
      await t.pumpAndSettle();
      expect(live.shown.last.title, 'Lunch');
    },
  );

  testWidgets('a renamed plan updates the lock-screen plan on the next load', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    final live = FakeLiveStore();
    final rows = [
      _row(
        'd',
        '2026-11-02',
        startsAt: DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
        title: 'Lunch',
      ),
    ];
    await _pump(t, live: live, upcoming: rows);
    await t.pumpAndSettle();
    expect(live.shown.last.title, 'Lunch');
    rows[0] = {...rows[0], 'title': 'Lunch at Kozo'};
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    // What a realtime change does: the items refetch, the agenda follows.
    c.invalidate(togetherRangeProvider);
    await t.pumpAndSettle();
    expect(live.shown.last.title, 'Lunch at Kozo');
  });

  testWidgets('with no plan close, the hub ends the lock-screen plan', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    final live = FakeLiveStore();
    await _pump(
      t,
      live: live,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(live.shown, isEmpty);
    expect(live.ends, greaterThan(0));
  });

  testWidgets('turning the lock-screen plan on shows it straight away', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final live = FakeLiveStore();
    await _pump(
      t,
      live: live,
      upcoming: [
        _row(
          'd',
          '2026-11-02',
          startsAt: DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
          title: 'Lunch',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(live.shown, isEmpty);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    await c.read(togetherLiveEnabledProvider.notifier).set(true);
    await t.pumpAndSettle();
    expect(live.shown.last.title, 'Lunch');
  });

  testWidgets('with the calendar copy on, opening Together copies our plans', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    final mirror = FakeMirrorCalendar();
    await _pump(
      t,
      mirror: mirror,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(mirror.entries('Plans').map((e) => e.title), ['Dinner']);
  });

  testWidgets('turning the calendar copy on copies straight away', (t) async {
    SharedPreferences.setMockInitialValues({});
    final mirror = FakeMirrorCalendar();
    await _pump(
      t,
      mirror: mirror,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(mirror.names, isEmpty);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    await c.read(togetherMirrorEnabledProvider.notifier).set(true);
    await t.pumpAndSettle();
    expect(mirror.entries('Plans').map((e) => e.title), ['Dinner']);
  });

  testWidgets('the first visit copies each plan once, into one calendar', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    // A slow phone: the visit's sync is still waiting when the opt-in loads.
    final gate = Completer<void>();
    final mirror = FakeMirrorCalendar(gate: gate);
    await _pump(
      t,
      mirror: mirror,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    gate.complete();
    await t.pumpAndSettle();
    expect(mirror.names, hasLength(1));
    expect(mirror.adds, 1);
  });

  testWidgets(
    'with no relationship any more, nothing of it is left on the phone',
    (t) async {
      SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
      final mirror = FakeMirrorCalendar();
      final id = await mirror.create('Plans');
      (await SharedPreferences.getInstance()).setString(
        'together_mirror_calendar_id',
        id,
      );
      final live = FakeLiveStore();
      await _pump(t, relationshipId: null, mirror: mirror, live: live);
      await t.pumpAndSettle();
      expect(mirror.names, isEmpty);
      expect(live.ends, greaterThan(0));
    },
  );

  testWidgets('a pending share opens the new-event sheet once, then clears', (
    t,
  ) async {
    await _pump(t);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    c.read(pendingShareProvider.notifier).state = PendingShare(
      'Picnic Sun',
      DateTime.now(),
    );
    await t.pumpAndSettle();
    expect(find.text('New event'), findsOneWidget);
    expect(c.read(pendingShareProvider), isNull);
  });

  testWidgets('before Together is reachable a share waits, untouched', (
    t,
  ) async {
    await _pump(t, relationshipId: null);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    c.read(pendingShareProvider.notifier).state = PendingShare(
      'Picnic Sun',
      DateTime.now(),
    );
    await t.pumpAndSettle();
    expect(find.text('New event'), findsNothing);
    expect(c.read(pendingShareProvider)?.text, 'Picnic Sun');
  });

  testWidgets('a stale share is dropped quietly', (t) async {
    await _pump(t);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    c.read(pendingShareProvider.notifier).state = PendingShare(
      'Old',
      DateTime.now().subtract(const Duration(minutes: 11)),
    );
    await t.pumpAndSettle();
    expect(find.text('New event'), findsNothing);
    expect(c.read(pendingShareProvider), isNull);
  });

  testWidgets('a ritual suggestion waits in Needs you', (t) async {
    await _pump(
      t,
      needs: [
        {
          'need_kind': 'ritual_proposal',
          'item_id': 'rit-3',
          'title': 'Weekly call',
          'due_date': null,
          'created_by': 'kofi',
          'detail': {
            'template': 'weekly_call',
            'cadence': 'weekly',
            'weekday': 7,
            'local_time': '19:00',
            'duration_min': 60,
            'tz': 'UTC',
          },
        },
      ],
    );
    expect(find.text('Weekly call'), findsOneWidget);
    await t.tap(find.text('Weekly call'));
    await t.pumpAndSettle();
    expect(
      find.text("We're in"),
      findsOneWidget,
      reason: 'the suggestion sheet is open',
    );
  });
}
