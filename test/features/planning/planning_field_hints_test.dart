// Empty fields show a short example of what goes in them: a table column's
// own hint, amounts as "0.00", and examples in the expense, budget, plan,
// checklist and progress sheets.
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/table_block_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Future<void> _open(WidgetTester t, List<Map<String, dynamic>> blocks) async {
  await t.pumpWidget(
    planningTestApp(
      FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks),
      }),
      _screen,
    ),
  );
  await t.pumpAndSettle();
}

/// The hint inside the field labelled [label].
Finder _hint(String label, String hint) => find.descendant(
  of: find.widgetWithText(AppTextFormField, label),
  matching: find.text(hint),
);

final _wishlist = fakeBlockJson(
  id: 't',
  type: 'table',
  payload: {
    'title': 'Wishlist',
    'columns': [
      {'key': 'c0', 'label': 'Item', 'type': 'text', 'hint': 'Headphones'},
      {'key': 'c1', 'label': 'Price', 'type': 'money'},
      {
        'key': 'c2',
        'label': 'Where to buy',
        'type': 'text',
        'hint': 'Shop or website',
      },
      {'key': 'c3', 'label': 'How many', 'type': 'number'},
    ],
  },
);

void main() {
  test('a column carries its hint, and writes it back', () {
    final c = PlanningTableColumn.fromJson({
      'key': 'c2',
      'label': 'Where to buy',
      'type': 'text',
      'hint': 'Shop or website',
    });
    expect(c.hint, 'Shop or website');
    expect(c.toJson()['hint'], 'Shop or website');
    expect(
      PlanningTableColumn.fromJson({
        'key': 'c0',
        'label': 'X',
        'type': 'text',
      }).toJson().containsKey('hint'),
      isFalse,
    );
  });

  test('editing columns keeps a hint while its column keeps its type', () {
    const before = [
      PlanningTableColumn(
        key: 'c0',
        label: 'Item',
        type: PlanningColumnType.text,
        hint: 'Headphones',
      ),
      PlanningTableColumn(
        key: 'c2',
        label: 'Where',
        type: PlanningColumnType.text,
        hint: 'Shop or website',
      ),
    ];
    final after = planningColumnsKeepingHints(before, const [
      PlanningTableColumn(
        key: 'c0',
        label: 'Thing',
        type: PlanningColumnType.text,
      ),
      PlanningTableColumn(
        key: 'c2',
        label: 'Where',
        type: PlanningColumnType.money,
      ),
      PlanningTableColumn(
        key: 'c3',
        label: 'New',
        type: PlanningColumnType.text,
      ),
    ]);
    expect(
      [for (final c in after) c.hint],
      ['Headphones', null, null],
      reason: 'renamed keeps it; a new type drops it; a new column has none',
    );
  });

  test('money hints follow the currency', () {
    expect(planningMoneyHint('GHS'), '0.00');
    expect(planningMoneyHint('JPY'), '0');
  });

  testWidgets(
    'a new table row: the columns\' hints, 0.00 for money, 0 for a number',
    (t) async {
      await _open(t, [_wishlist]);
      await t.tap(find.text('Add row'));
      await t.pumpAndSettle();
      expect(_hint('Item', 'Headphones'), findsOneWidget);
      expect(_hint('Where to buy', 'Shop or website'), findsOneWidget);
      expect(_hint('Price', '0.00'), findsOneWidget);
      expect(_hint('How many', '0'), findsOneWidget);
    },
  );

  testWidgets('a new expense', (t) async {
    await _open(t, [fakeBlockJson(id: 'x', type: 'expenses')]);
    await t.tap(find.text('Add expense'));
    await t.pumpAndSettle();
    expect(_hint('What for', 'Dinner, taxi, tickets…'), findsOneWidget);
    expect(_hint('Amount', '0.00'), findsOneWidget);
  });

  testWidgets('setting a budget', (t) async {
    await _open(t, [
      {
        ...fakeBlockJson(id: 'b', type: 'budget'),
        'computed': {'spent_minor': 0, 'other_currencies': []},
      },
    ]);
    await t.tap(find.text('Set budget'));
    await t.pumpAndSettle();
    expect(_hint('Budget', '500.00'), findsOneWidget);
  });

  testWidgets('a checklist item: an example item and sections', (t) async {
    await _open(t, [
      fakeBlockJson(id: 'c', items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]),
    ]);
    await t.tap(find.text('Tomatoes'));
    await t.pumpAndSettle();
    expect(_hint('Section (optional)', 'Produce, Dairy…'), findsOneWidget);
    await t.enterText(find.widgetWithText(AppTextFormField, 'Item'), '');
    await t.pump();
    expect(_hint('Item', 'Milk'), findsOneWidget);
  });

  testWidgets('progress: what to add, a note, a target', (t) async {
    await _open(t, [
      {
        ...fakeBlockJson(
          id: 'p',
          type: 'progress',
          payload: {'mode': 'numeric', 'unit': 'money'},
        ),
        'computed': {'mode': 'numeric', 'current': 0},
      },
    ]);
    await t.tap(find.text('Add to it'));
    await t.pumpAndSettle();
    expect(_hint('Amount', '50.00'), findsOneWidget);
    expect(_hint('Note (optional)', 'Birthday money'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.text('Set target'));
    await t.pumpAndSettle();
    expect(_hint('Target', '1,000.00'), findsOneWidget);
  });

  testWidgets('a new plan', (t) async {
    final g = FakePlanningGateway({
      'list_planning_entries': (_) => {'entries': [], 'next_cursor': null},
      'mark_planning_category_seen': (_) => {'seen_at': '2026-10-18T09:00:00Z'},
    });
    await t.pumpWidget(
      planningTestApp(
        g,
        PlanningCategoryScreen(
          relationshipId: 'r1',
          category: PlanningCategory.fromJson(
            fakeCategoryJson(id: 'c1', seedKey: 'trips', name: 'Trips'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('New plan'));
    await t.pumpAndSettle();
    expect(_hint('Title', 'Lisbon in May'), findsOneWidget);
  });
}
