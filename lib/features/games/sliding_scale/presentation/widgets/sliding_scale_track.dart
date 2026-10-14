import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

/// Where on the scale a value sits, 0 to 1.
///
/// Pure, because the mapping from a 1-10 answer to a position is the
/// part worth testing and a widget test would have to measure pixels to
/// reach it.
double slidingScaleFraction(double value, {double min = 1, double max = 10}) {
  if (max <= min) return 0;
  final t = value.isNaN ? min : value.clamp(min, max);
  return (t - min) / (max - min);
}

/// The scale itself: a lit track whose glow follows the answer.
///
/// Sliding Scale is literally a spectrum, and it shipped as a stock
/// Material slider on a default background -- the one game whose subject
/// is a gradient, drawn without one. It is also the neon toolkit's
/// second consumer, which is the acceptance test for whether that
/// toolkit generalises beyond the game it was built for (spec §6.3).
///
/// The track is drawn, not filled: §2.1 tier 2 says structure is a
/// luminous outline. What moves is the LIT PORTION, so the answer reads
/// as how far along the spectrum you are rather than as a knob's
/// coordinate.
class SlidingScaleTrack extends StatelessWidget {
  const SlidingScaleTrack({
    super.key,
    required this.fraction,
    required this.lowColor,
    required this.highColor,
  });

  /// 0 to 1. See [slidingScaleFraction].
  final double fraction;

  /// The two ends of the spectrum. Sliding Scale's palette entry is teal
  /// into blue precisely because the game is a gradient.
  final Color lowColor;
  final Color highColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 48),
      painter: SlidingScaleTrackPainter(
        fraction: fraction,
        lowColor: lowColor,
        highColor: highColor,
        quality: neonQualityOf(context),
      ),
    );
  }
}

/// Public, with public fields, so a test asserts on it without reaching
/// through `as dynamic` (spec §3.6.1).
class SlidingScaleTrackPainter extends CustomPainter {
  SlidingScaleTrackPainter({
    required this.fraction,
    required this.lowColor,
    required this.highColor,
    required this.quality,
  });

  final double fraction;
  final Color lowColor;
  final Color highColor;
  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final t = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final y = size.height / 2;
    final inset = size.height * 0.4;
    final left = inset;
    final right = size.width - inset;
    if (right <= left) return;

    // The whole span, dim: the part of the spectrum you have not claimed.
    paintGlowPath(
      canvas,
      Path()
        ..moveTo(left, y)
        ..lineTo(right, y),
      GlowStrokeSpec(color: highColor, alpha: NeonTokens.structureAlphaRest),
      quality.haloPasses,
    );

    // The lit portion, in the hue of the end you are nearer. Colour
    // carries meaning here the way ownership does on the Paint Ball
    // field: it says which end of the spectrum this answer belongs to.
    final head = left + (right - left) * t;
    if (head > left) {
      paintGlowPath(
        canvas,
        Path()
          ..moveTo(left, y)
          ..lineTo(head, y),
        GlowStrokeSpec(
          color: Color.lerp(lowColor, highColor, t)!,
          alpha: NeonTokens.actorAlpha,
          widthScale: 2.2,
        ),
        quality.haloPasses,
      );
    }

    // The answer itself: the brightest thing on the track (§2.1 tier 3).
    final mark = Offset(head, y);
    canvas.drawCircle(
      mark,
      size.height * 0.17,
      Paint()
        ..color = Color.lerp(
          lowColor,
          highColor,
          t,
        )!.withValues(alpha: NeonTokens.actorAlpha),
    );

    if (quality != NeonQuality.plain) {
      canvas.drawCircle(
        mark,
        size.height * 0.30,
        Paint()
          ..color = Color.lerp(lowColor, highColor, t)!.withValues(alpha: 0.28)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            NeonTokens.haloBlurInner,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(SlidingScaleTrackPainter old) =>
      old.fraction != fraction ||
      old.lowColor != lowColor ||
      old.highColor != highColor ||
      old.quality != quality;
}
