// Spec 1 W10 (batch 4 fix round 1): taps that still land once large text
// pushes their target below the fold. The large-text audit
// (scripts/large_text_audit.py) fails on a missed tap, because the states
// after it are never laid out at that size.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether a tap at the centre of [finder] would reach it now.
bool wouldHit(WidgetTester t, Finder finder) {
  final box = t.renderObject(finder) as RenderBox;
  final at = box.localToGlobal(box.size.center(Offset.zero));
  return t.hitTestOnBinding(at).path.any((e) => e.target == box);
}

/// Scrolls [finder] into reach, only when a tap would miss it: to the middle
/// of its scrollable, else to the top (clear of a composer or bar at the
/// bottom), else to the bottom. When the tap would land it does nothing at
/// all (no scroll, no frame), so a test at the normal size runs as before.
Future<void> bringIntoReach(WidgetTester t, Finder finder) async {
  for (final alignment in const [0.5, 0.0, 1.0]) {
    if (wouldHit(t, finder)) return;
    await Scrollable.ensureVisible(t.element(finder), alignment: alignment);
    await t.pump();
  }
}

/// [WidgetTester.tap] after [bringIntoReach].
Future<void> tapInReach(WidgetTester t, Finder finder) async {
  await bringIntoReach(t, finder);
  await t.tap(finder);
}
