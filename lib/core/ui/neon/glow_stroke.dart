import 'dart:ui';

import 'neon_quality.dart';
import 'neon_tokens.dart';

/// How bright, and in what colour, one luminous outline is.
class GlowStrokeSpec {
  const GlowStrokeSpec({
    required this.color,
    required this.alpha,
    this.widthScale = 1.0,
  });

  final Color color;

  /// 0 to 1. Clamped when painted, because an overshooting curve can
  /// hand this a value above 1 and Color.withValues asserts on those.
  final double alpha;

  /// Multiplies the core stroke width, for an outline that should read
  /// heavier than the default without changing the token.
  final double widthScale;
}

/// Halo passes for a tier, re-exported so painters need not import the
/// enum alongside this file.
int glowPassCountFor(NeonQuality quality) => quality.haloPasses;

/// Paints [path] as a luminous outline: blurred halo passes behind one
/// crisp core stroke.
///
/// The two-part construction is the whole trick of spec §2.1. A single
/// wide blur reads as fog. A blur sitting BEHIND a sharp edge reads as
/// emission, because that is what a real light source does to a camera.
/// So the core is never blurred and never dropped -- it carries the
/// information; the halo is the only part that degrades.
///
/// Drawn back to front: widest and dimmest first, core last.
void paintGlowPath(
  Canvas canvas,
  Path path,
  GlowStrokeSpec spec,
  int haloPasses,
) {
  final alpha = spec.alpha.clamp(0.0, 1.0);

  // A fully transparent outline is pure cost for no pixels, and a bay
  // fading out passes exactly that.
  if (alpha <= 0) return;

  final coreWidth = NeonTokens.coreStrokeWidth * spec.widthScale;

  // Outer first so the inner pass layers over it.
  for (var pass = haloPasses; pass >= 1; pass--) {
    final isOuter = pass == 2;
    final blur = isOuter ? NeonTokens.haloBlurOuter : NeonTokens.haloBlurInner;
    final spread =
        isOuter ? NeonTokens.haloSpreadOuter : NeonTokens.haloSpreadInner;
    final haloAlpha =
        alpha * (isOuter ? NeonTokens.haloAlphaOuter : NeonTokens.haloAlphaInner);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreWidth + spread
        ..color = spec.color.withValues(alpha: haloAlpha.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = coreWidth
      ..color = spec.color.withValues(alpha: alpha),
  );
}
