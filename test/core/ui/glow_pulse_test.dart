// test/core/ui/glow_pulse_test.dart
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inactive shows no glow decoration', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(active: false, child: SizedBox(width: 40, height: 40)),
    ));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.boxShadow == null || deco.boxShadow!.isEmpty, isTrue);
  });

  testWidgets('active renders a glow that animates', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(
        active: true,
        color: Color(0xFFEEAA55),
        child: SizedBox(width: 40, height: 40),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.boxShadow, isNotNull);
    expect(deco.boxShadow!.isNotEmpty, isTrue);
    // Stop the infinite animation so the test can settle.
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(active: false, child: SizedBox(width: 40, height: 40)),
    ));
  });
}
