import 'package:attune/core/widgets/rolling_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// AnimatedRollingCounter renders each digit as its own Text so it can roll
/// them independently, so the timer is read off the tree in order rather
/// than matched as one string.
String _read(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byType(RollingDuration),
      matching: find.byType(Text),
    ),
  );
  return texts.map((t) => t.data ?? '').join();
}

Widget _wrap(Duration d) =>
    MaterialApp(home: Scaffold(body: Center(child: RollingDuration(value: d))));

void main() {
  testWidgets('under a minute reads as plain seconds', (tester) async {
    await tester.pumpWidget(_wrap(const Duration(seconds: 43)));
    expect(_read(tester), '43');
  });

  testWidgets('past a minute reads as m:ss', (tester) async {
    await tester.pumpWidget(_wrap(const Duration(seconds: 700)));
    expect(_read(tester), '11:40');
  });

  testWidgets('seconds are zero-padded against the colon', (tester) async {
    await tester.pumpWidget(_wrap(const Duration(seconds: 65)));
    expect(_read(tester), '1:05');
  });

  testWidgets('a changed value rolls rather than cutting', (tester) async {
    await tester.pumpWidget(_wrap(const Duration(seconds: 8)));
    expect(_read(tester), '8');

    await tester.pumpWidget(_wrap(const Duration(seconds: 9)));
    await tester.pump(const Duration(milliseconds: 40));

    // Both the outgoing and incoming digits are mounted while the roll
    // runs; a plain Text swap would only ever show one of them.
    final mid = _read(tester);
    expect(
      mid.contains('8') && mid.contains('9'),
      isTrue,
      reason: 'saw "$mid" — the digit cut instead of rolling',
    );
  });
}
