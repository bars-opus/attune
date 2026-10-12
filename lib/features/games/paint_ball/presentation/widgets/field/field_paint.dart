import 'dart:math' as math;

import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import '../paint_ball_field.dart'
    show PaintSplat, kPaintBallCoverWidth, kPaintBallPositions;
import 'field_figure.dart' show figureCentreX;
import 'paint_ball_field_keys.dart';

/// How many splats stay on the field.
///
/// Paint from a whole match would bury the covers, so only the most
/// recent survive and older ones fade.
const int kFieldPaintVisible = 12;

/// Where one splat lands.
///
/// Pure, because this function is a BUG FIX and the alternative way to
/// test it is rendering a field at three widths and measuring pixels.
///
/// The old painter used `size.width / kPaintBallPositions` slot maths
/// while the bays and figures use the cover-centre formula. Those agree
/// only at the middle position; at the outer two, paint landed 11-17pt
/// to one side of the cover it had just hit, worsening with screen
/// width. Position 1 being exact is almost certainly why it survived.
///
/// Calling [figureCentreX] rather than recomputing is the point: one
/// formula for the whole field, so paint cannot drift away from the
/// cover it describes.
Offset splatCentre({
  required PaintSplat splat,
  required Size size,
  required double rowWidth,
}) {
  // PaintSplat.position is a bare int off the wire with no validation,
  // so a stale or malformed round can carry 3 or -1. Clamping keeps a
  // bad row on the field instead of drawing off it.
  final position = splat.position.clamp(0, kPaintBallPositions - 1);

  final centreX = figureCentreX(
    rowWidth: rowWidth,
    coverWidth: kPaintBallCoverWidth,
    column: position.toDouble(),
  );

  // Yours near the bottom, theirs near the top: the same never-flips
  // rule the rows follow, so "mine" is never something to work out.
  final rowY = splat.isMine ? size.height * 0.80 : size.height * 0.20;

  // Seeded per round and position, so redrawing a round does not move
  // its paint. A hit has no scatter at all -- it landed where it
  // landed, and a hit nudged off-centre would read as a near miss.
  final rng = math.Random(splat.round * 31 + position * 7);
  final offsetX =
      splat.hit ? 0.0 : (rng.nextDouble() - 0.5) * kPaintBallCoverWidth * 0.8;
  final offsetY = (rng.nextDouble() - 0.5) * 18;

  return Offset(
    (centreX + offsetX).clamp(0.0, math.max(0.0, size.width)),
    rowY + offsetY,
  );
}

/// The paint on the field.
///
/// Public [splats] so a test reads it directly rather than through
/// `(painter as dynamic).splats` (spec §3.6.1).
class FieldPaint extends StatelessWidget {
  const FieldPaint({
    super.key,
    required this.splats,
    required this.mineColor,
    required this.theirsColor,
  });

  final List<PaintSplat> splats;
  final Color mineColor;
  final Color theirsColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          key: PaintBallFieldKeys.paint,
          size: Size.infinite,
          painter: FieldPaintPainter(
            splats: splats,
            mineColor: mineColor,
            theirsColor: theirsColor,
            quality: neonQualityOf(context),
            rowWidth: constraints.maxWidth,
          ),
        );
      },
    );
  }
}

/// Draws the paint. Public fields throughout, for the same reason.
class FieldPaintPainter extends CustomPainter {
  FieldPaintPainter({
    required this.splats,
    required this.mineColor,
    required this.theirsColor,
    required this.quality,
    required this.rowWidth,
  });

  final List<PaintSplat> splats;
  final Color mineColor;
  final Color theirsColor;
  final NeonQuality quality;
  final double rowWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (splats.isEmpty || size.isEmpty) return;

    final recent =
        splats.length <= kFieldPaintVisible
            ? splats
            : splats.sublist(splats.length - kFieldPaintVisible);

    for (var i = 0; i < recent.length; i++) {
      final splat = recent[i];
      final age = recent.length == 1 ? 1.0 : i / (recent.length - 1);

      final colour = splat.isMine ? mineColor : theirsColor;
      final paint =
          Paint()
            ..color = colour.withValues(
              alpha: (0.18 + 0.32 * age) * NeonTokens.actorAlpha,
            )
            ..style = PaintingStyle.fill;

      final centre = splatCentre(
        splat: splat,
        size: size,
        rowWidth: rowWidth,
      );
      final rng = math.Random(splat.round * 31 + splat.position * 7);

      _drawSplat(canvas, centre, splat.hit ? 26.0 : 16.0, paint, rng);
    }
  }

  /// An irregular blob rather than a circle: a perfect disc reads as a
  /// dot, and paint does not land in circles.
  void _drawSplat(
    Canvas canvas,
    Offset centre,
    double radius,
    Paint paint,
    math.Random rng,
  ) {
    final path = Path();
    const points = 9;

    for (var i = 0; i <= points; i++) {
      final angle = (i / points) * 2 * math.pi;
      final wobble = radius * (0.7 + rng.nextDouble() * 0.5);
      final point = Offset(
        centre.dx + math.cos(angle) * wobble,
        centre.dy + math.sin(angle) * wobble,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    // Flecks around the blob. The first thing to go on a cheap device:
    // three extra circles per splat, twelve splats deep, is exactly the
    // kind of cost §6.10's launch gate is about.
    if (quality == NeonQuality.plain) return;

    for (var i = 0; i < 3; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final distance = radius * (1.1 + rng.nextDouble() * 0.7);
      canvas.drawCircle(
        Offset(
          centre.dx + math.cos(angle) * distance,
          centre.dy + math.sin(angle) * distance,
        ),
        radius * 0.12,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FieldPaintPainter old) =>
      old.quality != quality ||
      old.rowWidth != rowWidth ||
      old.mineColor != mineColor ||
      old.theirsColor != theirsColor ||
      old.splats.length != splats.length ||
      List.generate(splats.length, (index) {
        final current = splats[index];
        final previous = old.splats[index];
        return current.round != previous.round ||
            current.position != previous.position ||
            current.isMine != previous.isMine ||
            current.hit != previous.hit;
      }).any((changed) => changed);
}
