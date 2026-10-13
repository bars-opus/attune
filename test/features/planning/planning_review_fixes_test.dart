import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/planning/data/planning_error.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/domain/planning_outbox.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/table_block_view.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');
const _args = (relationshipId: 'r1', entryId: 'e1');

void main() {
  group('review I3: tables survive column changes', () {
    test('a new column never reuses a key still held by any row', () {
      final cols = [
        const PlanningTableColumn(key: 'c0', label: 'Bill', type: PlanningColumnType.text),
        const PlanningTableColumn(key: 'c1', label: 'Amount', type: PlanningColumnType.money),
      ];
      final rows = [PlanningItem.fromJson({...fakeItemJson(id: 'r'), 'cells': {'c0': 'Rent', 'c4': 'Ama'}})];
      expect(nextPlanningColumnKey(cols, rows), 'c5');
      expect(nextPlanningColumnKey(cols, const []), 'c2');
    });

    testWidgets('a value that no longer fits its column shows as text instead of crashing', (tester) async {
      final g = FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 't', type: 'table', payload: {
                'title': 'Costs',
                'columns': [
                  {'key': 'c0', 'label': 'Cost', 'type': 'money'},
                  {'key': 'c1', 'label': 'When', 'type': 'date'},
                  {'key': 'c2', 'label': 'Done', 'type': 'check'},
                ],
              }, items: [
                {...fakeItemJson(id: 'r1'), 'cells': {'c0': 'about 50', 'c1': 'soon', 'c2': 'yes'}},
              ]),
            ]),
      });
      await tester.pumpWidget(planningTestApp(g, _screen));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('about 50'), findsOneWidget);
      await tester.tap(find.text('about 50'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the row editor opens too');
    });
  });

  testWidgets('review I4: contributions are listed and can be removed', (tester) async {
    var deleted = false;
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            {...fakeBlockJson(id: 'pr', type: 'progress', payload: {'mode': 'numeric', 'unit': 'money'}, items: [
                if (!deleted) {...fakeItemJson(id: 'k1', text: 'Bonus'), 'amount_minor': 25000},
              ]),
              'target_minor': 100000, 'target_currency': 'GHS', 'computed': {'mode': 'numeric', 'current': 25000}},
          ]),
      'delete_planning_block_item': (_) {
        deleted = true;
        return {'deleted': true};
      },
    });
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('Bonus'), findsOneWidget);
    expect(find.text('+${formatPlanningMoney(25000, 'GHS')}'), findsOneWidget);
    await tester.drag(find.text('Bonus'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_block_item').single, {'p_id': 'k1'});
  });

  group('review I6: an expense retry cannot save twice', () {
    test('a failed refresh after a successful save does not report failure', () async {
      final g = FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'x', type: 'expenses')])});
      final c = ProviderContainer(overrides: planningOverrides(g, store: MemoryOutboxStore()));
      addTearDown(c.dispose);
      c.listen(planningEntryProvider(_args), (_, __) {});
      await c.read(planningEntryProvider(_args).future);
      g.handlers['save_planning_rich_item'] = (p) => {...fakeItemJson(id: p['p_id'] as String), 'amount_minor': 100};
      g.handlers['get_planning_entry'] = (_) => throw Exception('SocketException: offline');
      final saved = await c.read(planningEntryProvider(_args).notifier)
          .saveRichItem('x', id: 'fixed-id', fields: {'label': 'Taxi', 'amount_minor': 100});
      expect(saved.id, 'fixed-id');
      expect(g.callsTo('save_planning_rich_item').single['p_id'], 'fixed-id');
    });

    testWidgets('a failed save keeps the sheet and retries with the same id', (tester) async {
      var attempts = 0;
      final g = FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'x', type: 'expenses')]),
        'save_planning_rich_item': (p) {
          attempts++;
          if (attempts == 1) throw Exception('SocketException: offline');
          return {...fakeItemJson(id: p['p_id'] as String, text: 'Taxi'), 'amount_minor': 1200, 'currency': 'GHS'};
        },
      });
      await tester.pumpWidget(planningTestApp(g, _screen));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(AppTextFormField, 'What for'), 'Taxi');
      await tester.enterText(find.widgetWithText(AppTextFormField, 'Amount'), '12');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppTextFormField, 'What for'), findsOneWidget, reason: 'the sheet stays open with what was typed');
      expect(find.text('Taxi'), findsWidgets);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final ids = [for (final c in g.callsTo('save_planning_rich_item')) c['p_id']];
      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
      expect(find.widgetWithText(AppTextFormField, 'What for'), findsNothing, reason: 'closed once saved');
    });
  });

  test('PlanningNetwork stays the type a dropped save surfaces as', () {
    expect(mapPlanningError(Exception('SocketException')), isA<PlanningNetwork>());
  });
}
