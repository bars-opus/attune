import 'package:attune/features/planning/data/planning_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';

void main() {
  test('P3 block types round-trip their wire names', () {
    for (final wire in ['table', 'photo', 'link', 'place', 'expenses', 'budget']) {
      final type = planningBlockTypeFromWire(wire);
      expect(type, isNot(PlanningBlockType.unsupported), reason: wire);
      expect(planningBlockTypeToWire(type), wire);
    }
  });

  test('table columns, photo paths, link preview and place read from the payload', () {
    final table = PlanningBlock.fromJson(fakeBlockJson(id: 't', type: 'table', payload: {
      'title': 'Packing',
      'columns': [
        {'key': 'c0', 'label': 'Item', 'type': 'text'},
        {'key': 'c1', 'label': 'Cost', 'type': 'money'},
      ],
    }, items: [
      {...fakeItemJson(id: 'r1'), 'cells': {'c0': 'Tent', 'c1': 4500}},
    ]));
    expect(table.columns.map((c) => (c.key, c.type)), [('c0', PlanningColumnType.text), ('c1', PlanningColumnType.money)]);
    expect(table.items.single.cells, {'c0': 'Tent', 'c1': 4500});

    final photo = PlanningBlock.fromJson(fakeBlockJson(id: 'p', type: 'photo', payload: {'paths': ['r/e/a.jpg']}));
    expect(photo.photoPaths, ['r/e/a.jpg']);

    final link = PlanningBlock.fromJson(fakeBlockJson(id: 'l', type: 'link', payload: {
      'url': 'https://villa.example/ubud', 'label': 'Villa',
      'preview': {'status': 'ok', 'title': 'Ubud', 'host': 'villa.example', 'image_path': 'r/e/preview-1.jpg'},
    }));
    expect(link.linkUrl, 'https://villa.example/ubud');
    expect(link.linkPreview!.isOk, isTrue);
    expect(link.linkPreview!.imagePath, 'r/e/preview-1.jpg');

    final place = PlanningBlock.fromJson(fakeBlockJson(id: 'pl', type: 'place',
        payload: {'name': 'Ubud', 'address': 'Bali', 'lat': -8.5, 'lng': 115.26}));
    expect(place.place!.hasCoordinates, isTrue);
    expect(PlanningBlock.fromJson(fakeBlockJson(id: 'x', type: 'place', payload: {'name': 'Home'})).place!.hasCoordinates,
        isFalse);
  });

  test('expense lines, budget computed totals and the entry split', () {
    final item = PlanningItem.fromJson({
      ...fakeItemJson(id: 'x1', text: 'Villa'),
      'amount_minor': 1001, 'currency': 'USD', 'paid_by': 'u-a', 'split_share_minor': null,
    });
    expect((item.amountMinor, item.currency, item.paidBy, item.splitShareMinor), (1001, 'USD', 'u-a', null));

    final budget = PlanningBlock.fromJson({
      ...fakeBlockJson(id: 'b', type: 'budget'),
      'target_minor': 200000, 'target_currency': 'USD',
      'computed': {'spent_minor': 1001, 'other_currencies': [{'currency': 'IDR', 'minor': 500000}]},
    });
    expect(budget.targetMinor, 200000);
    expect(budget.budget!.spentMinor, 1001);
    expect(budget.budget!.otherCurrencies.single, ('IDR', 500000));

    final detail = PlanningEntryDetail.fromJson(fakeEntryDetailJson());
    expect(detail.entry.split, isNull);
    final withSplit = PlanningEntryDetail.fromJson({
      ...fakeEntryDetailJson(),
      'entry': {
        ...(fakeEntryDetailJson()['entry'] as Map<String, dynamic>),
        'split': {
          'settled_at': null,
          'balances': [{'currency': 'USD', 'minor': 500, 'owed_to': 'u-a', 'owed_by': 'u-b'}],
        },
      },
    });
    final b = withSplit.entry.split!.balances.single;
    expect((b.currency, b.minor, b.owedTo, b.owedBy), ('USD', 500, 'u-a', 'u-b'));
  });
}
