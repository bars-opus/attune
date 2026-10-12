import 'dart:math' as math;

import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  double? coverWidth,
}) {
  // Taken as a parameter rather than read from ScreenUtil, because this
  // function is PURE and its unit tests have no ScreenUtilInit in the
  // tree -- `.w` throws LateInitializationError there. The widget layer
  // scales and passes it down; the default keeps the unscaled value for
  // callers that are already working in design units.
  final cover = coverWidth ?? kPaintBallCoverWidth;
  // PaintSplat.position is a bare int off the wire with no validation,
  // so a stale or malformed round can carry 3 or -1. Clamping keeps a
  // bad row on the field instead of drawing off it.
  final position = splat.position.clamp(0, kPaintBallPositions - 1);

  final centreX = figureCentreX(
    rowWidth: rowWidth,
    coverWidth: cover,
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
      splat.hit ? 0.0 : (rng.nextDouble() - 0.5) * cover * 0.8;
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
            coverWidth: kPaintBallCoverWidth.w,
            hitRadius: 15.r,
            missRadius: 10.r,
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
    this.coverWidth = kPaintBallCoverWidth,
    this.hitRadius = 15,
    this.missRadius = 10,
  });

  final List<PaintSplat> splats;
  final Color mineColor;
  final Color theirsColor;
  final NeonQuality quality;
  final double rowWidth;

  /// A splat's size. Scaled by the widget layer like [coverWidth], and
  /// defaulted to the design values so a unit test needs no ScreenUtil.
  final double hitRadius;
  final double missRadius;

  /// Scaled by the widget layer, so the painter and [splatCentre] agree
  /// with the covers the figures stand on.
  ///
  /// Defaults to the unscaled design value rather than being required,
  /// so a unit test can construct this painter without a ScreenUtilInit
  /// in the tree -- `.w` throws LateInitializationError there.
  final double coverWidth;

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
            // Translucent on purpose. The first golden showed paint as
            // opaque blobs smothering the bay they landed on -- paint is
            // a RECORD of the round, and it must not outrank the cover
            // it marks (§2.1: structure stays legible).
            ..color = colour.withValues(alpha: 0.14 + 0.20 * age)
            ..style = PaintingStyle.fill;

      final centre = splatCentre(
        splat: splat,
        size: size,
        rowWidth: rowWidth,
        coverWidth: coverWidth,
      );
      final rng = math.Random(splat.round * 31 + splat.position * 7);

      // Taken as a parameter rather than derived from coverWidth or read
      // via `.r`. Deriving it compounded the scale twice: at the design
      // width the ratio gave the intended 26pt, but at a wider viewport
      // it gave 55pt and the splat swallowed the figure and its cover
      // whole. Caught by rendering the golden and looking at it.
      _drawSplat(
        canvas,
        centre,
        splat.hit ? hitRadius : missRadius,
        paint,
        rng,
      );
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
      old.coverWidth != coverWidth ||
      old.hitRadius != hitRadius ||
      old.missRadius != missRadius ||
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
