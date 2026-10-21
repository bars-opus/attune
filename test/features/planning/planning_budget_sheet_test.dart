import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/charts/arc_gauge.dart';
import 'package:attune/core/widgets/circular_documentation_container.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attune/features/planning/presentation/widgets/planning_progress_bar.dart';
import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _budget({int? target, int spent = 3000}) => {
      ...fakeBlockJson(id: 'bud', type: 'budget', payload: {'title': 'Budget'}),
      'target_minor': target,
      'target_currency': 'GHS',
      'computed': {'spent_minor': spent, 'other_currencies': []},
    };

FakePlanningGateway _gateway({int? target, int spent = 3000}) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [_budget(target: target, spent: spent)]),
    });

void main() {
  testWidgets("Set budget opens the app's sheet: header, neutral colour, Done saves", (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block_target'] = (p) => _budget(target: p['p_target_minor'] as int);
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set budget'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget, reason: 'BottomSheetUtils');
    expect(find.widgetWithText(BottomSheetHeader, 'Set budget'), findsOneWidget);
    final sheet = tester.widget<CircularDocumentationContainer>(find.byType(CircularDocumentationContainer));
    expect(sheet.color, Theme.of(tester.element(find.byType(BottomSheetHeader))).colorScheme.neutral);

    await tester.enterText(find.widgetWithText(AppTextFormField, 'Budget'), '250');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetHeader), findsNothing, reason: 'closed once saved');
    expect(g.callsTo('update_planning_block_target').single['p_target_minor'], 25000);
  });

  testWidgets('Done with no amount, or one it cannot read, keeps the sheet and says why', (tester) async {
    final g = _gateway();
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetHeader), findsOneWidget);
    expect(find.text('Enter an amount like 500'), findsOneWidget);
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Budget'), '1.2.3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetHeader), findsOneWidget);
    expect(g.callsTo('update_planning_block_target'), isEmpty);
  });

  ArcGaugePainter gauge(WidgetTester tester) => tester
      .widget<CustomPaint>(find.descendant(of: find.byType(ArcGauge), matching: find.byType(CustomPaint)).first)
      .painter! as ArcGaugePainter;

  testWidgets('a set budget shows as a gauge: what is left in the middle, the track a light shade of the fill',
      (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(target: 10000), _screen));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byType(ArcGauge))).colorScheme;
    expect(find.byType(LinearProgressIndicator), findsNothing, reason: 'the gauge replaces the bar');
    expect(find.text('${formatPlanningMoney(7000, 'GHS')} left'), findsOneWidget);
    expect(find.text('of ${formatPlanningMoney(10000, 'GHS')}'), findsOneWidget);
    expect(gauge(tester).value, moreOrLessEquals(0.3));
    expect(gauge(tester).fill, scheme.primary);
    expect(gauge(tester).track, scheme.primary.withValues(alpha: 0.18));
  });

  testWidgets('over budget, the gauge is full and in the error colour', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(target: 2000, spent: 3000), _screen));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byType(ArcGauge))).colorScheme;
    expect(find.text('${formatPlanningMoney(1000, 'GHS')} over budget'), findsOneWidget);
    expect(gauge(tester).value, 1);
    expect(gauge(tester).fill, scheme.error);
    expect(gauge(tester).track, scheme.error.withValues(alpha: 0.18));
  });

  testWidgets('with no budget set there is no gauge, just what is spent', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.byType(ArcGauge), findsNothing);
    expect(find.textContaining('No budget set'), findsOneWidget);
  });

  testWidgets("the progress block's bar uses the same light primary track", (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                {
                  ...fakeBlockJson(id: 'p', type: 'progress', payload: {'title': 'Savings', 'mode': 'numeric', 'unit': 'count'}),
                  'target_minor': 10,
                  'computed': {'mode': 'numeric', 'current': 4},
                },
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    // The goal bar (PlanningProgressBar): the track is the same light primary.
    final bar = find.byType(PlanningProgressBar);
    final scheme = Theme.of(tester.element(bar)).colorScheme;
    final colours = [
      for (final e in find.descendant(of: bar, matching: find.byType(ColoredBox)).evaluate()) (e.widget as ColoredBox).color,
    ];
    expect(colours, contains(scheme.primary.withValues(alpha: 0.18)));
    expect(colours, contains(scheme.primary));
  });
}
