import 'dart:io';

import 'package:attune/features/planning/v2/presentation/planning_v2_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

List<String> _sqlArray(String fn) {
  final sql = File('supabase/migrations/20261012200100_planning_v2_helpers.sql').readAsStringSync();
  final body = RegExp('FUNCTION public.$fn\\(\\)[\\s\\S]*?ARRAY\\[([\\s\\S]*?)\\]').firstMatch(sql)!.group(1)!;
  return RegExp(r"'([a-z]+)'").allMatches(body).map((m) => m.group(1)!).toList();
}

void main() {
  test('icon and colour keys match the server allow-lists exactly', () {
    expect(planningV2IconKeys, _sqlArray('planning_v2_icons'));
    expect(planningV2ColorKeys, _sqlArray('planning_v2_colors'));
    for (final k in planningV2IconKeys) {
      expect(planningV2Icon(k), isNot(Icons.folder_rounded), reason: 'icon $k unmapped');
    }
  });

  test('highlight palette covers every rich-text token in both themes', () {
    for (final b in Brightness.values) {
      expect(planningV2HighlightPalette(b).keys.toSet(), {'yellow', 'green', 'blue', 'pink', 'purple'});
    }
  });

  test('date ranges format for humans', () {
    expect(formatPlanningRange(null, null), 'Pick a date');
    expect(formatPlanningRange(DateTime(2026, 3, 3), null), 'Mar 3, 2026');
    expect(formatPlanningRange(DateTime(2026, 3, 3), DateTime(2026, 3, 13)), 'Mar 3 – Mar 13, 2026');
    expect(formatPlanningRange(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), 'Dec 30, 2026 – Jan 2, 2027');
  });

  testWidgets('planningV2Confirm: confirm returns true; tapping outside returns false (no hang)', (tester) async {
    bool? result;
    await tester.pumpWidget(planningV2TestApp(FakePlanningGateway(), Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => result = await planningV2Confirm(context,
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
}
