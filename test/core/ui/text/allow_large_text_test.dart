// Spec 1 §2.3 (W2a): the phone's text size reaches a Spec 1 screen through
// the root shell's 1.0 clamp, capped at 2.0 and never below 1.0.
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _scaleOf10(WidgetTester tester, {required bool wrapped}) async {
  late double scaled;
  final probe = Builder(
    builder: (context) {
      scaled = MediaQuery.textScalerOf(context).scale(10);
      return const SizedBox();
    },
  );
  await tester.pumpWidget(
    MaterialApp(
      // What app_shell.dart does for every route.
      builder:
          (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: child!,
          ),
      home: wrapped ? AllowLargeText(child: probe) : probe,
    ),
  );
  return scaled;
}

void main() {
  testWidgets('the shell clamp alone keeps 1.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: false), 10);
  });

  testWidgets('wrapped, the phone text size comes through', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: true), closeTo(13, 0.001));
  });

  testWidgets('capped at 2.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: true), 20);
  });

  testWidgets('never below 1.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 0.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    expect(await _scaleOf10(tester, wrapped: true), 10);
  });
}
