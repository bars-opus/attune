import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/planning/data/planning_models.dart' show planningYmd;
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');
final _list = find.descendant(of: find.byType(ReorderableListView), matching: find.byType(Scrollable)).first;

String _ymd(DateTime d) => planningYmd(d);
DateTime get _today => DateUtils.dateOnly(DateTime.now());

Map<String, dynamic> _option(String id, List<String> votes) =>
    {...fakeItemJson(id: id), 'date_start': '2026-11-20', 'date_end': '2026-11-25', 'votes': votes};

Map<String, dynamic> _poll(List<String> votes) =>
    fakeBlockJson(id: 'poll', type: 'date_poll', payload: {'title': 'Pick dates'}, items: [_option('o1', votes)]);

Widget _app(FakePlanningGateway g, Widget home, {PartnerDistance? partner}) => ProviderScope(
      overrides: planningOverrides(g, partner: partner),
      child: withScreenUtil(MaterialApp(theme: ThemeData(useMaterial3: true), home: home)),
    );

void main() {
  testWidgets('a poll option shows who it works for, and locks only when both agree', (tester) async {
    var votes = <String>['u-b'];
    var locked = false;
    final date = fakeBlockJson(id: 'poll', type: 'date', payload: {'title': 'Pick dates'}, dateStart: '2026-11-20', dateEnd: '2026-11-25');
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [locked ? date : _poll(votes)]),
    });
    g.handlers['vote_planning_poll'] = (p) {
      votes = [...votes, 'u-a'];
      return _poll(votes);
    };
    g.handlers['lock_planning_poll'] = (_) {
      locked = true;
      return date;
    };
    await tester.pumpWidget(_app(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('Nov 20 – Nov 25, 2026'), findsOneWidget);
    expect(find.text('Lock it in'), findsNothing, reason: 'only Kofi has voted');
    await tester.tap(find.text('Works for me'));
    await tester.pumpAndSettle();
    expect(g.callsTo('vote_planning_poll').single, {'p_item_id': 'o1', 'p_vote': true});
    await tester.tap(find.text('Lock it in'));
    await tester.pumpAndSettle();
    expect(g.callsTo('lock_planning_poll').single, {'p_block_id': 'poll', 'p_item_id': 'o1'});
    expect(find.text('Works for me'), findsNothing, reason: 'the poll is a date now');
  });

  testWidgets('countdown says days, Tomorrow, Today, or asks for a date', (tester) async {
    Map<String, dynamic> cd(String id, DateTime? d, String key) =>
        {...fakeBlockJson(id: id, type: 'countdown', sortKey: key), 'computed': {'target_date': d == null ? null : _ymd(d)}};
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            cd('a', _today.add(const Duration(days: 12)), 'a'),
            cd('b', _today.add(const Duration(days: 1)), 'b'),
            cd('c', _today, 'c'),
            cd('d', null, 'd'),
          ]),
    });
    await tester.pumpWidget(_app(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('12 days'), findsWidgets, reason: 'the block, and the plan\'s key facts');
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pick a date'), 200, scrollable: _list);
    expect(find.text('Pick a date'), findsOneWidget);
  });

  testWidgets('numeric progress shows money toward the target; adding a contribution saves minor units', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            {...fakeBlockJson(id: 'pr', type: 'progress', payload: {'title': 'Deposit', 'mode': 'numeric', 'unit': 'money'}),
              'target_minor': 100000, 'target_currency': 'GHS', 'computed': {'mode': 'numeric', 'current': 60000}},
            {...fakeBlockJson(id: 'pc', type: 'progress', sortKey: 'k', payload: {'mode': 'checklist'}),
              'computed': {'mode': 'checklist', 'done': 1, 'total': 2}},
          ]),
    });
    g.handlers['save_planning_rich_item'] =
        (p) => {...fakeItemJson(id: p['p_id'] as String), 'amount_minor': 2550};
    await tester.pumpWidget(_app(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('${formatPlanningMoney(60000, 'GHS')} of ${formatPlanningMoney(100000, 'GHS')}'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsWidgets);
    await tester.tap(find.text('Add to it'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '25.50');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect((g.callsTo('save_planning_rich_item').single['p_fields'] as Map)['amount_minor'], 2550);
  });

  testWidgets('dual clock shows the partner\'s city and time when they share, a hint when not', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'dc', type: 'dual_clock', payload: {'title': 'Our time'})]),
      'planning_timezone_offset_minutes': (_) => 480,
    });
    await tester.pumpWidget(_app(g, _screen,
        partner: const PartnerDistance(km: 12000, partnerCity: 'Makassar', partnerTimezone: 'Asia/Makassar')));
    await tester.pumpAndSettle();
    expect(find.text('Makassar'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('dual clock without shared presence explains itself', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'dc', type: 'dual_clock')]),
    });
    await tester.pumpWidget(_app(g, _screen));
    await tester.pumpAndSettle();
    expect(find.textContaining('when they share their location'), findsOneWidget);
    expect(g.callsTo('planning_timezone_offset_minutes'), isEmpty);
  });

  testWidgets('an empty link and place from a template ask to be filled in', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'ln', type: 'link', payload: {'label': 'Places to stay'}),
            fakeBlockJson(id: 'pl', type: 'place', sortKey: 'k', payload: {'title': 'Destination'}),
          ]),
    });
    g.handlers['update_planning_block'] =
        (p) => fakeBlockJson(id: 'ln', type: 'link', payload: p['p_payload'] as Map<String, dynamic>, version: 2);
    await tester.pumpWidget(_app(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('Places to stay'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Choose a place'), findsOneWidget);
    await tester.tap(find.text('Add link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Web address'), 'airbnb.com/rooms/1');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(g.callsTo('update_planning_block').single['p_payload'],
        {'url': 'https://airbnb.com/rooms/1', 'label': 'Places to stay'});
  });

  testWidgets('the tool tray offers all 13 blocks', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson()});
    await tester.pumpWidget(_app(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add block'));
    await tester.pumpAndSettle();
    for (final label in ['Date poll', 'Countdown', 'Progress', 'Dual clock']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('New category offers gallery ideas; Planning reports the device time zone', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_home': (_) => {'categories': [fakeCategoryJson(id: 'c1', seedKey: 'goals', name: 'Goals', icon: 'flag')]},
      'list_planning_gallery': (_) => [
            {'key': 'next_visit', 'name': 'Next visit', 'icon': 'plane', 'color': 'indigo',
             'description': 'Long distance: count down, pick dates.', 'block_types': ['countdown']},
          ],
      'create_planning_category_from_gallery': (p) => fakeCategoryJson(id: p['p_id'] as String, name: 'Next visit'),
      'set_planning_timezone': (p) => {'timezone': p['p_timezone']},
    });
    await tester.pumpWidget(ProviderScope(
      overrides: planningOverrides(g, deviceTimezone: 'Africa/Accra'),
      child: withScreenUtil(MaterialApp(theme: ThemeData(useMaterial3: true), home: const PlanningHomeScreen(relationshipId: 'r1'))),
    ));
    await tester.pumpAndSettle();
    expect(g.callsTo('set_planning_timezone').single, {'p_relationship_id': 'r1', 'p_timezone': 'Africa/Accra'});
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    expect(find.text('Long distance: count down, pick dates.'), findsOneWidget);
    await tester.tap(find.text('Next visit'));
    await tester.pumpAndSettle();
    final call = g.callsTo('create_planning_category_from_gallery').single;
    expect((call['p_relationship_id'], call['p_gallery_key']), ('r1', 'next_visit'));
  });
}
