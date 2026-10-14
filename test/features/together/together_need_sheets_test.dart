import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_need.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_need_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

final _proposal = TogetherNeed.fromRow({
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
      {
        'id': 'o2',
        'position': 2,
        'start_date': '2026-11-07',
        'end_date': null,
        'starts_at': null,
        'ends_at': null,
      },
    ],
  },
});

Future<FakeTogetherGateway> _host(
  WidgetTester t,
  Future<void> Function(BuildContext) open,
) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({
    'decide_couple_event': (_) => null,
    'decide_owner_handoff': (_) => null,
    'delete_couple_event': (_) => null,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
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
  testWidgets('accepting needs a chosen time, then confirms it', (t) async {
    final g = await _host(t, (c) => showProposalSheet(c, _proposal));
    expect(find.text('Kofi suggested'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(g.calls, isEmpty, reason: 'nothing chosen yet');
    await t.tap(find.textContaining('Sat'));
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {
      'p_event_id': 'e1',
      'p_option_id': 'o2',
      'p_accept': true,
      'p_note': null,
    });
    expect(find.text('Added to Together.'), findsOneWidget);
  });

  testWidgets("can't make any: declines with an optional note", (t) async {
    final g = await _host(t, (c) => showProposalSheet(c, _proposal));
    await t.enterText(find.byType(TextField), 'Working late');
    await t.tap(find.text("Can't make these"));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {
      'p_event_id': 'e1',
      'p_option_id': null,
      'p_accept': false,
      'p_note': 'Working late',
    });
  });

  testWidgets('a hand-off can be taken on', (t) async {
    final handoff = TogetherNeed.fromRow({
      'need_kind': 'handoff',
      'item_id': 'e2',
      'title': 'Book the plumber',
      'due_date': '2026-11-10',
      'created_by': 'kofi',
      'detail': {'kind': 'event'},
    });
    final g = await _host(t, (c) => showHandoffSheet(c, handoff));
    expect(find.text('Book the plumber'), findsOneWidget);
    await t.tap(find.text("I'll take it"));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {'p_event_id': 'e2', 'p_accept': true});
  });

  testWidgets('my own proposal says no reply yet and can be withdrawn', (
    t,
  ) async {
    final sent = TogetherNeed.fromRow({
      'need_kind': 'sent_proposal',
      'item_id': 'e3',
      'title': 'Hike',
      'due_date': null,
      'created_by': 'ama',
      'detail': {
        'all_day': true,
        'proposed_to': 'kofi',
        'expires_at': '2026-11-09T10:00:00+00:00',
        'options': [],
      },
    });
    final g = await _host(t, (c) => showSentProposalSheet(c, sent));
    expect(find.text('No reply yet'), findsOneWidget);
    await t.tap(find.text('Withdraw'));
    await t.pumpAndSettle();
    expect(g.calls.single.$1, 'delete_couple_event');
  });
}
