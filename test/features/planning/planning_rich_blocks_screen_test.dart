import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _expense(String id, String label, int minor, String paidBy, {int version = 1}) => {
      ...fakeItemJson(id: id, text: label, version: version),
      'amount_minor': minor, 'currency': 'GHS', 'paid_by': paidBy, 'split_share_minor': null,
    };

Map<String, dynamic> _entry({Map<String, dynamic>? split, List<Map<String, dynamic>>? blocks, int spent = 3000}) {
  final base = fakeEntryDetailJson(title: 'Accra weekend', blocks: blocks ?? [
    fakeBlockJson(id: 'x', type: 'expenses', payload: {'title': 'Costs'}, items: [
      _expense('i1', 'Hotel', 2000, 'u-a'),
      _expense('i2', 'Taxi', 1000, 'u-b'),
    ]),
    {...fakeBlockJson(id: 'bud', type: 'budget', sortKey: 'k', payload: {'title': 'Budget'}),
      'target_minor': 2500, 'target_currency': 'GHS',
      'computed': {'spent_minor': spent, 'other_currencies': []}},
    fakeBlockJson(id: 'ln', type: 'link', sortKey: 'l', payload: {
      'url': 'https://villa.example/ubud',
      'preview': {'status': 'ok', 'title': 'Ubud villa with pool', 'host': 'villa.example'},
    }),
    fakeBlockJson(id: 'ln2', type: 'link', sortKey: 'm', payload: {'url': 'https://plain.example/x'}),
    fakeBlockJson(id: 'pl', type: 'place', sortKey: 'n', payload: {'name': 'Labadi Beach', 'address': 'Accra, Ghana'}),
    fakeBlockJson(id: 't', type: 'table', sortKey: 'o', payload: {
      'title': 'Packing',
      'columns': [
        {'key': 'c0', 'label': 'Item', 'type': 'text'},
        {'key': 'c1', 'label': 'Packed', 'type': 'check'},
      ],
    }, items: [
      {...fakeItemJson(id: 'r1'), 'cells': {'c0': 'Sunscreen', 'c1': true}},
    ]),
    fakeBlockJson(id: 'ph', type: 'photo', sortKey: 'p', payload: {'title': 'Photos', 'paths': []}),
  ]);
  final entry = Map<String, dynamic>.from(base['entry'] as Map);
  if (split != null) entry['split'] = split;
  return {...base, 'entry': entry};
}

/// The plan's own list (other blocks scroll sideways too).
final _list = find.descendant(of: find.byType(ReorderableListView), matching: find.byType(Scrollable)).first;

void main() {
  testWidgets('expenses, budget, link, place, table and photo blocks render', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => _entry()});
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();

    expect(find.text('Hotel'), findsOneWidget);
    expect(find.text(formatPlanningMoney(2000, 'GHS')), findsOneWidget);
    expect(find.text('Total ${formatPlanningMoney(3000, 'GHS')}'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Ubud villa with pool'), 200, scrollable: _list);
    expect(find.text('${formatPlanningMoney(500, 'GHS')} over budget'), findsOneWidget);
    expect(find.text('Ubud villa with pool'), findsOneWidget);
    expect(find.text('villa.example'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Labadi Beach'), 200, scrollable: _list);
    expect(find.text('plain.example'), findsOneWidget, reason: 'no preview: host + url still shown');
    expect(find.text('Accra, Ghana'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Sunscreen'), 200, scrollable: _list);
    expect(find.text('Packed'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Add photo'), 200, scrollable: _list);
    expect(find.text('Add photo'), findsOneWidget);
  });

  testWidgets('adding an expense parses the amount into minor units', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => _entry()});
    g.handlers['save_planning_rich_item'] = (p) => _expense(p['p_id'] as String, 'Dinner', 4550, 'u-a');
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What for'), 'Dinner');
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '45.50');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final fields = g.callsTo('save_planning_rich_item').single['p_fields'] as Map;
    expect(fields['label'], 'Dinner');
    expect(fields['amount_minor'], 4550);
    expect(fields['currency'], 'GHS');
    expect(fields['paid_by'], 'u-a', reason: 'defaults to me');
  });

  testWidgets('split on shows who evens out, and Mark settled settles', (tester) async {
    var settled = false;
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => _entry(split: {
            'settled_at': settled ? '2026-10-12T10:00:00Z' : null,
            'balances': settled ? [] : [{'currency': 'GHS', 'minor': 500, 'owed_to': 'u-a', 'owed_by': 'u-b'}],
          }),
    });
    g.handlers['settle_planning_split'] = (_) {
      settled = true;
      return {'entry': _entry(split: {'settled_at': '2026-10-12T10:00:00Z', 'balances': []})['entry']};
    };
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('Kofi owes Ama ${formatPlanningMoney(500, 'GHS')}'), findsOneWidget);
    await tester.tap(find.text('Mark settled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settle'));
    await tester.pumpAndSettle();
    expect(g.callsTo('settle_planning_split'), hasLength(1));
    expect(find.text('All even'), findsOneWidget);
  });

  testWidgets('split can be turned on from the plan menu', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => _entry()});
    g.handlers['set_planning_entry_split'] =
        (_) => {'entry': _entry(split: {'settled_at': null, 'balances': []})['entry']};
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split costs'));
    await tester.pumpAndSettle();
    expect(g.callsTo('set_planning_entry_split').single, {'p_entry_id': 'e1', 'p_enabled': true});
    expect(find.text('All even'), findsOneWidget);
  });

  testWidgets('the tool tray offers the rich blocks; a link asks for its address first', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => _entry(blocks: [])});
    g.handlers['add_planning_block'] = (p) => fakeBlockJson(
        id: p['p_id'] as String, type: p['p_block_type'] as String, payload: p['p_payload'] as Map<String, dynamic>);
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add block'));
    await tester.pumpAndSettle();
    for (final label in ['Table', 'Photos', 'Link', 'Place', 'Expenses', 'Budget']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Web address'), 'villa.example/ubud');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final sent = g.callsTo('add_planning_block').single;
    expect(sent['p_block_type'], 'link');
    expect((sent['p_payload'] as Map)['url'], 'https://villa.example/ubud', reason: 'scheme added for the user');
  });

  testWidgets('a budget target is typed as money', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => _entry()});
    g.handlers['update_planning_block_target'] = (p) => {
          ...fakeBlockJson(id: 'bud', type: 'budget', sortKey: 'k', payload: {'title': 'Budget'}, version: 2),
          'target_minor': p['p_target_minor'], 'target_currency': p['p_currency'],
          'computed': {'spent_minor': 3000, 'other_currencies': []},
        };
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Set budget'), 200, scrollable: _list);
    await tester.tap(find.text('Set budget'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Budget'), '100');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(g.callsTo('update_planning_block_target').single,
        {'p_id': 'bud', 'p_version': 1, 'p_target_minor': 10000, 'p_currency': 'GHS'});
    expect(find.text('${formatPlanningMoney(7000, 'GHS')} left'), findsOneWidget);
  });
}
