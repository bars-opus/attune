
import 'package:attune/core/ui/neon/bloom_flash.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCanvas implements Canvas {
  final circles = <({Offset centre, double radius, Paint paint})>[];

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((centre: c, radius: radius, paint: paint));

  /// Every canvas call this recorder does NOT model.
  ///
  /// The cost contracts here are the branch's only evidence for the
  /// §6.10 tier saving, and they work by counting draw calls -- so a
  /// future implementation that reached for saveLayer, clipPath or a
  /// transform would satisfy the count while costing more. Recording
  /// the unmodelled calls turns a contract that can be bypassed into
  /// one that cannot.
  final unmodelled = <String>[];

  @override
  noSuchMethod(Invocation invocation) {
    unmodelled.add(invocation.memberName.toString());
    return null;
  }
}

void main() {
  const mint = Color(0xFF5EEAD4);

  group('the bloom curve', () {
    test('it expands, fast at first', () {
      // An impact that grew linearly reads as a balloon inflating. Paint
      // hits hardest at the moment of contact and the spread decelerates,
      // so the curve has to be front-loaded.
      final early = bloomRadiusAt(0.25, hit: true);
      final mid = bloomRadiusAt(0.5, hit: true);
      final late = bloomRadiusAt(1.0, hit: true);

      expect(early, lessThan(mid));
      expect(mid, lessThan(late));
      expect(
        mid / late,
        greaterThan(0.5),
        reason: 'more than half the spread happens in the first half',
      );
    });

    test('it starts at nothing', () {
      expect(bloomRadiusAt(0, hit: true), closeTo(0, 0.01));
    });

    test('a hit blooms wider than a miss', () {
      // A miss that bloomed as large as a hit would make the two
      // outcomes indistinguishable at the one moment they matter most.
      expect(
        bloomRadiusAt(1.0, hit: true),
        greaterThan(bloomRadiusAt(1.0, hit: false)),
      );
    });

    test('out-of-range progress stays bounded', () {
      // The replay's impactProgress is clamped upstream, but a radius
      // that could run away would be a crash rather than a glitch.
      for (final p in [-1.0, -0.0, 1.5, 100.0, double.nan]) {
        final r = bloomRadiusAt(p, hit: true);
        expect(r.isFinite, isTrue, reason: 'at $p');
        expect(r, greaterThanOrEqualTo(0), reason: 'at $p');
        expect(
          r,
          lessThanOrEqualTo(bloomRadiusAt(1.0, hit: true) + 0.01),
          reason: 'at $p the bloom must not exceed its full size',
        );
      }
    });
  });

  group('what gets drawn', () {
    _RecordingCanvas render(double progress, {NeonQuality quality = NeonQuality.rich}) {
      final canvas = _RecordingCanvas();
      BloomFlashPainter(
        at: const Offset(100, 100),
        color: mint,
        progress: progress,
        hit: true,
        quality: quality,
      ).paint(canvas, const Size(200, 200));
      return canvas;
    }

    test('the first instant is WHITE, and only the first instant', () {
      // §2.2 reserves white for the instant of impact and nothing else
      // on the field. That is what makes a hit unmistakable -- but a
      // white core that lingered would turn the field's one special
      // colour into a third palette entry.
      final flash = render(0.05);
      final later = render(0.8);

      bool hasWhite(_RecordingCanvas c) => c.circles.any(
        (d) => d.paint.color.r > 0.9 && d.paint.color.g > 0.9 && d.paint.color.b > 0.9,
      );

      expect(flash.circles, isNotEmpty, reason: 'a positive control');
      expect(hasWhite(flash), isTrue, reason: 'the flash is white');
      expect(later.circles, isNotEmpty, reason: 'a positive control');
      expect(hasWhite(later), isFalse, reason: 'and it does not linger');
    });

    test('the bloom carries the shooter’s colour', () {
      final bloom = render(0.6);

      expect(bloom.circles, isNotEmpty);
      expect(
        bloom.circles.any((d) => d.paint.color.g > d.paint.color.r),
        isTrue,
        reason: 'mint is greener than it is red',
      );
    });

    test('it fades to nothing by the end', () {
      // The bloom is an event, not a state (§2.5). A bloom still visible
      // at rest would schedule frames forever.
      final done = render(1.0);

      for (final draw in done.circles) {
        expect(
          draw.paint.color.a,
          lessThan(0.15),
          reason: 'the bloom has faded out, not frozen at full strength',
        );
      }
    });

    test('nothing is drawn before the impact', () {
      final canvas = _RecordingCanvas();
      BloomFlashPainter(
        at: const Offset(100, 100),
        color: mint,
        progress: 0,
        hit: true,
        quality: NeonQuality.rich,
      ).paint(canvas, const Size(200, 200));

      // A positive control lives in the sibling tests above, which prove
      // this painter DOES draw at other progress values.
      expect(canvas.circles.where((d) => d.radius > 0.5), isEmpty);
    });

    test('the cost contract counts every call, not just drawCircle', () {
      // Across the whole bloom and every tier: the white flash, the
      // bloom and the fade are three different code paths, and a
      // saveLayer on any one of them would otherwise slip through.
      for (final quality in NeonQuality.values) {
        for (final progress in [0.05, 0.3, 0.6, 1.0]) {
          final canvas = render(progress, quality: quality);

          expect(
            canvas.circles,
            isNotEmpty,
            reason: 'a positive control, at $quality progress $progress',
          );
          expect(
            canvas.unmodelled,
            isEmpty,
            reason:
                'at $quality progress $progress the bloom used a canvas '
                'call the cost contract cannot see: ${canvas.unmodelled}',
          );
        }
      }
    });

    test('the plain tier draws fewer layers', () {
      // §6.10's launch gate. A full-screen bloom is the single most
      // expensive effect in this language.
      final rich = render(0.5);
      final plain = render(0.5, quality: NeonQuality.plain);

      expect(rich.circles, isNotEmpty, reason: 'a positive control');
      expect(plain.circles.length, lessThan(rich.circles.length));
      expect(plain.circles, isNotEmpty, reason: 'but a hit still registers');
    });
  });

  testWidgets('the widget renders without a canvas of its own', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: BloomFlash(
              at: Offset(100, 100),
              color: mint,
              progress: 0.5,
              hit: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(BloomFlash), findsOneWidget);
  });
}
