// A goal on screen: a stepped bar that fills (one segment a step), a pace
// line — will we make it? — and the date it is due by, choosable.
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/planning_progress_bar.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:flutter/material.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');
final _today = DateUtils.dateOnly(DateTime.now());
String _ymd(DateTime d) => planningYmd(d);

Map<String, dynamic> _checklistGoal({
  required int done,
  required int total,
  int? dueIn,
  int startedDaysAgo = 10,
  String? dateId = 'd1',
}) => {
  ...fakeBlockJson(
    id: 'g',
    type: 'progress',
    payload: {'mode': 'checklist', if (dateId != null) 'date_block_id': dateId},
  ),
  'computed': {
    'mode': 'checklist',
    'done': done,
    'total': total,
    'checklist_block_id': 'k1',
    'date_block_id': dateId,
    'target_date':
        dueIn == null ? null : _ymd(_today.add(Duration(days: dueIn))),
    'started_on': _ymd(_today.subtract(Duration(days: startedDaysAgo))),
  },
};

Map<String, dynamic> _moneyGoal({
  required int current,
  required int target,
  required int dueIn,
}) => {
  ...fakeBlockJson(
    id: 'g',
    type: 'progress',
    payload: {'mode': 'numeric', 'unit': 'money', 'date_block_id': 'd1'},
  ),
  'target_minor': target,
  'target_currency': 'GHS',
  'computed': {
    'mode': 'numeric',
    'current': current,
    'date_block_id': 'd1',
    'target_date': _ymd(_today.add(Duration(days: dueIn))),
    'started_on': _ymd(_today.subtract(const Duration(days: 10))),
  },
};

final _targetDate = fakeBlockJson(
  id: 'd1',
  type: 'date',
  payload: {'title': 'Target date'},
  dateStart: '2027-01-01',
);
final _testDrive = fakeBlockJson(
  id: 'd2',
  type: 'date',
  payload: {'title': 'Test drive'},
  dateStart: '2026-11-20',
);

FakePlanningGateway _gateway(List<Map<String, dynamic>> blocks) =>
    FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks),
      'update_planning_block':
          (p) => {
            ...blocks.firstWhere((b) => b['id'] == p['p_id']),
            'payload': p['p_payload'],
            'version': 2,
          },
    });

Future<FakePlanningGateway> _open(
  WidgetTester t,
  List<Map<String, dynamic>> blocks, {
  bool reduce = false,
}) async {
  final g = _gateway(blocks);
  // The real screen's data, with only reduce motion changed (a bare
  // MediaQueryData has no size, and sheets size themselves from it).
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(t.view).copyWith(disableAnimations: reduce),
      child: planningTestApp(g, _screen),
    ),
  );
  await t.pumpAndSettle();
  return g;
}

PlanningProgressBar _bar(WidgetTester t) =>
    t.widget<PlanningProgressBar>(find.byType(PlanningProgressBar));

