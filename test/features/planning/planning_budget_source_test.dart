// A budget follows one source: all of the plan's expenses, one Expenses
// block, or a money table. Chosen from the budget ("Counts"), linked by
// itself when there is exactly one candidate, and used by the Expenses chart.
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

Map<String, dynamic> _budget(
  String id, {
  String source = 'all',
  String? sourceId,
  int? target = 500000,
}) => {
  ...fakeBlockJson(
    id: id,
    type: 'budget',
    payload: {
      'title': 'Budget',
      if (sourceId != null) 'source_block_id': sourceId,
    },
  ),
  'target_minor': target,
  'target_currency': 'GHS',
  'computed': {
    'spent_minor': 0,
    'other_currencies': [],
    'source': source,
    'source_block_id': sourceId,
  },
};

final _travel = fakeBlockJson(
  id: 'x1',
  type: 'expenses',
  payload: {'title': 'Travel'},
);
final _food = fakeBlockJson(
  id: 'x2',
  type: 'expenses',
  payload: {'title': 'Food'},
);
final _costs = fakeBlockJson(
  id: 't1',
  type: 'table',
  payload: {
    'title': 'Costs',
    'columns': [
      {'key': 'c0', 'label': 'Day', 'type': 'text'},
      {'key': 'c1', 'label': 'Tickets', 'type': 'money'},
    ],
  },
);
final _notes = fakeBlockJson(
  id: 't2',
  type: 'table',
  payload: {
    'title': 'Packing',
    'columns': [
      {'key': 'c0', 'label': 'Thing', 'type': 'text'},
    ],
  },
);

FakePlanningGateway _gateway(List<Map<String, dynamic>> blocks) =>
    FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks),
      'update_planning_block':
          (p) => {
            ..._budget(
              'b1',
              source: 'table',
              sourceId: (p['p_payload'] as Map)['source_block_id'] as String?,
            ),
            'payload': p['p_payload'],
            'version': 2,
          },
      'add_planning_block':
          (p) => fakeBlockJson(id: p['p_id'] as String, type: 'budget'),
    });

void main() {
  test('the server says what a budget counts; missing means all expenses', () {
    final b = PlanningBlock.fromJson(
      _budget('b1', source: 'expenses', sourceId: 'x1'),
    );
    expect(b.budget!.source, PlanningBudgetSource.expenses);
    expect(b.budget!.sourceBlockId, 'x1');
    expect(
      PlanningBudgetComputed.fromJson({'spent_minor': 0}).source,
      PlanningBudgetSource.all,
    );
  });

  testWidgets('the budget says what it counts', (t) async {
    await t.pumpWidget(
      planningTestApp(
        _gateway([_travel, _budget('b1', source: 'expenses', sourceId: 'x1')]),
        _screen,
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.widgetWithText(InfoRowWidget, 'Counts: Travel'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Counts offers all expenses, each Expenses block and each money table; a choice saves the link',
    (t) async {
      final g = _gateway([_travel, _food, _costs, _notes, _budget('b1')]);
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pumpAndSettle();
      final counts = find.widgetWithText(InfoRowWidget, 'Counts: All expenses');
      await t.scrollUntilVisible(
        counts,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(counts);
      await t.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('planning-budget-source-sheet'));
      for (final label in ['All expenses', 'Travel', 'Food', 'Costs']) {
        expect(
          find.descendant(
            of: sheet,
            matching: find.widgetWithText(InfoRowWidget, label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      // A divider under every choice but the last.
      final rows =
          t
              .widgetList<InfoRowWidget>(
                find.descendant(of: sheet, matching: find.byType(InfoRowWidget)),
              )
              .toList();
      expect([for (final r in rows) r.showDivider], [true, true, true, false]);
      expect(
        find.descendant(of: sheet, matching: find.text('Packing')),
        findsNothing,
        reason: 'a table without a money column has nothing to count',
      );
      await t.tap(
        find.descendant(
          of: sheet,
          matching: find.widgetWithText(InfoRowWidget, 'Costs'),
        ),
      );
      await t.pumpAndSettle();
      final payload =
          g.callsTo('update_planning_block').single['p_payload'] as Map;
      expect(payload['source_block_id'], 't1');
      expect(
        payload['title'],
        'Budget',
        reason: 'the rest of the payload is kept',
      );
      expect(
        find.widgetWithText(InfoRowWidget, 'Counts: Costs (table)'),
        findsOneWidget,
      );
    },
  );

  group('a new budget', () {
    Future<Map> added(List<Map<String, dynamic>> blocks) async {
      final g = _gateway(blocks);
      final c = ProviderContainer(overrides: planningOverrides(g));
      addTearDown(c.dispose);
      const args = (relationshipId: 'r1', entryId: 'e1');
      await c.read(planningEntryProvider(args).future);
      await c
          .read(planningEntryProvider(args).notifier)
          .addBlock(PlanningBlockType.budget);
      return g.callsTo('add_planning_block').single['p_payload'] as Map;
    }

    test('follows the only Expenses block or money table by itself', () async {
      expect((await added([_travel]))['source_block_id'], 'x1');
      expect((await added([_costs, _notes]))['source_block_id'], 't1');
    });

    test('with several, or none, it starts on all expenses', () async {
      expect(
        (await added([_travel, _costs])).containsKey('source_block_id'),
        isFalse,
      );
      expect((await added([_notes])).containsKey('source_block_id'), isFalse);
    });
  });

  group('a table edit re-reads the budget', () {
    Future<int> reads(List<Map<String, dynamic>> blocks) async {
      final g = _gateway(blocks);
      g.handlers['save_planning_rich_item'] = (p) => {
            ...fakeItemJson(id: p['p_id'] as String),
            'cells': {'c1': 100},
          };
      final c = ProviderContainer(overrides: planningOverrides(g));
      addTearDown(c.dispose);
      const args = (relationshipId: 'r1', entryId: 'e1');
      await c.read(planningEntryProvider(args).future);
      await c.read(planningEntryProvider(args).notifier).saveRichItem('t1', fields: {
        'cells': {'c1': 100},
      });
      return g.callsTo('get_planning_entry').length;
    }

    test('when the plan has a budget', () async {
      expect(await reads([_costs, _budget('b1', source: 'table', sourceId: 't1')]), 2);
    });

    test('and not when it has none', () async {
      expect(await reads([_costs]), 1);
    });
  });
}
