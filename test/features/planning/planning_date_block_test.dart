import 'package:attune/core/widgets/app_countdown.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/planning/presentation/widgets/date_block_view.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway({String? date}) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'd1', type: 'date', payload: {'title': 'When'}, dateStart: date),
          ]),
    });

InfoRowWidget _row(WidgetTester tester, String title) =>
    tester.widget<InfoRowWidget>(find.ancestor(of: find.text(title), matching: find.byType(InfoRowWidget)));

void main() {
  testWidgets('date choices are single-line InfoRowWidget rows; the top one has the divider', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(_row(tester, 'A single date').showDivider, isTrue);
    expect(_row(tester, 'A start and an end date').showDivider, isFalse, reason: 'the last row');
    expect(find.text('Remove the date'), findsNothing, reason: 'nothing to clear yet');
    expect(find.byTooltip('Change date'), findsNothing);
    expect(find.text('One day'), findsNothing, reason: 'one line per row now');
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.tap(find.text('A single date'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('with a date set it sits inline in the note: no card, no heading, the date in primary with its countdown', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(date: '2026-11-20'), _screen));
    await tester.pumpAndSettle();
    final block = find.byType(DateBlockView);
    expect(find.ancestor(of: block, matching: find.byType(CardInkWell)), findsNothing);
    expect(find.descendant(of: block, matching: find.text('When')), findsNothing, reason: 'no heading');
    expect(find.text('A single date'), findsNothing);
    expect(find.byTooltip('Change date'), findsNothing, reason: 'the date itself is the button');
    final date = find.descendant(of: block, matching: find.text('Nov 20, 2026'));
    expect(tester.widget<Text>(date).style?.color, Theme.of(tester.element(date)).colorScheme.primary);
    expect(find.descendant(of: block, matching: find.byType(AppCountdown)), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AppCountdown)).dy, greaterThan(tester.getTopLeft(date).dy),
        reason: 'the countdown below the date');
    expect(find.byTooltip('Options for When'), findsOneWidget, reason: 'the more menu stays at the right');
  });

  testWidgets('tapping the date opens the app sheet with the date choices; Remove clears the date', (tester) async {
    final g = _gateway(date: '2026-11-20');
    g.handlers['update_planning_block'] =
        (p) => fakeBlockJson(id: 'd1', type: 'date', payload: {'title': 'When'}, version: 2);
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DateBlockView), matching: find.text('Nov 20, 2026')));
    await tester.pumpAndSettle();
    for (final label in ['A single date', 'A start and an end date', 'Remove the date']) {
      expect(find.ancestor(of: find.text(label), matching: find.byType(InfoRowWidget)), findsOneWidget, reason: label);
    }
    await tester.ensureVisible(find.text('Remove the date')); // the sheet scrolls on short screens
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove the date'));
    await tester.pumpAndSettle();
    final call = g.callsTo('update_planning_block').single;
    expect((call['p_date_start'], call['p_date_end']), (null, null));
  });

  testWidgets('choosing A single date in the sheet opens the date picker', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(date: '2026-11-20'), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DateBlockView), matching: find.text('Nov 20, 2026')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A single date'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('no date yet: the heading says Pick a date, once — no placeholder line under it', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'd1', type: 'date')]),
    });
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    expect(find.text('Pick a date'), findsOneWidget);
    expect(find.text('Date'), findsNothing);
    final heading = tester.widget<Text>(find.text('Pick a date'));
    final ctx = tester.element(find.text('Pick a date'));
    expect(heading.style?.fontSize, Theme.of(ctx).textTheme.titleSmall?.fontSize, reason: 'a smaller heading');
    expect(heading.style?.fontWeight, FontWeight.w400, reason: 'not bold');
    final divider = find.byType(AppDivider).first;
    expect(tester.getTopLeft(divider).dy, greaterThan(tester.getBottomLeft(find.text('Pick a date')).dy));
    expect(tester.getTopLeft(divider).dy, lessThan(tester.getTopLeft(find.text('A single date')).dy),
        reason: 'the divider sits under the heading, above the choices');
  });

  testWidgets('a titled block keeps its title and drops the placeholder line', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.text('When'), findsOneWidget);
    expect(find.text('Pick a date'), findsNothing);
  });

  testWidgets('a selected date shows a live countdown to it', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(planningTestApp(_gateway(date: ymd(today.add(const Duration(days: 12)))), _screen));
    await tester.pumpAndSettle();
    expect(find.byType(AppCountdown), findsOneWidget);
    expect(find.text('In 12 days'), findsOneWidget);
  });

  testWidgets('no countdown before a date is picked', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.byType(AppCountdown), findsNothing);
  });
}