void main() {
  test('the server\'s pace inputs reach the goal', () {
    final p =
        PlanningBlock.fromJson(
          _checklistGoal(done: 2, total: 5, dueIn: 30),
        ).progress!;
    expect(p.dateBlockId, 'd1');
    expect(p.targetDate, _today.add(const Duration(days: 30)));
    expect(p.startedOn, _today.subtract(const Duration(days: 10)));
  });

  testWidgets('a few steps: one segment each', (t) async {
    await _open(t, [_checklistGoal(done: 2, total: 5, dueIn: 30)]);
    expect(_bar(t).segments, 5);
    expect(_bar(t).fraction, 2 / 5);
  });

  testWidgets('many steps: one smooth bar', (t) async {
    await _open(t, [_checklistGoal(done: 4, total: 20, dueIn: 30)]);
    expect(_bar(t).segments, isNull);
  });

  testWidgets('a money goal: a smooth bar with quarter marks', (t) async {
    await _open(t, [_moneyGoal(current: 40000, target: 100000, dueIn: 60)]);
    expect(_bar(t).segments, isNull);
    expect(_bar(t).milestones, isTrue);
  });

  testWidgets(
    'the bar fills in when the goal shows; at once with reduce motion',
    (t) async {
      final g = _gateway([_checklistGoal(done: 3, total: 4, dueIn: 30)]);
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final state = t.state<PlanningProgressBarState>(
        find.byType(PlanningProgressBar),
      );
      expect(state.shown, inExclusiveRange(0, 0.75), reason: 'filling');
      await t.pumpAndSettle();
      expect(state.shown, 0.75);
      await _open(t, [
        _checklistGoal(done: 3, total: 4, dueIn: 30),
      ], reduce: true);
      expect(
        t
            .state<PlanningProgressBarState>(find.byType(PlanningProgressBar))
            .shown,
        0.75,
      );
    },
  );

  group('the pace line', () {
    testWidgets('on track', (t) async {
      await _open(t, [
        _targetDate,
        _checklistGoal(done: 4, total: 10, dueIn: 18),
      ]);
      expect(
        find.text(
          'On track\nfor ${MyDateFormat.toDateShort(_today.add(const Duration(days: 18)))}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ahead', (t) async {
      await _open(t, [
        _targetDate,
        _checklistGoal(done: 5, total: 10, dueIn: 60),
      ]);
      expect(
        find.text(
          'Ahead of pace\ndone by ${MyDateFormat.toDateShort(_today.add(const Duration(days: 10)))} at this rate',
        ),
        findsOneWidget,
      );
    });

    testWidgets('behind, in steps', (t) async {
      await _open(t, [
        _targetDate,
        _checklistGoal(done: 2, total: 10, dueIn: 28),
      ]);
      expect(
        find.text('A little behind\nabout 2 steps a week would get you there'),
        findsOneWidget,
      );
    });

    testWidgets('behind, in money', (t) async {
      // 400 of 1,000 in 10 days; 600 left by day 14 (two weeks): 300 a week.
      await _open(t, [
        _targetDate,
        _moneyGoal(current: 40000, target: 100000, dueIn: 14),
      ]);
      expect(
        find.text(
          'A little behind\nabout ${formatPlanningMoneyFor(30000)} a week would get you there',
        ),
        findsOneWidget,
      );
    });

    testWidgets('not started', (t) async {
      await _open(t, [
        _targetDate,
        _checklistGoal(done: 0, total: 5, dueIn: 30),
      ]);
      expect(
        find.text('Tick off a first step\nto see your pace'),
        findsOneWidget,
      );
    });

    testWidgets('the day itself', (t) async {
      await _open(t, [
        _targetDate,
        _checklistGoal(done: 3, total: 5, dueIn: 0),
      ]);
      expect(find.text('The date is today\n2 steps to go'), findsOneWidget);
    });

    testWidgets('the date gone', (t) async {
      await _open(t, [
        _targetDate,
        _checklistGoal(done: 3, total: 5, dueIn: -2),
      ]);
      expect(
        find.text('The date has passed\npick a new one when you\'re ready'),
        findsOneWidget,
      );
    });

    testWidgets('no date, no pace line', (t) async {
      await _open(t, [
        _checklistGoal(done: 3, total: 5, dueIn: null, dateId: null),
      ]);
      expect(find.textContaining('pace'), findsNothing);
      expect(find.textContaining('On track'), findsNothing);
    });
  });

  testWidgets('the pace line sits above the goal\'s card, a little larger', (t) async {
    await _open(t, [_targetDate, _checklistGoal(done: 4, total: 10, dueIn: 18)]);
    final line = find.textContaining('On track', findRichText: true);
    expect(line, findsOneWidget);
    expect(find.ancestor(of: line, matching: find.byType(CardInkWell)), findsNothing, reason: 'outside the card');
    final card = find.ancestor(of: find.byType(PlanningProgressBar), matching: find.byType(CardInkWell));
    expect(t.getBottomLeft(line).dy, lessThanOrEqualTo(t.getTopLeft(card).dy), reason: 'above it');
    final text = t.widget<Text>(find.ancestor(of: line, matching: find.byType(Text)).first);
    expect(text.style?.fontSize, Theme.of(t.element(line)).textTheme.bodyMedium?.fontSize);
    // Two lines, then room before the card.
    expect(t.getTopLeft(card).dy - t.getBottomLeft(line).dy, greaterThanOrEqualTo(Spacing.md));
  });

  testWidgets('a medium gap before By, and a divider under it', (t) async {
    await _open(t, [_targetDate, _checklistGoal(done: 2, total: 5, dueIn: 30)]);
    final by = find.widgetWithText(InfoRowWidget, 'By: Target date');
    final count = find.textContaining('of 5 done');
    expect(t.getTopLeft(by).dy - t.getBottomLeft(count).dy, greaterThanOrEqualTo(Spacing.md));
    expect(t.widget<InfoRowWidget>(by).showDivider,
      isTrue,
      reason: 'it marks By off from Tracks under it',
    );
  });

  testWidgets('a money goal: By has its divider, contributions follow', (t) async {
    await _open(t, [_targetDate, _moneyGoal(current: 40000, target: 100000, dueIn: 60)]);
    expect(t.widget<InfoRowWidget>(find.widgetWithText(InfoRowWidget, 'By: Target date')).showDivider, isTrue);
  });

  testWidgets('By: the date it is due by, and another can be chosen', (
    t,
  ) async {
    final g = await _open(t, [
      _targetDate,
      _testDrive,
      _checklistGoal(done: 2, total: 5, dueIn: 30),
    ]);
    final row = find.widgetWithText(InfoRowWidget, 'By: Target date');
    await t.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Clear of the bar at the bottom of the plan.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await t.pumpAndSettle();
    await t.tap(row);
    await t.pumpAndSettle();
    final other = find.descendant(
      of: find.byKey(const ValueKey('planning-block-picker-sheet')),
      matching: find.widgetWithText(InfoRowWidget, 'Test drive'),
    );
    await t.tap(other);
    await t.pumpAndSettle();
    final payload =
        g.callsTo('update_planning_block').single['p_payload'] as Map;
    expect(payload['date_block_id'], 'd2');
    expect(payload['mode'], 'checklist');
  });
}

String formatPlanningMoneyFor(int minor) => formatPlanningMoney(minor, 'GHS');
