import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the requested number of dots', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BreathingDots(count: 3)),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    // Each dot is an AnimatedBuilder-wrapped container; assert 3 dot widgets.
    expect(find.byType(BreathingDots), findsOneWidget);
    expect(
      find.byKey(const ValueKey('breathing_dot_0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('breathing_dot_2')), findsOneWidget);
    // stop the loop so the test can settle
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce-motion renders without a running animation ticker',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: BreathingDots())),
    ));
    // With reduce-motion the dots are static; pumpAndSettle must not time out.
    await tester.pumpAndSettle();
    expect(find.byType(BreathingDots), findsOneWidget);
  });
}
