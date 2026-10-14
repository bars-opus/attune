import 'package:flutter/material.dart';

import 'neon_quality.dart';
import 'neon_tokens.dart';

/// How far a bloom has spread, 0 to 1 of its full radius.
///
/// Pure, so the curve is checkable without a canvas.
///
/// Front-loaded on purpose: paint hits hardest at contact and the spread
/// decelerates. A linear expansion reads as a balloon inflating, which
/// is the opposite of an impact.
double bloomRadiusAt(double progress, {required bool hit}) {
  // NaN compares false against everything, so it has to be caught rather
  // than clamped.
  final t = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);

  // A hit spreads wider than a miss. Identical blooms would make the two
  // outcomes indistinguishable at the one moment they matter most.
  final full = hit ? NeonTokens.bloomRadiusHit : NeonTokens.bloomRadiusMiss;

  // easeOutCubic: most of the travel in the first half.
  final eased = 1 - ((1 - t) * (1 - t) * (1 - t));
  return full * eased;
}

/// The instant a paintball lands.
///
/// Spec §2.6 beats 5 and 6: a white flash, then a coloured bloom, then
/// settle. §2.2 reserves white for exactly this and nowhere else on the
/// field, which is what makes a hit unmistakable -- and why the white
/// core must not linger, or the field gains a third palette colour.
///
/// Event motion (§2.5): it runs once off the replay's own progress and
/// schedules no frames of its own.
class BloomFlash extends StatelessWidget {
  const BloomFlash({
    super.key,
    required this.at,
    required this.color,
    required this.progress,
    required this.hit,
  });

  /// Where the shot landed, in the painter's own coordinates.
  final Offset at;

  /// The shooter's hue. The bloom is their paint, not the target's.
  final Color color;

  /// 0 to 1 across impact and settle.
  final double progress;

  final bool hit;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: BloomFlashPainter(
          at: at,
          color: color,
          progress: progress,
          hit: hit,
          quality: neonQualityOf(context),
        ),
      ),
    );
  }
}

/// Public, with public fields, so a test asserts on it without reaching
/// through `as dynamic` (spec §3.6.1).
class BloomFlashPainter extends CustomPainter {
  BloomFlashPainter({
    required this.at,
    required this.color,
    required this.progress,
    required this.hit,
    required this.quality,
  });

  final Offset at;
  final Color color;
  final double progress;
  final bool hit;
  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final t = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final radius = bloomRadiusAt(t, hit: hit);
    if (radius < 0.5) return;

    // The coloured bloom, fading as it spreads.
    final fade = (1 - t);
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = color.withValues(alpha: (0.45 * fade * fade).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          NeonTokens.haloBlurOuter,
        ),
    );

    // A tighter, brighter core behind it. Dropped first on a cheap
    // device: a second blurred pass over a large radius is the most
    // expensive thing this language draws (§6.10).
    if (quality != NeonQuality.plain) {
      canvas.drawCircle(
        at,
        radius * 0.55,
        Paint()
          ..color = color.withValues(alpha: (0.6 * fade).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            NeonTokens.haloBlurInner,
          ),
      );
    }

    // The white instant. §2.2's one exception, and it has to leave
    // quickly or it stops being an instant.
    const flashWindow = 0.22;
    if (t < flashWindow) {
      final flash = 1 - (t / flashWindow);
      canvas.drawCircle(
        at,
        radius * 0.4,
        Paint()
          ..color = const Color(
            0xFFFFFFFF,
          ).withValues(alpha: (flash * flash).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(BloomFlashPainter old) =>
      old.progress != progress ||
      old.at != at ||
      old.color != color ||
      old.hit != hit ||
      old.quality != quality;
}
