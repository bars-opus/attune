// test/core/ui/shimmer_test.dart
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('active shimmer wraps the child in a ShaderMask', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Shimmer(child: Text('hi'))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('hi'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the loop
  });

  testWidgets('reduce-motion renders the child plainly (no running sweep)',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: Shimmer(child: Text('hi')))),
    ));
    await tester.pumpAndSettle(); // must not time out (no repeating ticker)
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('inactive renders the child plainly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Shimmer(active: false, child: Text('hi'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
  });
}
