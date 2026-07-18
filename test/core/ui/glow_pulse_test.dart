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

  testWidgets(
      'active with reduce-motion renders a STATIC glow (signal without motion)',
      (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: const MaterialApp(
        home: GlowPulse(
          active: true,
          color: Color(0xFFEEAA55),
          child: SizedBox(width: 40, height: 40),
        ),
      ),
    ));
    await tester.pump();
    BoxDecoration decoAt() =>
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;

    // The "live" signal survives reduce-motion: a glow is present…
    final first = decoAt();
    expect(first.boxShadow, isNotNull);
    expect(first.boxShadow!.isNotEmpty, isTrue);

    // …but it does not animate: identical shadow across time, no pending
    // frames scheduled.
    await tester.pump(const Duration(milliseconds: 400));
    final later = decoAt();
    expect(later.boxShadow!.single.spreadRadius,
        first.boxShadow!.single.spreadRadius);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('pulse settles to a static glow after its cycles (no infinite loop)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(
        active: true,
        cycles: 1,
        color: Color(0xFFEEAA55),
        child: SizedBox(width: 40, height: 40),
      ),
    ));
    // One breath (1600ms up + 1600ms down) + settle ramp (400ms) + margin.
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    // Settled: static glow present, and nothing left animating — the whole
    // point of bounding the pulse is zero frame scheduling at rest.
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.boxShadow, isNotNull);
    expect(deco.boxShadow!.isNotEmpty, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
