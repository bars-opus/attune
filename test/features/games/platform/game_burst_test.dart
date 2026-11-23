import 'package:attune/features/games/platform/feel/game_burst.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  group('one ray', () {
    test('is invisible at the start and gone by the end', () {
      expect(burstRay(0, 40).alpha, 0);
      expect(burstRay(1, 40).alpha, 0);
      expect(burstRay(0.2, 40).alpha, greaterThan(0.8));
    });

    test('travels outward and never turns inside out', () {
      var lastOuter = -1.0;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final ray = burstRay(t, 40);
        expect(ray.outer, greaterThanOrEqualTo(lastOuter), reason: 'at $t');
        expect(ray.outer, greaterThan(ray.inner), reason: 'at $t');
        expect(ray.outer, lessThanOrEqualTo(40.0001), reason: 'at $t');
        lastOuter = ray.outer;
      }
      expect(lastOuter, greaterThan(30), reason: 'it does reach the edge');
    });

    test('odd progress values stay in bounds', () {
      for (final t in [-1.0, 1.5, 100.0, double.nan]) {
        final ray = burstRay(t, 40);
        expect(ray.inner.isFinite && ray.outer.isFinite, isTrue);
        expect(ray.alpha, inInclusiveRange(0.0, 1.0), reason: 'at $t');
      }
    });
  });

  group('the painter', () {
    RecordingCanvas paint(double progress, {int rays = 9}) {
      final canvas = RecordingCanvas();
      GameBurstPainter(
        progress: progress,
        color: const Color(0xFFFFFFFF),
        rays: rays,
      ).paint(canvas, const Size(80, 80));
      return canvas;
    }

    test('draws one line per ray, mid-burst', () {
      expect(paint(0.3).lines, hasLength(9));
      expect(paint(0.3, rays: 5).lines, hasLength(5));
    });

    test('draws nothing before it starts or after it ends', () {
      // The control is the test above: this painter does draw.
      expect(paint(0).lines, isEmpty);
      expect(paint(1).lines, isEmpty);
    });

    test('uses nothing costlier than lines', () {
      final canvas = paint(0.3);

      expect(canvas.lines, isNotEmpty);
      expect(canvas.unmodelled, isEmpty, reason: '${canvas.unmodelled}');
    });
  });

  group('the widget', () {
    Widget host(int count, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: GameBurst(count: count, color: const Color(0xFFFFFFFF)),
        ),
      ),
    );

    double progress(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(GameBurst),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as GameBurstPainter)
            .progress;

    testWidgets('plays once when the count goes up, then stops', (
      tester,
    ) async {
      await tester.pumpWidget(host(0));
      expect(progress(tester), 0);

      await tester.pumpWidget(host(1));
      await tester.pump(GameMotion.burst ~/ 2);
      expect(progress(tester), inExclusiveRange(0.0, 1.0));

      await tester.pumpAndSettle();
      expect(progress(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('does not play when the count is unchanged', (tester) async {
      await tester.pumpWidget(host(3));
      await tester.pumpWidget(host(3));
      await tester.pump(GameMotion.burst ~/ 2);

      expect(progress(tester), 0);
    });

    testWidgets('does not play at all under reduce motion', (tester) async {
      await tester.pumpWidget(host(0, reduceMotion: true));
      await tester.pumpWidget(host(1, reduceMotion: true));
      await tester.pump();

      expect(progress(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
