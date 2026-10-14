import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_need.dart';
import 'package:attune/features/together/domain/together_ritual.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/ritual_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

final _ritual = TogetherRitual.fromRow({
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
});

/// What the sheet asked the server to change (reads like its memories list
/// are left out).
List<(String, Map<String, dynamic>)> _writes(FakeTogetherGateway g) =>
    g.calls.where((c) => !c.$1.startsWith('list_')).toList();

Future<FakeTogetherGateway> _host(
  WidgetTester t,
  Future<void> Function(BuildContext) open, {
  List<Map<String, dynamic>> memories = const [],
}) async {
  t.view.physicalSize = const Size(1170, 4200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({
    'propose_ritual': (_) => 'rit-2',
    'update_ritual': (_) => null,
    'set_ritual_status': (_) => null,
    'skip_ritual_occurrence': (_) => null,
    'decide_ritual': (_) => null,
    'list_together_ritual_memories': (_) => memories,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherDeviceTimezoneProvider.overrideWith(
          (ref) async => 'Africa/Accra',
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        togetherMeProvider.overrideWithValue('ama'),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed: () => open(c),
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

void main() {
  testWidgets(
    'picking Date night proposes it to my partner with its defaults',
    (t) async {
      final g = await _host(t, (c) => showRitualTemplatesSheet(c, 'r1'));
      expect(find.text('State of the Union'), findsOneWidget);
      await t.tap(find.text('Date night'));
      await t.pumpAndSettle();
      expect(find.text('Suggest'), findsOneWidget);
      await t.tap(find.text('Suggest'));
      await t.pumpAndSettle();
      final p = _writes(g).single.$2['p_ritual'] as Map;
      expect(
        [
          p['template'],
          p['cadence'],
          p['weekday'],
          p['local_time'],
          p['duration_min'],
          p['tz'],
        ],
        ['date_night', 'weekly', 5, '19:00', 120, 'Africa/Accra'],
      );
      expect(find.text('Sent to Kofi.'), findsOneWidget);
    },
  );

  testWidgets('skipping a week asks once, with no guilt', (t) async {
    final g = await _host(t, (c) => showRitualSheet(c, 'r1', _ritual));
    await t.tap(find.textContaining('Skip'));
    await t.pumpAndSettle();
    expect(_writes(g), isEmpty);
    await t.tap(find.widgetWithText(TextButton, 'Skip it'));
    await t.pumpAndSettle();
    expect(_writes(g).single.$2, {'p_event_id': 'e9'});
    expect(find.text('Skipped this week.'), findsOneWidget);
  });

  testWidgets('pausing and ending; ending asks first', (t) async {
    final g = await _host(t, (c) => showRitualSheet(c, 'r1', _ritual));
    await t.tap(find.text('Pause'));
    await t.pumpAndSettle();
    expect(_writes(g).last.$2, {'p_ritual_id': 'rit-1', 'p_status': 'paused'});
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('End this ritual'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'End it'));
    await t.pumpAndSettle();
    expect(_writes(g).last.$2, {'p_ritual_id': 'rit-1', 'p_status': 'ended'});
  });

  testWidgets("a partner's ritual suggestion can be accepted", (t) async {
    final need = TogetherNeed.fromRow({
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
        'tz': 'Europe/London',
      },
    });
    final g = await _host(t, (c) => showRitualProposalSheet(c, need));
    expect(find.text('Kofi suggested a ritual'), findsOneWidget);
    expect(find.text('Sundays at 19:00 (London time)'), findsOneWidget);
    await t.tap(find.text("We're in"));
    await t.pumpAndSettle();
    expect(_writes(g).single.$2, {'p_ritual_id': 'rit-3', 'p_accept': true});
  });

  testWidgets('my unanswered suggestion can be withdrawn', (t) async {
    final mine = TogetherRitual.fromRow({
      'ritual_id': 'rit-4',
      'template': 'date_night',
      'title': 'Date night',
      'cadence': 'weekly',
      'weekday': 5,
      'local_time': '19:00',
      'duration_min': 120,
      'tz': 'Africa/Accra',
      'status': 'proposed',
      'created_by': 'ama',
      'proposed_to': 'kofi',
    });
    final g = await _host(t, (c) => showSentRitualSheet(c, mine));
    expect(find.text('Waiting for Kofi'), findsOneWidget);
    await t.tap(find.text('Withdraw'));
    await t.pumpAndSettle();
    expect(_writes(g).single.$2, {'p_ritual_id': 'rit-4', 'p_status': 'ended'});
    expect(find.text('Withdrawn.'), findsOneWidget);
  });

  testWidgets("a ritual's sheet lists its memories, with no count", (t) async {
    await _host(
      t,
      (c) => showRitualSheet(c, 'r1', _ritual),
      memories: [
        {
          'moment_id': 'm1',
          'occurred_at': '2026-10-30',
          'title': 'Date night',
          'note': 'Dancing after',
          'logged_by': 'kofi',
        },
      ],
    );
    expect(find.text('Memories'), findsOneWidget);
    expect(find.text('Dancing after'), findsOneWidget);
    expect(find.textContaining('memories ('), findsNothing);
  });

  testWidgets('with no memories yet, the sheet just says how to add one', (
    t,
  ) async {
    await _host(t, (c) => showRitualSheet(c, 'r1', _ritual));
    expect(
      find.text('After a week, add a line about it from Together.'),
      findsOneWidget,
    );
  });
}
