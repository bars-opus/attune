// Which blocks sit in a card. Content blocks (date, table, photos, link,
// place) have one only while empty — once filled they read as part of the
// note. Tools (expenses, budget, countdown, checklist, progress, date poll,
// dual clock) always have one. Text never does.
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

Future<bool> _inCard(WidgetTester t, Map<String, dynamic> block) async {
  await t.pumpWidget(
    planningTestApp(
      FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [block]),
      }),
      const PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1'),
    ),
  );
  await t.pumpAndSettle();
  final at = find.byKey(ValueKey('block-${block['id']}'));
  expect(at, findsOneWidget, reason: '${block['block_type']} is on screen');
  return find
      .descendant(of: at, matching: find.byType(CardInkWell))
      .evaluate()
      .isNotEmpty;
}

Map<String, dynamic> _b(
  String type, {
  Map<String, dynamic>? payload,
  String? dateStart,
  List<Map<String, dynamic>> items = const [],
  Map<String, dynamic>? computed,
}) => {
  ...fakeBlockJson(
    id: 'b-$type',
    type: type,
    payload: payload,
    dateStart: dateStart,
    items: items,
  ),
  if (computed != null) 'computed': computed,
};

const _cols = {
  'columns': [
    {'key': 'c0', 'label': 'Day', 'type': 'text'},
  ],
};

void main() {
  group('a content block has a card only while empty', () {
    for (final (name, empty, filled) in [
      ('a date', _b('date'), _b('date', dateStart: '2026-12-01')),
      (
        'a table',
        _b('table', payload: _cols),
        _b(
          'table',
          payload: _cols,
          items: [
            {
              ...fakeItemJson(id: 'r1'),
              'cells': {'c0': 'Mon'},
            },
          ],
        ),
      ),
      (
        'photos',
        _b('photo', payload: {'paths': []}),
        _b(
          'photo',
          payload: {
            'paths': ['r1/e1/a.jpg'],
          },
        ),
      ),
      (
        'a link',
        _b('link'),
        _b('link', payload: {'url': 'https://example.com'}),
      ),
      (
        'a place',
        _b('place'),
        _b('place', payload: {'name': 'Accra Mall', 'lat': 5.62, 'lng': -0.17}),
      ),
    ]) {
      testWidgets(
        '$name: a card while empty',
        (t) async => expect(await _inCard(t, empty), isTrue),
      );
      testWidgets(
        '$name: no card once filled',
        (t) async => expect(await _inCard(t, filled), isFalse),
      );
    }
  });

  group('a tool always has its card, filled or not', () {
    for (final (name, block) in [
      (
        'expenses',
        _b(
          'expenses',
          items: [
            {
              ...fakeItemJson(id: 'x1', text: 'Taxi'),
              'amount_minor': 1500,
              'currency': 'GHS',
              'paid_by': 'u-a',
            },
          ],
        ),
      ),
      (
        'a budget',
        _b('budget', computed: {'spent_minor': 0, 'other_currencies': []}),
      ),
      ('a countdown', _b('countdown', computed: {'target_date': '2026-12-01'})),
      (
        'a checklist',
        _b('checklist', items: [fakeItemJson(id: 'i1', text: 'Milk')]),
      ),
      (
        'a progress bar',
        _b(
          'progress',
          payload: {'mode': 'numeric'},
          computed: {'mode': 'numeric', 'current': 0},
        ),
      ),
    ]) {
      testWidgets(name, (t) async => expect(await _inCard(t, block), isTrue));
    }
  });

  testWidgets('text never has a card', (t) async {
    expect(
      await _inCard(
        t,
        _b(
          'text',
          payload: {
            'delta': [
              {'insert': 'Hello\n'},
            ],
          },
        ),
      ),
      isFalse,
    );
  });
}
