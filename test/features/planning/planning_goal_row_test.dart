import 'package:attune/features/planning/data/models/planning_goal_model.dart';
import 'package:attune/features/planning/presentation/widgets/planning_goal_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart';

PlanningGoalModel _goal({
  int childCount = 2,
  int completedChildCount = 1,
  DateTime? completedAt,
}) => PlanningGoalModel(
  id: 'g1', title: 'Save for the trip', note: null,
  completedAt: completedAt, updatedAt: DateTime(2026, 9, 14),
  childCount: childCount, completedChildCount: completedChildCount,
);

void main() {
  testWidgets('shows the title and a progress fraction, not a raw percentage string only', (
    tester,
  ) async {
    await tester.pumpWidget(withScreenUtil(MaterialApp(
      home: Scaffold(
        body: PlanningGoalRow(goal: _goal(), onTap: () {}),
      ),
    )));
    expect(find.text('Save for the trip'), findsOneWidget);
    expect(find.textContaining('1'), findsOneWidget); // 1 of 2 somewhere
    expect(find.textContaining('2'), findsOneWidget);
  });

  testWidgets('a completed goal shows a completed visual state', (tester) async {
    await tester.pumpWidget(withScreenUtil(MaterialApp(
      home: Scaffold(
        body: PlanningGoalRow(
          goal: _goal(childCount: 2, completedChildCount: 2, completedAt: DateTime(2026, 9, 14)),
          onTap: () {},
        ),
      ),
    )));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('tapping the row calls onTap exactly once', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(withScreenUtil(MaterialApp(
      home: Scaffold(
        body: PlanningGoalRow(goal: _goal(), onTap: () => tapCount++),
      ),
    )));
    await tester.tap(find.byType(PlanningGoalRow));
    expect(tapCount, 1);
  });
}
