import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('animate:false renders child immediately at full opacity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SettleIn(animate: false, child: Text('hi')),
    ));
    expect(find.text('hi'), findsOneWidget);
    final opacity = tester.widget<FadeTransition>(
      find.byType(FadeTransition),
    );
    expect(opacity.opacity.value, 1.0);
  });

  testWidgets('reduce-motion renders end-state without a running animation',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: SettleIn(child: Text('hi'))),
    ));
    await tester.pump(); // no need to settle; should already be at end-state
    final opacity = tester.widget<FadeTransition>(
      find.byType(FadeTransition),
    );
    expect(opacity.opacity.value, 1.0);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('animate:true starts hidden and ends visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SettleIn(child: Text('hi')),
    ));
    final startOpacity =
        tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
    expect(startOpacity, lessThan(1.0));
    await tester.pumpAndSettle();
    final endOpacity =
        tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
    expect(endOpacity, 1.0);
  });
}
