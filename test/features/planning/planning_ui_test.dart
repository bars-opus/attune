import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/sql_definitions.dart';
import 'support/planning_test_app.dart';

List<String> _sqlArray(String fn) {
  final body = RegExp(r'ARRAY\[([\s\S]*?)\]').firstMatch(newestSqlFunctionBody(fn))!.group(1)!;
  return RegExp(r"'([a-z]+)'").allMatches(body).map((m) => m.group(1)!).toList();
}

void main() {
  test('icon and colour keys match the server allow-lists exactly', () {
    expect(planningIconKeys, _sqlArray('planning_v2_icons'));
    expect(planningColorKeys, _sqlArray('planning_v2_colors'));
    for (final k in planningIconKeys) {
      expect(planningIcon(k), isNot(Icons.folder_rounded), reason: 'icon $k unmapped');
    }
  });

  test('highlight palette covers every rich-text token in both themes', () {
    for (final b in Brightness.values) {
      expect(planningHighlightPalette(b).keys.toSet(), {'yellow', 'green', 'blue', 'pink', 'purple'});
    }
  });

  test('date ranges format for humans', () {
    expect(formatPlanningRange(null, null), 'Pick a date');
    expect(formatPlanningRange(DateTime(2026, 3, 3), null), 'Mar 3, 2026');
    expect(formatPlanningRange(DateTime(2026, 3, 3), DateTime(2026, 3, 13)), 'Mar 3 – Mar 13, 2026');
    expect(formatPlanningRange(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 'Dec 30, 2026 – Jan 2, 2027');
  });

  testWidgets('planningConfirm: confirm returns true; tapping outside returns false (no hang)', (tester) async {
    bool? result;
    await tester.pumpWidget(planningTestApp(FakePlanningGateway(), Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => result = await planningConfirm(context,
                title: 'Delete?', message: 'Gone for good.', confirmText: 'Delete', destructive: true),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  test('the Conversations line for each Planning summary', () {
    expect(planningSummaryLine(null), 'Start planning together');
    expect(planningSummaryLine(PlanningSummary(kind: PlanningSummaryKind.overdue, entryId: 'e',
        title: 'Eggs', contextDate: DateTime(2026, 11, 8))), 'Eggs was due Nov 8');
    expect(planningSummaryLine(PlanningSummary(kind: PlanningSummaryKind.upcoming, entryId: 'e',
        title: 'Bali', contextDate: DateTime(2026, 11, 28))), 'Bali · Nov 28');
    expect(planningSummaryLine(const PlanningSummary(kind: PlanningSummaryKind.recent, entryId: 'e',
        title: 'Saturday shop', contextDate: null)), 'Saturday shop');
  });
}

