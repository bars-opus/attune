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
  DateTime? now,
  CalendarExporter? exporter,
  ({DateTime start, DateTime end})? window,
  TogetherAiGateway? ai,
  String? text,
}) async {
  // A phone-sized screen, so the sheet's lower rows are on screen.
  // Tall enough that the whole editor fits without scrolling.
  t.view.physicalSize = const Size(1170, 4200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
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
          if (partnerFails) throw Exception('offline');
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

void main() {
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
}
