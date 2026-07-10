// test/core/ui/scale_pop_test.dart
import 'package:attune/core/ui/motion/scale_pop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pops (scale != 1.0 mid-animation) when trigger changes',
      (tester) async {
    var trigger = 0;
    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, s) {
        setState = s;
        return ScalePop(trigger: trigger, child: const Icon(Icons.send));
      }),
    ));
    setState(() => trigger = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final t = tester.widget<ScaleTransition>(find.byType(ScaleTransition));
    expect(t.scale.value, isNot(1.0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      1.0,
    );
  });

  testWidgets('reduce-motion never leaves scale off 1.0', (tester) async {
    var trigger = 0;
    late StateSetter setState;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: StatefulBuilder(builder: (context, s) {
          setState = s;
          return ScalePop(trigger: trigger, child: const Icon(Icons.send));
        }),
      ),
    ));
    setState(() => trigger = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      1.0,
    );
  });
}
