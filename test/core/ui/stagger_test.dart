import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/ui/motion/stagger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wraps each child in a SettleIn', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stagger(children: [
          const Text('a', key: ValueKey('a')),
          const Text('b', key: ValueKey('b')),
          const Text('c', key: ValueKey('c')),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SettleIn), findsNWidgets(3));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('animate:false renders children at rest', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stagger(animate: false, children: [
          const Text('a', key: ValueKey('a')),
          const Text('b', key: ValueKey('b')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });
}
