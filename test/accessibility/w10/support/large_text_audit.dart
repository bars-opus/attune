// Spec 1 W10a: the large-text audit's shared pieces. Every audited surface
// is pumped at each text size below on two phones; every layout overflow
// is collected (file:line) instead of failing at the first; goldens are
// taken on the common phone at 1.0, 1.3 and 2.0 (§2.3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Normal text and the three candidate caps (§8 W10a).
const auditScales = <double>[1.0, 1.3, 1.6, 2.0];

/// The golden sizes (§2.3).
const goldenScales = <double>[1.0, 1.3, 2.0];

/// A common phone, and a narrow Android one (Android Go class).
const auditPhones = <Size>[Size(390, 844), Size(360, 800)];

/// `scale1.0`, `scale1.3`, `scale2.0`: the flow goldens' naming.
String scaleName(double scale) => 'scale${scale.toStringAsFixed(1)}';

/// Sets the phone's size and text size for one test.
void setPhone(WidgetTester t, Size size, double scale) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
}

/// Every layout overflow reported while [body] runs, as `file:line`
/// (`lib/...`), one entry per overflowing widget. A tap that misses its
/// widget (below the fold at large text) fails the test instead of
/// leaving the flow short of the state it was meant to reach.
Future<List<String>> collectOverflows(Future<void> Function() body) async => [
  for (final (site, _) in await collectOverflowSizes(body)) site,
];

/// As [collectOverflows], with how far each widget overflowed, in pixels.
Future<List<(String, double)>> collectOverflowSizes(
  Future<void> Function() body,
) async {
  final found = <(String, double)>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (!text.contains('overflowed by')) {
      previous?.call(details);
      return;
    }
    final at = RegExp(
      r'The relevant error-causing widget was:\s*\n\s*\S+\s*\n\s*\S+:file://\S*?/(lib/[^:\s]+:\d+)',
    ).firstMatch(text);
    final px = RegExp(r'overflowed by ([0-9.]+) pixels').firstMatch(text);
    found.add((
      at?.group(1) ?? text.split('\n').first,
      double.tryParse(px?.group(1) ?? '') ?? 0,
    ));
  };
  final previousHitTest = WidgetController.hitTestWarningShouldBeFatal;
  WidgetController.hitTestWarningShouldBeFatal = true;
  try {
    await body();
  } finally {
    WidgetController.hitTestWarningShouldBeFatal = previousHitTest;
    FlutterError.onError = previous;
  }
  return found;
}

/// Drags every vertical scrollable on screen to its end, a screen at a
/// time, so rows below the fold are laid out too.
Future<void> scrollToEnd(WidgetTester t) async {
  final scrollables = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  for (var i = 0; i < 6; i++) {
    if (scrollables.evaluate().isEmpty) return;
    await t.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
  }
}

/// Pumps frames for [duration] without waiting for every animation to end
/// (some surfaces animate forever).
Future<void> settle(
  WidgetTester t, [
  Duration duration = const Duration(seconds: 2),
]) async {
  for (
    var elapsed = Duration.zero;
    elapsed < duration;
    elapsed += const Duration(milliseconds: 100)
  ) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
