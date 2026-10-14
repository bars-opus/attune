import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart' show withScreenUtil;

void main() {
  testWidgets('a custom empty state shows the icon it is given', (tester) async {
    await tester.pumpWidget(withScreenUtil(const MaterialApp(
      home: Scaffold(
        body: EmptyStateWidget(type: EmptyStateType.custom, icon: Icons.flight_takeoff_rounded, title: 'No trips yet'),
      ),
    )));
    expect(find.byIcon(Icons.flight_takeoff_rounded), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);
  });

  testWidgets('a custom empty state with no icon still shows none', (tester) async {
    await tester.pumpWidget(withScreenUtil(const MaterialApp(
      home: Scaffold(body: EmptyStateWidget(type: EmptyStateType.custom, title: 'Nothing')),
    )));
    expect(find.byType(Icon), findsNothing);
  });
}
