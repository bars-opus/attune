import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/calendar_exporter.dart';
import 'package:attune/features/together/data/together_ai_repository.dart';
import 'package:attune/features/together/domain/together_ai.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/calendar_export.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/couple_event_sheet.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_ai_test.dart' show FakeAiGateway;
import 'together_repository_test.dart' show FakeTogetherGateway;

class _FakeExporter implements CalendarExporter {
  final added = <CalendarExport>[];
  @override
  Future<bool> add(CalendarExport e) async {
    added.add(e);
    return true;
  }
}

Future<FakeTogetherGateway> _open(
  WidgetTester t, {
  TogetherItem? item,
  bool partnerFails = false,
  int partnerFailures = 0,
  Duration partnerDelay = Duration.zero,
  DateTime? now,
  CalendarExporter? exporter,
  ({DateTime start, DateTime end})? window,
  TogetherAiGateway? ai,
  String? text,
  DateTime? day,
}) async {
  // A phone-sized screen, so the sheet's lower rows are on screen.
  // Tall enough that the whole editor fits without scrolling.
  t.view.physicalSize = const Size(1170, 4200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  var failuresLeft = partnerFailures;
  final g = FakeTogetherGateway({
    'create_couple_event': (_) => 'ev-1',
    'update_couple_event': (_) => null,
    'delete_couple_event': (_) => null,
    'leave_couple_event': (_) => null,
    'list_together_items': (_) => const [],
    'propose_couple_event': (_) => 'p1',
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherMeProvider.overrideWithValue('ama'),
        if (now != null) togetherClockProvider.overrideWithValue(() => now),
        if (exporter != null)
          calendarExporterProvider.overrideWithValue(exporter),
        if (ai != null) ...[
          togetherAiRepositoryProvider.overrideWithValue(
            TogetherAiRepository(ai),
          ),
          togetherAiAvailableProvider.overrideWith((ref, id) async => true),
        ],
        togetherPartnerIdProvider.overrideWith((ref) async {
          await Future<void>.delayed(partnerDelay);
          if (partnerFails) throw Exception('offline');
          if (failuresLeft > 0) {
            failuresLeft--;
            throw Exception('offline');
          }
          return 'kofi';
        }),
        togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        planningChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        togetherDeviceTimezoneProvider.overrideWith(
          (ref) async => 'Africa/Accra',
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        coupleNameProvider.overrideWith((ref, id) async => 'The Harolds'),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (context) => TextButton(
                        onPressed:
                            () => showCoupleEventSheet(
                              context,
                              relationshipId: 'r1',
                              item: item,
                              proposeWindow: window,
                              initialText: text,
                              day: day,
                            ),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return g;
}

TogetherItem _item({
  List<String> who = const ['ama', 'kofi'],
  String createdBy = 'ama',
  TogetherVisibility visibility = TogetherVisibility.shared,
  String kind = 'event',
}) => TogetherItem.fromRow({
  'item_kind': 'event',
  'item_id': 'e1',
  'item_date': '2026-11-06',
  'starts_at': '2026-11-06T19:00:00+00:00',
  'ends_at': null,
  'all_day': false,
  'tz': 'Africa/Accra',
  'title': 'Dinner',
  'participant_ids': who,
  'owner_id': null,
  'created_by': createdBy,
  'visibility': visibility.wire,
  'status': 'confirmed',
  'source_ref': {'kind': kind, 'event_starts_at': '2026-11-06T19:00:00+00:00'},
});

/// One Friday of a weekly series (series start 16 Oct, this one 30 Oct).
TogetherItem _occurrence({bool allDay = false, String? until}) => TogetherItem.fromRow({
  'item_kind': 'event',
  'item_id': 'e1',
  'item_date': '2026-10-30',
  'starts_at': allDay ? null : '2026-10-30T19:00:00+00:00',
  'ends_at': allDay ? null : '2026-10-30T21:00:00+00:00',
  'all_day': allDay,
  'tz': allDay ? null : 'Europe/London',
  'title': 'Date night',
  'participant_ids': const ['ama', 'kofi'],
  'owner_id': null,
  'created_by': 'ama',
  'visibility': 'shared',
  'status': 'confirmed',
  'source_ref': {
    'kind': 'event',
    'rrule': 'FREQ=WEEKLY;BYDAY=FR',
    if (until != null) 'recurrence_until': until,
    if (allDay) 'start_date': '2026-10-16',
    if (!allDay) 'event_starts_at': '2026-10-16T18:00:00+00:00',
    if (!allDay) 'event_ends_at': '2026-10-16T20:00:00+00:00',
  },
});

String _when(DateTime d) =>
    MyDateFormat.join([MyDateFormat.toDate(d), MyDateFormat.toTime(d)]);

Future<void> _tapDelete(WidgetTester t) async {
  await t.scrollUntilVisible(
    find.text('Delete event'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(find.text('Delete event'));
  await t.pumpAndSettle();
  await t.tap(find.text('Delete event'));
  await t.pumpAndSettle();
}

void main() {
  group('one occurrence of a repeating event', () {
    final thisOne = DateTime.parse('2026-10-30T19:00:00Z').toLocal();
    final seriesStart = DateTime.parse('2026-10-16T18:00:00Z').toLocal();

    testWidgets('opens on its own date, not the series start', (t) async {
      await _open(t, item: _occurrence());
      expect(find.text(_when(thisOne)), findsOneWidget);
      expect(find.text(_when(seriesStart)), findsNothing);
    });

    testWidgets('an all-day one opens on its own day', (t) async {
      await _open(t, item: _occurrence(allDay: true));
      expect(
        find.text(MyDateFormat.toDate(DateTime(2026, 10, 30))),
        findsOneWidget,
      );
      expect(
        find.text(MyDateFormat.toDate(DateTime(2026, 10, 16))),
        findsNothing,
      );
    });

    testWidgets('Save asks; This one only detaches that date with no repeat', (
      t,
    ) async {
      final g = await _open(t, item: _occurrence());
      g.handlers['detach_couple_event_occurrence'] = (_) => 'ev-2';
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Change this one or all repeats?'), findsOneWidget);
      await t.tap(find.text('This one only'));
      await t.pumpAndSettle();
      final call = g.calls.singleWhere(
        (c) => c.$1 == 'detach_couple_event_occurrence',
      );
      expect(call.$2['p_event_id'], 'e1');
      expect(call.$2['p_on'], '2026-10-30');
      final payload = call.$2['p_event'] as Map;
      expect(payload['rrule'], isNull);
      expect(payload['recurrence_until'], isNull);
      expect(
        DateTime.parse(payload['starts_at'] as String),
        DateTime.utc(2026, 10, 30, 19),
      );
      expect(
        DateTime.parse(payload['ends_at'] as String),
        DateTime.utc(2026, 10, 30, 21),
      );
      expect(g.calls.where((c) => c.$1 == 'update_couple_event'), isEmpty);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets(
      'All repeats with the time untouched keeps the series where it was',
      (t) async {
        final g = await _open(t, item: _occurrence());
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        await t.tap(find.text('All repeats'));
        await t.pumpAndSettle();
        final call = g.calls.singleWhere((c) => c.$1 == 'update_couple_event');
        final payload = call.$2['p_event'] as Map;
        expect(
          DateTime.parse(payload['starts_at'] as String),
          DateTime.utc(2026, 10, 16, 18),
        );
        expect(
          DateTime.parse(payload['ends_at'] as String),
          DateTime.utc(2026, 10, 16, 20),
        );
        expect(payload['rrule'], 'FREQ=WEEKLY;BYDAY=FR');
        expect(
          g.calls.where((c) => c.$1 == 'detach_couple_event_occurrence'),
          isEmpty,
        );
      },
    );

    testWidgets('All repeats, all-day, keeps the series start date', (t) async {
      final g = await _open(t, item: _occurrence(allDay: true));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('All repeats'));
      await t.pumpAndSettle();
      final payload =
          g.calls
                  .singleWhere((c) => c.$1 == 'update_couple_event')
                  .$2['p_event']
              as Map;
      expect(payload['start_date'], '2026-10-16');
    });

    testWidgets(
      'All repeats after moving this one an hour moves the whole series an hour',
      (t) async {
        final g = await _open(t, item: _occurrence());
        // The date-and-time wheel needs more width than a phone sheet gives.
        t.view.physicalSize = const Size(2400, 4200);
        await t.pumpAndSettle();
        await t.tap(find.text(_when(thisOne)));
        await t.pumpAndSettle();
        final picker = t.widget<CupertinoDatePicker>(
          find.byType(CupertinoDatePicker),
        );
        picker.onDateTimeChanged(thisOne.add(const Duration(hours: 1)));
        Navigator.of(t.element(find.byType(CupertinoDatePicker))).pop();
        await t.pumpAndSettle();
        expect(
          find.text(_when(thisOne.add(const Duration(hours: 1)))),
          findsOneWidget,
        );
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        await t.tap(find.text('All repeats'));
        await t.pumpAndSettle();
        final payload =
            g.calls
                    .singleWhere((c) => c.$1 == 'update_couple_event')
                    .$2['p_event']
                as Map;
        expect(
          DateTime.parse(payload['starts_at'] as String),
          DateTime.utc(2026, 10, 16, 19),
        );
        expect(
          DateTime.parse(payload['ends_at'] as String),
          DateTime.utc(2026, 10, 16, 21),
          reason: 'the length is kept',
        );
      },
    );

    Future<void> moveThisOne(WidgetTester t, Duration by) async {
      t.view.physicalSize = const Size(2400, 4200);
      await t.pumpAndSettle();
      await t.tap(find.text(_when(thisOne)));
      await t.pumpAndSettle();
      t.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(thisOne.add(by));
      Navigator.of(t.element(find.byType(CupertinoDatePicker))).pop();
      await t.pumpAndSettle();
    }

    testWidgets('All repeats after moving this one to Saturday moves the series to Saturdays', (t) async {
      final g = await _open(t, item: _occurrence());
      await moveThisOne(t, const Duration(days: 1));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('All repeats'));
      await t.pumpAndSettle();
      final payload = g.calls.singleWhere((c) => c.$1 == 'update_couple_event').$2['p_event'] as Map;
      expect(payload['rrule'], 'FREQ=WEEKLY;BYDAY=SA');
      expect(DateTime.parse(payload['starts_at'] as String), DateTime.utc(2026, 10, 17, 18));
    });

    testWidgets('All repeats that would end before it starts says so, sends nothing', (t) async {
      final g = await _open(t, item: _occurrence(until: '2026-11-01'));
      await moveThisOne(t, const Duration(days: 21));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('All repeats'));
      await t.pumpAndSettle();
      expect(g.calls.where((c) => c.$1 == 'update_couple_event'), isEmpty);
      expect(find.text('Repeat until must be after the start'), findsOneWidget);
    });

    testWidgets('This one only can move past the end of the repeats', (t) async {
      final g = await _open(t, item: _occurrence(until: '2026-11-01'));
      g.handlers['detach_couple_event_occurrence'] = (_) => 'ev-2';
      await moveThisOne(t, const Duration(days: 21));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('This one only'));
      await t.pumpAndSettle();
      expect(g.calls.where((c) => c.$1 == 'detach_couple_event_occurrence'), hasLength(1));
    });

    testWidgets('Cancel on the question sends nothing and stays open', (
      t,
    ) async {
      final g = await _open(t, item: _occurrence());
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(g.calls.where((c) => c.$1 != 'list_together_items'), isEmpty);
      expect(find.text('Edit event'), findsOneWidget);
    });

    testWidgets('Delete asks; This one only skips that date', (t) async {
      final g = await _open(t, item: _occurrence());
      g.handlers['skip_couple_event_occurrence'] = (_) => null;
      await _tapDelete(t);
      expect(find.text('Delete this one or all repeats?'), findsOneWidget);
      expect(find.text('Delete every repeat?'), findsNothing);
      await t.tap(find.text('This one only'));
      await t.pumpAndSettle();
      expect(g.calls.last.$1, 'skip_couple_event_occurrence');
      expect(g.calls.last.$2, {'p_event_id': 'e1', 'p_on': '2026-10-30'});
      expect(find.text('Deleted this one.'), findsOneWidget);
    });

    testWidgets('Delete all repeats deletes the series; Cancel does nothing', (
      t,
    ) async {
      final g = await _open(t, item: _occurrence());
      await _tapDelete(t);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(g.calls.where((c) => c.$1 != 'list_together_items'), isEmpty);
      // The header is scrolled out of the list; the row still there says
      // the sheet is still open.
      expect(find.text('Delete event'), findsOneWidget);
      await _tapDelete(t);
      await t.tap(find.text('All repeats'));
      await t.pumpAndSettle();
      expect(g.calls.last.$1, 'delete_couple_event');
      expect(g.calls.last.$2, {'p_event_id': 'e1'});
    });
  });

  testWidgets('who it\'s for names the couple by their chosen name', (t) async {
    await _open(t);
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is SegmentedButton),
        matching: find.text('The Harolds'),
      ),
      findsOneWidget,
    );
    expect(find.text('Both of us'), findsNothing);
  });

  testWidgets(
    'a new event for both of us is created and confirmed behind the sheet',
    (t) async {
      final g = await _open(t);
      expect(find.text('New event'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Dinner at Buka');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final payload = g.calls.single.$2['p_event'] as Map<String, dynamic>;
      expect(payload['title'], 'Dinner at Buka');
      expect(payload['participant_ids'], ['ama', 'kofi']);
      expect(payload['tz'], 'Africa/Accra');
      expect(find.text('New event'), findsNothing);
      expect(find.text('Added.'), findsOneWidget);
    },
  );

  testWidgets(
    'an empty title stays open with a plain message and sends nothing',
    (t) async {
      final g = await _open(t);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(g.calls, isEmpty);
      expect(find.text('Give it a title'), findsOneWidget);
      expect(find.text('New event'), findsOneWidget);
    },
  );

  testWidgets('editing my event saves an update; delete asks first', (t) async {
    final g = await _open(t, item: _item());
    expect(find.text('Edit event'), findsOneWidget);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    // No "this one or all repeats?" for an event that doesn't repeat.
    expect(find.text('Change this one or all repeats?'), findsNothing);
    expect(g.calls.single.$1, 'update_couple_event');
    expect(g.calls.single.$2['p_event_id'], 'e1');

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Delete event'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Delete event'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Delete'));
    await t.pumpAndSettle();
    expect(g.calls.last.$1, 'delete_couple_event');
  });

  testWidgets("my partner's event that includes me can be left", (t) async {
    final g = await _open(t, item: _item(createdBy: 'kofi'));
    await t.scrollUntilVisible(
      find.text('Leave event'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Leave event'));
    await t.pumpAndSettle();
    expect(g.calls.single.$1, 'leave_couple_event');
  });

  testWidgets(
    "a ritual's week is skipped, not deleted or left (it would come back)",
    (t) async {
      final g = await _open(
        t,
        item: _item(createdBy: 'kofi', kind: 'ritual_occurrence'),
      );
      await t.scrollUntilVisible(
        find.text('Skip this week'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Delete event'), findsNothing);
      expect(find.text('Leave event'), findsNothing);
      await t.tap(find.text('Skip this week'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Skip it'));
      await t.pumpAndSettle();
      expect(g.calls.last.$1, 'skip_ritual_occurrence');
      expect(g.calls.last.$2, {'p_event_id': 'e1'});
    },
  );

  testWidgets('after a shared event, I can add a memory of it', (t) async {
    final g = await _open(t, item: _item(), now: DateTime(2026, 11, 8, 9));
    await t.scrollUntilVisible(
      find.text('Add a memory'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Add a memory'));
    await t.pumpAndSettle();
    expect(find.text('A line to remember it by'), findsOneWidget);
    expect(g.calls.where((c) => c.$1 == 'add_event_memory'), isEmpty);
  });

  testWidgets('a saved event can be added to my own calendar', (t) async {
    final exporter = _FakeExporter();
    await _open(t, item: _item(), exporter: exporter);
    await t.scrollUntilVisible(
      find.text('Add to my calendar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // The 200-point steps can stop with the button just past the sheet's
    // edge: bring it fully into view before tapping.
    await t.ensureVisible(find.text('Add to my calendar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add to my calendar'));
    await t.pumpAndSettle();
    expect(exporter.added.single.title, 'Dinner');
  });

  testWidgets("a partner's busy block has no Add to my calendar", (t) async {
    await _open(
      t,
      item: _item(createdBy: 'kofi', visibility: TogetherVisibility.busyOnly),
      exporter: _FakeExporter(),
    );
    expect(find.text('Add to my calendar'), findsNothing);
  });

  testWidgets('a free window opens as a suggestion for that time', (t) async {
    final s = DateTime(2026, 11, 10, 19);
    final g = await _open(
      t,
      window: (start: s, end: s.add(const Duration(hours: 3))),
    );
    await t.enterText(find.byType(TextField).first, 'Dinner');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final call = g.calls.singleWhere((c) => c.$1 == 'propose_couple_event');
    final first = (call.$2['p_options'] as List).first as Map;
    expect(DateTime.parse(first['starts_at'] as String), s.toUtc());
    expect(
      DateTime.parse(first['ends_at'] as String),
      s.add(const Duration(hours: 2)).toUtc(),
    );
  });

  testWidgets('describing it fills the form in; nothing is saved yet', (
    t,
  ) async {
    final g = await _open(
      t,
      ai: FakeAiGateway(
        response: {
          'draft': {
            'title': "Dinner with Kofi's parents",
            'all_day': false,
            'start_local': '2026-11-07T19:00',
            'end_local': null,
            'with_partner': true,
            'location': 'Osu',
            'note': null,
          },
        },
      ),
    );
    await t.enterText(
      find.widgetWithText(TextField, 'e.g. dinner with Kofi Sat 7pm'),
      "dinner with Kofi's parents Sat 7pm at Osu",
    );
    await t.tap(find.text('Fill in'));
    await t.pumpAndSettle();
    expect(find.text("Dinner with Kofi's parents"), findsWidgets);
    await t.scrollUntilVisible(
      find.text('Osu'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Osu'), findsWidgets);
    expect(g.calls.where((c) => c.$1 == 'create_couple_event'), isEmpty);
  });

  for (final (name, error, message) in [
    (
      'a bad read',
      const TogetherAiException('PROVIDER_FAILED'),
      "Couldn't read that",
    ),
    (
      'a used-up budget',
      const TogetherAiException('RATE_LIMITED', retryAfterSeconds: 7200),
      'Try again in 2 hours',
    ),
  ]) {
    testWidgets('$name leaves the form as it was', (t) async {
      await _open(t, ai: FakeAiGateway(error: error));
      await t.enterText(
        find.widgetWithText(TextField, 'e.g. dinner with Kofi Sat 7pm'),
        'x',
      );
      await t.tap(find.text('Fill in'));
      await t.pumpAndSettle();
      expect(find.textContaining(message), findsOneWidget);
      expect(find.widgetWithText(TextField, 'x'), findsOneWidget);
    });
  }

  testWidgets('in a suggestion, the time it read is the time suggested', (
    t,
  ) async {
    final g = await _open(
      t,
      window: (
        start: DateTime(2026, 11, 5, 19),
        end: DateTime(2026, 11, 5, 22),
      ),
      ai: FakeAiGateway(
        response: {
          'draft': {
            'title': 'Dinner',
            'all_day': false,
            'start_local': '2026-11-07T19:00',
            'end_local': '2026-11-07T21:00',
            'with_partner': true,
            'location': null,
            'note': null,
          },
        },
      ),
    );
    await t.enterText(
      find.widgetWithText(TextField, 'e.g. dinner with Kofi Sat 7pm'),
      'dinner Sat 7pm',
    );
    await t.tap(find.text('Fill in'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final call = g.calls.singleWhere((c) => c.$1 == 'propose_couple_event');
    final first = (call.$2['p_options'] as List).first as Map;
    expect(
      DateTime.parse(first['starts_at'] as String),
      DateTime(2026, 11, 7, 19).toUtc(),
    );
  });

  testWidgets('a trip it read keeps its last day', (t) async {
    final g = await _open(
      t,
      ai: FakeAiGateway(
        response: {
          'draft': {
            'title': 'Trip to Cape Coast',
            'all_day': true,
            'start_local': '2026-11-07',
            'end_local': '2026-11-09',
            'with_partner': true,
            'location': null,
            'note': null,
          },
        },
      ),
    );
    await t.enterText(
      find.widgetWithText(TextField, 'e.g. dinner with Kofi Sat 7pm'),
      'trip to Cape Coast Sat to Mon',
    );
    await t.tap(find.text('Fill in'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final call = g.calls.singleWhere((c) => c.$1 == 'create_couple_event');
    expect((call.$2['p_event'] as Map)['end_date'], '2026-11-09');
  });

  testWidgets('if AI is switched off mid-way, it says so plainly', (t) async {
    await _open(
      t,
      ai: FakeAiGateway(error: const TogetherAiException('CONSENT_REQUIRED')),
    );
    await t.enterText(
      find.widgetWithText(TextField, 'e.g. dinner with Kofi Sat 7pm'),
      'x',
    );
    await t.tap(find.text('Fill in'));
    await t.pumpAndSettle();
    expect(
      find.textContaining("AI help isn't available for you two right now"),
      findsOneWidget,
    );
  });

  testWidgets(
    'a shared note waits in Describe it; nothing is read until I tap',
    (t) async {
      final ai = FakeAiGateway(response: {'draft': {}});
      await _open(t, ai: ai, text: 'Dinner at Buka Sat 7pm');
      expect(find.text('Dinner at Buka Sat 7pm'), findsOneWidget);
      expect(ai.bodies, isEmpty);
    },
  );

  testWidgets('without AI, a shared note fills the title and note', (t) async {
    await _open(t, text: 'Dinner at Buka\nSat 7pm, table for 2');
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Sat 7pm, table for 2'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sat 7pm, table for 2'), findsOneWidget);
  });

  testWidgets('no AI for this couple: no Describe it box', (t) async {
    await _open(t);
    expect(find.text('Fill in'), findsNothing);
  });

  testWidgets(
    'if the partner lookup fails, Save says so instead of doing nothing',
    (t) async {
      final g = await _open(t, partnerFails: true);
      await t.enterText(find.byType(TextField).first, 'Dinner');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(g.calls.where((c) => c.$1 == 'create_couple_event'), isEmpty);
      expect(
        find.text('Could not save that. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "my partner's shared event: I can't change who sees it, I can leave or delete",
    (t) async {
      await _open(t, item: _item(createdBy: 'kofi'));
      final vis = t.widget<SegmentedButton<TogetherVisibility>>(
        find.byType(SegmentedButton<TogetherVisibility>),
      );
      expect(vis.onSelectionChanged, isNull);
      await t.scrollUntilVisible(
        find.text('Delete event'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Leave event'), findsOneWidget);
      expect(find.text('Delete event'), findsOneWidget);
    },
  );

  testWidgets(
    'after saving, the calendar refetches without waiting for realtime',
    (t) async {
      final g = await _open(t);
      final container = ProviderScope.containerOf(
        t.element(find.text('New event')),
      );
      final args = (
        relationshipId: 'r1',
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      );
      container.listen(togetherRangeProvider(args), (_, __) {});
      await container.read(togetherRangeProvider(args).future);
      final before = g.calls.where((c) => c.$1 == 'list_together_items').length;
      await t.enterText(find.byType(TextField).first, 'Dinner');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await container.read(togetherRangeProvider(args).future);
      expect(
        g.calls.where((c) => c.$1 == 'list_together_items').length,
        before + 1,
      );
    },
  );
  testWidgets(
    'asking my partner to pick sends a proposal with the chosen times',
    (t) async {
      final g = await _open(t);
      g.handlers['propose_couple_event'] = (_) => 'ev-p';
      await t.enterText(find.byType(TextField).first, 'Dinner');
      await t.scrollUntilVisible(
        find.text('Ask Kofi to pick'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(
        find.descendant(
          of: find.widgetWithText(InfoRowWidget, 'Ask Kofi to pick'),
          matching: find.byType(Switch),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Add another time'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Save'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final call = g.calls.firstWhere((c) => c.$1 == 'propose_couple_event');
      expect((call.$2['p_options'] as List), hasLength(2));
      expect(find.text('Sent to Kofi.'), findsOneWidget);
    },
  );

  testWidgets('asking my partner to hold it saves, then asks them', (t) async {
    final g = await _open(t);
    await t.enterText(find.byType(TextField).first, 'Book the plumber');
    await t.scrollUntilVisible(
      find.text("Who's holding it"),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('owner-picker')),
        matching: find.text('Kofi'),
      ),
    );
    await t.pumpAndSettle();
    g.handlers['propose_owner_handoff'] = (_) => null;
    await t.scrollUntilVisible(
      find.text('Save'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(
      g.calls.map((c) => c.$1),
      containsAllInOrder(['create_couple_event', 'propose_owner_handoff']),
    );
    final payload =
        g.calls.firstWhere((c) => c.$1 == 'create_couple_event').$2['p_event']
            as Map;
    expect(
      payload['owner_id'],
      isNull,
      reason: 'the partner is asked, never assigned',
    );
  });

  testWidgets(
    'switching Who to Me after choosing to propose just saves the event',
    (t) async {
      final g = await _open(t);
      g.handlers['propose_couple_event'] = (_) => 'ev-p';
      await t.enterText(find.byType(TextField).first, 'Dinner');
      await t.tap(
        find.descendant(
          of: find.widgetWithText(InfoRowWidget, 'Ask Kofi to pick'),
          matching: find.byType(Switch),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Starts'),
        findsNothing,
        reason: 'the offered times replace Starts/Ends',
      );
      await t.tap(find.text('Me').first); // "Who it's for" comes first
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(g.calls.map((c) => c.$1), contains('create_couple_event'));
      expect(g.calls.map((c) => c.$1), isNot(contains('propose_couple_event')));
    },
  );

  testWidgets(
    'a pending hand-off shows as asked, and saving does not ask again',
    (t) async {
      final item = _item();
      final pending = TogetherItem.fromRow({
        'item_kind': 'event',
        'item_id': item.id,
        'item_date': '2026-11-06',
        'starts_at': '2026-11-06T19:00:00+00:00',
        'ends_at': null,
        'all_day': false,
        'tz': 'Africa/Accra',
        'title': 'Dinner',
        'participant_ids': ['ama', 'kofi'],
        'owner_id': null,
        'created_by': 'ama',
        'visibility': 'shared',
        'status': 'confirmed',
        'source_ref': {
          'kind': 'event',
          'event_starts_at': '2026-11-06T19:00:00+00:00',
          'owner_proposed_to': 'kofi',
        },
      });
      final g = await _open(t, item: pending);
      final picker = t.widget<SegmentedButton<String>>(
        find.byKey(const Key('owner-picker')),
      );
      expect(picker.selected, {'partner'});
      g.handlers['propose_owner_handoff'] = (_) => null;
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        g.calls.map((c) => c.$1),
        isNot(contains('propose_owner_handoff')),
      );
    },
  );

  testWidgets(
    'asking my partner to take my item keeps it mine until they say yes',
    (t) async {
      final mine = TogetherItem.fromRow({
        'item_kind': 'event',
        'item_id': 'e1',
        'item_date': '2026-11-06',
        'starts_at': '2026-11-06T19:00:00+00:00',
        'ends_at': null,
        'all_day': false,
        'tz': 'Africa/Accra',
        'title': 'Plumber',
        'participant_ids': ['ama', 'kofi'],
        'owner_id': 'ama',
        'created_by': 'ama',
        'visibility': 'shared',
        'status': 'confirmed',
        'source_ref': {
          'kind': 'event',
          'event_starts_at': '2026-11-06T19:00:00+00:00',
        },
      });
      final g = await _open(t, item: mine);
      g.handlers['propose_owner_handoff'] = (_) => null;
      await t.tap(
        find.descendant(
          of: find.byKey(const Key('owner-picker')),
          matching: find.text('Kofi'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final payload =
          g.calls.firstWhere((c) => c.$1 == 'update_couple_event').$2['p_event']
              as Map;
      expect(payload['owner_id'], 'ama');
      expect(g.calls.map((c) => c.$1), contains('propose_owner_handoff'));
    },
  );

  testWidgets(
    'if asking my partner fails after saving, the event is saved once and I am told',
    (t) async {
      final g = await _open(t);
      g.handlers['propose_owner_handoff'] = (_) => throw Exception('offline');
      await t.enterText(find.byType(TextField).first, 'Book the plumber');
      await t.tap(
        find.descendant(
          of: find.byKey(const Key('owner-picker')),
          matching: find.text('Kofi'),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(g.calls.where((c) => c.$1 == 'create_couple_event'), hasLength(1));
      expect(find.text('New event'), findsNothing);
      expect(find.text("Added, but couldn't ask Kofi."), findsOneWidget);
    },
  );
  testWidgets('a shared event just for me can be marked a big day', (t) async {
    final g = await _open(t);
    await t.enterText(find.byType(TextField).first, 'Interview');
    await t.tap(find.text('Me').first);
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.widgetWithText(InfoRowWidget, 'A big day for me'),
        matching: find.byType(Switch),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final payload =
        g.calls.firstWhere((c) => c.$1 == 'create_couple_event').$2['p_event']
            as Map;
    expect(payload['kind'], 'big_day');
    expect(payload['participant_ids'], ['ama']);
  });

  testWidgets('the big-day toggle only shows for a shared event just for me', (
    t,
  ) async {
    await _open(t);
    expect(
      find.text('A big day for me'),
      findsNothing,
      reason: 'Who is Both by default',
    );
  });

  testWidgets("saving my partner's big day keeps it a big day", (t) async {
    final theirs = TogetherItem.fromRow({
      'item_kind': 'event',
      'item_id': 'b1',
      'item_date': '2026-11-20',
      'starts_at': null,
      'ends_at': null,
      'all_day': true,
      'tz': null,
      'title': 'Viva',
      'participant_ids': ['kofi'],
      'owner_id': null,
      'created_by': 'kofi',
      'visibility': 'shared',
      'status': 'confirmed',
      'source_ref': {'kind': 'big_day', 'start_date': '2026-11-20'},
    });
    final g = await _open(t, item: theirs);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final payload =
        g.calls.firstWhere((c) => c.$1 == 'update_couple_event').$2['p_event']
            as Map;
    expect(payload['kind'], 'big_day');
  });

  testWidgets('two quick taps on Save make one event', (t) async {
    final g = await _open(t, partnerDelay: const Duration(milliseconds: 200));
    await t.enterText(find.byType(TextField).first, 'Dinner');
    await t.tap(find.text('Save'));
    await t.pump();
    await t.tap(find.text('Save'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(g.calls.where((c) => c.$1 == 'create_couple_event'), hasLength(1));
  });

  testWidgets('after the partner lookup failed once, trying again saves', (
    t,
  ) async {
    final g = await _open(t, partnerFailures: 1);
    await t.enterText(find.byType(TextField).first, 'Dinner');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls.where((c) => c.$1 == 'create_couple_event'), isEmpty);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls.where((c) => c.$1 == 'create_couple_event'), hasLength(1));
  });

  testWidgets(
    'Repeat works again once asking my partner is no longer on offer',
    (t) async {
      await _open(t);
      await t.tap(
        find.descendant(
          of: find.widgetWithText(InfoRowWidget, 'Ask Kofi to pick'),
          matching: find.byType(Switch),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Me').first); // who it's for
      await t.pumpAndSettle();
      expect(find.text('Ask Kofi to pick'), findsNothing);
      final repeat = t.widget<InfoRowWidget>(
        find.widgetWithText(InfoRowWidget, 'Does not repeat'),
      );
      expect(repeat.onTap, isNotNull);
    },
  );

  testWidgets('All day on an evening event stays one day', (t) async {
    final g = await _open(t, now: DateTime(2026, 11, 6, 22, 30));
    await t.enterText(find.byType(TextField).first, 'Movie');
    await t.tap(
      find.descendant(
        of: find.widgetWithText(InfoRowWidget, 'All day'),
        matching: find.byType(Switch),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final payload = g.calls.single.$2['p_event'] as Map<String, dynamic>;
    expect(payload['start_date'], '2026-11-06');
    expect(
      payload.containsKey('end_date'),
      isFalse,
      reason: 'not a two-day event',
    );
  });

  testWidgets('times read in the app format, date then time', (t) async {
    final now = DateTime(2026, 11, 6, 9, 10);
    await _open(t, now: now);
    final start = DateTime(2026, 11, 6, 10);
    expect(
      find.text(
        MyDateFormat.join([
          MyDateFormat.toDate(start),
          MyDateFormat.toTime(start),
        ]),
      ),
      findsOneWidget,
    );
  });

  testWidgets('deleting a private event does not say both of you', (t) async {
    await _open(
      t,
      item: _item(visibility: TogetherVisibility.private, who: const ['ama']),
    );
    await t.scrollUntilVisible(
      find.text('Delete event'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.text('Delete event'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete event'));
    await t.pumpAndSettle();
    expect(find.text('It will be removed for both of you.'), findsNothing);
    expect(find.text('It will be deleted.'), findsOneWidget);
  });

  testWidgets('a weekly repeat keeps at least one day', (t) async {
    await _open(t, now: DateTime(2026, 11, 6, 9)); // a Friday
    await t.tap(find.text('Does not repeat'));
    await t.pumpAndSettle();
    await t.tap(find.text('Every week'));
    await t.pumpAndSettle();
    final fri = find.widgetWithText(FilterChip, 'Fri');
    expect(t.widget<FilterChip>(fri).selected, isTrue);
    await t.tap(fri);
    await t.pumpAndSettle();
    expect(t.widget<FilterChip>(fri).selected, isTrue);
  });

  testWidgets('planned on a day ahead, it starts that evening', (t) async {
    await _open(t, now: DateTime(2026, 11, 6, 9), day: DateTime(2026, 11, 20));
    final start = DateTime(2026, 11, 20, 19);
    expect(
      find.text(
        MyDateFormat.join([
          MyDateFormat.toDate(start),
          MyDateFormat.toTime(start),
        ]),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a suggestion never carries a repeat, even one picked meanwhile',
    (t) async {
      final g = await _open(t);
      await t.enterText(find.byType(TextField).first, 'Dinner');
      await t.tap(
        find.descendant(
          of: find.widgetWithText(InfoRowWidget, 'Ask Kofi to pick'),
          matching: find.byType(Switch),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Me').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Does not repeat'));
      await t.pumpAndSettle();
      await t.tap(find.text('Every week'));
      await t.pumpAndSettle();
      await t.tap(find.text('The Harolds'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final call = g.calls.singleWhere((c) => c.$1 == 'propose_couple_event');
      expect((call.$2['p_event'] as Map)['rrule'], isNull);
    },
  );

  testWidgets('closing the sheet while a failed lookup finishes is quiet', (
    t,
  ) async {
    await _open(
      t,
      partnerFailures: 1,
      partnerDelay: const Duration(milliseconds: 200),
    );
    await t.enterText(find.byType(TextField).first, 'Dinner');
    await t.tap(find.text('Save'));
    await t.pump();
    Navigator.of(t.element(find.text('New event'))).pop();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('All day on and off again keeps the end', (t) async {
    await _open(t, now: DateTime(2026, 11, 6, 9));
    final end = DateTime(2026, 11, 6, 11);
    final endText = MyDateFormat.join([
      MyDateFormat.toDate(end),
      MyDateFormat.toTime(end),
    ]);
    expect(find.text(endText), findsOneWidget);
    final allDay = find.descendant(
      of: find.widgetWithText(InfoRowWidget, 'All day'),
      matching: find.byType(Switch),
    );
    await t.tap(allDay);
    await t.pumpAndSettle();
    await t.tap(allDay);
    await t.pumpAndSettle();
    expect(find.text(endText), findsOneWidget);
  });

  testWidgets(
    'the delete question is about the saved event, not unsaved edits',
    (t) async {
      await _open(t, item: _item());
      await t.tap(find.text('Just me'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Delete event'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Delete event'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete event'));
      await t.pumpAndSettle();
      expect(find.text('It will be removed for both of you.'), findsOneWidget);
    },
  );

  group('late at night', () {
    testWidgets('a new plan from + starts tomorrow evening, not at midnight', (t) async {
      await _open(t, now: DateTime(2026, 11, 6, 23, 20));
      expect(find.text(_when(DateTime(2026, 11, 7, 19))), findsOneWidget);
    });

    testWidgets('added to today, it stays today: the next quarter hour', (t) async {
      await _open(t, now: DateTime(2026, 11, 6, 23, 20), day: DateTime(2026, 11, 6));
      expect(find.text(_when(DateTime(2026, 11, 6, 23, 30))), findsOneWidget);
    });
  });

  group('All repeats keeps the day picked', () {
    TogetherItem monthly() => TogetherItem.fromRow({
      'item_kind': 'event', 'item_id': 'm1', 'item_date': '2026-11-30',
      'starts_at': null, 'ends_at': null, 'all_day': true, 'tz': null,
      'title': 'Rent', 'participant_ids': const ['ama', 'kofi'], 'owner_id': null,
      'created_by': 'ama', 'visibility': 'shared', 'status': 'confirmed',
      'source_ref': {'kind': 'event', 'rrule': 'FREQ=MONTHLY', 'start_date': '2026-10-31'},
    });

    Future<Map> saveAllAfterMove(WidgetTester t, FakeTogetherGateway g, DateTime from, DateTime to, {bool allDay = false}) async {
      t.view.physicalSize = const Size(2400, 4200);
      await t.pumpAndSettle();
      await t.tap(find.text(allDay ? MyDateFormat.toDate(from) : _when(from)));
      await t.pumpAndSettle();
      t.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(to);
      Navigator.of(t.element(find.byType(CupertinoDatePicker))).pop();
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('All repeats'));
      await t.pumpAndSettle();
      return g.calls.singleWhere((c) => c.$1 == 'update_couple_event').$2['p_event'] as Map;
    }

    testWidgets('monthly on the 31st, November\'s moved to the 29th: every 29th', (t) async {
      final g = await _open(t, item: monthly());
      final payload = await saveAllAfterMove(t, g, DateTime(2026, 11, 30), DateTime(2026, 11, 29), allDay: true);
      expect(payload['start_date'], '2026-10-29');
      expect(payload['excluded_shift'], {'months': 0, 'day': 29});
    });

    testWidgets('weekly, moved a day: skipped dates move a day too', (t) async {
      final g = await _open(t, item: _occurrence());
      final thisOne = DateTime.parse('2026-10-30T19:00:00Z').toLocal();
      final payload = await saveAllAfterMove(t, g, thisOne, thisOne.add(const Duration(days: 1)));
      expect(payload['excluded_shift'], {'days': 1});
    });

    testWidgets('only the time changed: skipped dates stay', (t) async {
      final g = await _open(t, item: _occurrence());
      final thisOne = DateTime.parse('2026-10-30T19:00:00Z').toLocal();
      final payload = await saveAllAfterMove(t, g, thisOne, thisOne.add(const Duration(hours: 1)));
      expect(payload.containsKey('excluded_shift'), isFalse);
    });
  });

  for (final editing in [false, true])
    testWidgets('every row carries its own divider${editing ? ' (editing)' : ''}', (t) async {
      await _open(t, item: editing ? _item() : null);
      final rows = t.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).toList();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(r.showDivider, isTrue, reason: r.title);
      }
    });
}
