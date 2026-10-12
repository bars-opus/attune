import 'dart:ui';

import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was drawn, so the halo structure can be asserted
/// without a golden. A golden proves it LOOKS right; this proves the
/// right number of passes happened, which is the performance contract.
class _RecordingCanvas implements Canvas {
  final drawnPaths = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) => drawnPaths.add(paint);

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  final path = Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10));
  const spec = GlowStrokeSpec(color: Color(0xFF5EEAD4), alpha: 0.9);

  test('a core stroke is always drawn, whatever the tier', () {
    // The outline is what makes the field legible. Halo is decoration;
    // the core is the information, and it may never be optimised away.
    for (final quality in NeonQuality.values) {
      final canvas = _RecordingCanvas();
      paintGlowPath(canvas, path, spec, quality.haloPasses);

      expect(
        canvas.drawnPaths,
        isNotEmpty,
        reason: '$quality must still draw the stroke itself',
      );
    }
  });

  test('each tier draws exactly its halo passes plus the core', () {
    for (final quality in NeonQuality.values) {
      final canvas = _RecordingCanvas();
      paintGlowPath(canvas, path, spec, quality.haloPasses);

      expect(
        canvas.drawnPaths.length,
        quality.haloPasses + 1,
        reason: '$quality: ${quality.haloPasses} halo passes and one core',
      );
    }
  });

  test('halo passes are dimmer and wider than the core', () {
    // §2.1: an outline reads as EMITTING only if the blur sits behind a
    // crisp edge. Equal-alpha passes read as a fuzzy line instead.
    final canvas = _RecordingCanvas();
    paintGlowPath(canvas, path, spec, NeonQuality.rich.haloPasses);

    // Painted back to front: widest and dimmest first, core last.
    final core = canvas.drawnPaths.last;
    final halos = canvas.drawnPaths.take(canvas.drawnPaths.length - 1);

    for (final halo in halos) {
      expect(
        halo.color.a,
        lessThan(core.color.a),
        reason: 'a halo must be dimmer than the edge it surrounds',
      );
      expect(
        halo.strokeWidth,
        greaterThan(core.strokeWidth),
        reason: 'a halo must be wider than the edge it surrounds',
      );
      expect(
        halo.maskFilter,
        isNotNull,
        reason: 'a halo without blur is just a thick line',
      );
    }

    expect(
      core.maskFilter,
      isNull,
      reason: 'the core must stay crisp or the whole thing reads as fog',
    );
  });

  test('zero alpha draws nothing rather than an invisible pass', () {
    // Reachable: a bay fading out passes alpha through to 0, and
    // painting a fully transparent blur is pure cost for no pixels.
    final canvas = _RecordingCanvas();
    paintGlowPath(
      canvas,
      path,
      const GlowStrokeSpec(color: Color(0xFF5EEAD4), alpha: 0),
      NeonQuality.rich.haloPasses,
    );

    expect(canvas.drawnPaths, isEmpty);
  });

  test('alpha above one is clamped rather than throwing', () {
    // An animation overshooting with easeOutBack can hand this a value
    // over 1, and Color.withValues asserts on out-of-range alpha.
    final canvas = _RecordingCanvas();

    expect(
      () => paintGlowPath(
        canvas,
        path,
        const GlowStrokeSpec(color: Color(0xFF5EEAD4), alpha: 1.4),
        NeonQuality.glow.haloPasses,
      ),
      returnsNormally,
    );
    for (final paint in canvas.drawnPaths) {
      expect(paint.color.a, lessThanOrEqualTo(1.0));
    }
  });

  test('the pass count helper agrees with the enum', () {
    for (final quality in NeonQuality.values) {
      expect(glowPassCountFor(quality), quality.haloPasses);
    }
  });
}
