// Countdown and Progress say what they follow ("Counts to" / "Tracks"),
// let you choose it from the app's sheet, and link by themselves when the
// plan has exactly one candidate.
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

final _tripDates = fakeBlockJson(
  id: 'd1',
  type: 'date',
  payload: {'title': 'Trip dates'},
  dateStart: '2026-12-01',
);
final _bookBy = fakeBlockJson(
  id: 'd2',
  type: 'date',
  payload: {'title': 'Book by'},
  dateStart: '2026-11-05',
);
final _packing = fakeBlockJson(
  id: 'k1',
  type: 'checklist',
  payload: {'title': 'Packing'},
);
final _beforeWeGo = fakeBlockJson(
  id: 'k2',
  type: 'checklist',
  payload: {'title': 'Before we go'},
);

Map<String, dynamic> _countdown({
  String? follows = 'd1',
  String? target = '2026-12-01',
}) => {
  ...fakeBlockJson(
    id: 'cd',
    type: 'countdown',
    payload: {
      'title': 'Countdown',
      if (follows != null) 'date_block_id': follows,
    },
  ),
  'computed': {'target_date': target, 'date_block_id': follows},
};

Map<String, dynamic> _progress({String? follows = 'k1'}) => {
  ...fakeBlockJson(
    id: 'pg',
    type: 'progress',
    payload: {
      'mode': 'checklist',
      if (follows != null) 'checklist_block_id': follows,
    },
  ),
  'computed': {
    'mode': 'checklist',
    'done': 0,
    'total': 0,
    'checklist_block_id': follows,
  },
};

FakePlanningGateway _gateway(List<Map<String, dynamic>> blocks) =>
    FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks),
      'update_planning_block': (p) {
        final payload = p['p_payload'] as Map<String, dynamic>;
        final original = blocks.firstWhere((b) => b['id'] == p['p_id']);
        return {
          ...original,
          'payload': payload,
          'version': 2,
          'computed': {
            ...(original['computed'] as Map),
            if (payload.containsKey('date_block_id'))
              'date_block_id': payload['date_block_id'],
            if (payload.containsKey('checklist_block_id'))
              'checklist_block_id': payload['checklist_block_id'],
          },
        };
      },
      'add_planning_block':
          (p) => fakeBlockJson(
            id: p['p_id'] as String,
            type: p['p_block_type'] as String,
          ),
    });

Finder _sheet() => find.byKey(const ValueKey('planning-block-picker-sheet'));

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  test('the server says which date and which checklist they follow', () {
    expect(PlanningBlock.fromJson(_countdown()).countdownDateBlockId, 'd1');
    expect(
      PlanningBlock.fromJson(_progress()).progress!.checklistBlockId,
      'k1',
    );
  });

  testWidgets(
    'a countdown says what it counts to, and another date can be chosen',
    (t) async {
      final g = _gateway([_tripDates, _bookBy, _countdown()]);
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pumpAndSettle();
      final row = find.widgetWithText(InfoRowWidget, 'Counts to: Trip dates');
      await _scrollTo(t, row);
      await t.tap(row);
      await t.pumpAndSettle();
      final rows =
          t
              .widgetList<InfoRowWidget>(
                find.descendant(
                  of: _sheet(),
                  matching: find.byType(InfoRowWidget),
                ),
              )
              .toList();
      expect([for (final r in rows) r.title], ['Trip dates', 'Book by']);
      expect([for (final r in rows) r.showDivider], [true, false]);
      expect(
        find.descendant(
          of: _sheet(),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      await t.tap(
        find.descendant(
          of: _sheet(),
          matching: find.widgetWithText(InfoRowWidget, 'Book by'),
        ),
      );
      await t.pumpAndSettle();
      final payload =
          g.callsTo('update_planning_block').single['p_payload'] as Map;
      expect(payload['date_block_id'], 'd2');
      expect(
        payload['title'],
        'Countdown',
        reason: 'the rest of the payload is kept',
      );
      expect(
        find.widgetWithText(InfoRowWidget, 'Counts to: Book by'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a trip waiting on its poll says so', (t) async {
    await t.pumpWidget(
      planningTestApp(
        _gateway([
          fakeBlockJson(id: 'pl', type: 'date_poll'),
          _countdown(follows: null, target: null),
        ]),
        _screen,
      ),
    );
    await t.pumpAndSettle();
    await _scrollTo(
      t,
      find.text('Lock a date in the poll and the countdown starts.'),
    );
    expect(
      find.text('Lock a date in the poll and the countdown starts.'),
      findsOneWidget,
    );
    expect(find.textContaining('Counts to'), findsNothing);
  });

  testWidgets(
    'a checklist progress says what it tracks, and another checklist can be chosen',
    (t) async {
      final g = _gateway([_packing, _beforeWeGo, _progress()]);
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pumpAndSettle();
      final row = find.widgetWithText(InfoRowWidget, 'Tracks: Packing');
      await _scrollTo(t, row);
      await t.tap(row);
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: _sheet(),
          matching: find.widgetWithText(InfoRowWidget, 'Before we go'),
        ),
      );
      await t.pumpAndSettle();
      final payload =
          g.callsTo('update_planning_block').single['p_payload'] as Map;
      expect(payload['checklist_block_id'], 'k2');
      expect(payload['mode'], 'checklist');
      expect(
        find.widgetWithText(InfoRowWidget, 'Tracks: Before we go'),
        findsOneWidget,
      );
    },
  );

  group('a new block links itself to the only candidate', () {
    Future<Map> added(
      List<Map<String, dynamic>> blocks,
      PlanningBlockType type, [
      Map<String, dynamic>? payload,
    ]) async {
      final g = _gateway(blocks);
      final c = ProviderContainer(overrides: planningOverrides(g));
      addTearDown(c.dispose);
      const args = (relationshipId: 'r1', entryId: 'e1');
      await c.read(planningEntryProvider(args).future);
      await c
          .read(planningEntryProvider(args).notifier)
          .addBlock(type, payload: payload);
      return g.callsTo('add_planning_block').single['p_payload'] as Map;
    }

    test('a countdown, to the only dated Date block', () async {
      expect(
        (await added([
          _tripDates,
        ], PlanningBlockType.countdown))['date_block_id'],
        'd1',
      );
      expect(
        (await added([
          _tripDates,
          _bookBy,
        ], PlanningBlockType.countdown)).containsKey('date_block_id'),
        isFalse,
      );
      expect(
        (await added(
          [],
          PlanningBlockType.countdown,
        )).containsKey('date_block_id'),
        isFalse,
      );
    });

    test(
      'a checklist progress, to the only checklist; a numeric one never',
      () async {
        final one = await added(
          [_packing],
          PlanningBlockType.progress,
          {'mode': 'checklist'},
        );
        expect(one['checklist_block_id'], 'k1');
        expect(one['mode'], 'checklist');
        expect(
          (await added(
            [_packing, _beforeWeGo],
            PlanningBlockType.progress,
            {'mode': 'checklist'},
          )).containsKey('checklist_block_id'),
          isFalse,
        );
        expect(
          (await added(
            [_packing],
            PlanningBlockType.progress,
            {'mode': 'numeric', 'unit': 'count'},
          )).containsKey('checklist_block_id'),
          isFalse,
        );
      },
    );
  });
}
