import 'dart:math' as math;

import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../paint_ball_field.dart' show kPaintBallPositions;
import 'paint_ball_field_keys.dart';

/// How long a figure takes to change cover.
///
/// Deliberately outside the 150-320ms band the rest of this work obeys.
/// That band governs a SETTLE -- one object arriving at one place. This
/// is three sequential beats (step back out of cover, cross, step
/// forward into the new one), and three beats inside 320ms is about
/// 100ms each, below the point at which an eye can follow a path at all.
///
/// Pinned by a test so that "fixing" it to comply with the band breaks
/// something visible rather than quietly removing the journey.
const Duration kFigureTravelDuration = Duration(milliseconds: 620);

/// Where a figure's centre sits for a given column.
///
/// A pure function because this formula is the fix for a bug reported
/// from a device, and the alternative way to test it is pumping a field
/// at several widths and reading back rectangles.
///
/// The covers are a FIXED width laid out by spaceEvenly, which produces
/// four equal gaps around three covers. So a cover's centre is
/// `gap*(i+1) + coverWidth*(i+0.5)` -- which equals a notional slot
/// centre (`rowWidth/3`) only when the row happens to be exactly three
/// covers wide. Slot maths drifted the figure off its cover at every
/// other width, worst at the outer two.
///
/// Accepts a fractional [column] so the crossing interpolates.
double figureCentreX({
  required double rowWidth,
  required double coverWidth,
  required double column,
}) {
  final gap =
      (rowWidth - kPaintBallPositions * coverWidth) /
      (kPaintBallPositions + 1);
  return gap * (column + 1) + coverWidth * (column + 0.5);
}

/// A player, as a luminous mark that travels between covers.
///
/// Spec §2.1 tier 3: actors are the only bright things on the field, and
/// §2.2 gives them their OWNER's hue rather than a third neutral colour,
/// so that colour keeps meaning ownership and nothing else.
///
/// It lives above the row rather than inside a cover, because a child
/// cannot travel outside its parent's box -- which is exactly what a
/// journey between covers requires.
class FieldFigure extends StatefulWidget {
  const FieldFigure({
    super.key,
    required this.position,
    required this.isOpponent,
    required this.rowWidth,
    required this.coverWidth,
    required this.ownerColor,
    required this.isAiming,
    required this.tilt,
    required this.reduceMotion,
    this.onTap,
  });

  final int position;
  final bool isOpponent;

  /// The full row and one cover inside it. Both are needed: the covers
  /// are a fixed width with even gaps, so their spacing is not the row
  /// divided three ways (see [figureCentreX]).
  final double rowWidth;
  final double coverWidth;

  /// §2.2: a figure wears its owner's colour.
  final Color ownerColor;

  final bool isAiming;

  /// Lean toward whatever is being aimed at, in turns, so an aim is
  /// visible on the field rather than only in a control strip.
  final double tilt;

  final bool reduceMotion;

  /// Set only when this figure IS the fire control.
  final VoidCallback? onTap;

  @override
  State<FieldFigure> createState() => _FieldFigureState();
}

class _FieldFigureState extends State<FieldFigure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _fromColumn;
  late int _to;
  // Where the figure is drawn this frame. A retarget resumes from here,
  // not from the target it was heading to.
  late double _liveColumn;

  @override
  void initState() {
    super.initState();
    _fromColumn = widget.position.toDouble();
    _liveColumn = _fromColumn;
    _to = widget.position;
    _controller = AnimationController(
      vsync: this,
      duration: kFigureTravelDuration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(FieldFigure old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      // Resume from where the figure actually IS, not from the target it
      // was heading to. Using old.position made an interrupted journey
      // snap forward to the abandoned target and then travel backwards
      // -- a measured 116pt teleport, in the widget built to prevent
      // exactly that.
      _fromColumn =
          _controller.value < 1 ? _liveColumn : old.position.toDouble();
      _to = widget.position;
      if (widget.reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quality = neonQualityOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // The lateral move happens in the MIDDLE of the journey, so the
        // figure is clear of cover while it crosses. Sliding sideways
        // while still tucked in would read as passing through the wall.
        final lateral = Curves.easeInOut.transform(
          ((t - 0.25) / 0.5).clamp(0.0, 1.0),
        );
        final column = _fromColumn + (_to - _fromColumn) * lateral;
        _liveColumn = column;

        // Depth: 0 is tucked in cover, 1 is stepped out. It rises for
        // the crossing and falls again on arrival -- and stays out while
        // aiming, since an aiming player is deliberately exposed.
        final travelling = t < 1;
        final depth =
            travelling
                ? Curves.easeInOut.transform(1 - (2 * t - 1).abs())
                : (widget.isAiming ? 1.0 : 0.0);

        // Sized in `.r` on BOTH axes. `.w` by `.h` gave the silhouette a
        // different aspect on every screen shape -- and on the 800x600
        // test surface drew it stretched nearly 3:1, which is the
        // distortion three figure redesigns were judged against.
        final figureSize = Size(
          FieldFigurePainter.kWidth.r,
          FieldFigurePainter.kHeight.r,
        );

        final x = figureCentreX(
              rowWidth: widget.rowWidth,
              coverWidth: widget.coverWidth,
              column: column,
            ) -
            figureSize.width / 2;

        // Both rows shelter under their own dome and the domes face each
        // other, so "tucked in" is measured from opposite edges. A
        // single inset would have put the opponent outside their arch
        // entirely, standing on top of the cover instead of behind it.
        final baseInset = widget.isOpponent ? 46.h : 34.h;
        final stepOut = 14.h * depth;

        return Positioned(
          key: PaintBallFieldKeys.figure(
            widget.position,
            isOpponent: widget.isOpponent,
          ),
          left: x,
          top: widget.isOpponent ? baseInset + stepOut : null,
          bottom: widget.isOpponent ? null : baseInset + stepOut,
          child: IgnorePointer(
            // Transparent to taps unless it is the fire control: it
            // stands over a cover that is itself a tap target, and
            // intercepting would make that cover unreachable, silently
            // costing the player one of three hiding places.
            ignoring: widget.onTap == null,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedRotation(
                duration: Duration(
                  milliseconds: widget.reduceMotion ? 0 : 260,
                ),
                curve: Curves.easeOut,
                turns: widget.isAiming ? widget.tilt : 0,
                child: CustomPaint(
                  size: figureSize,
                  painter: FieldFigurePainter(
                    color: widget.ownerColor,
                    // BOTH rows draw upright.
                    //
                    // The partner used to be inverted so the two rows
                    // mirrored their cover. Rendering it showed why that
                    // fails: an upside-down bust reads as an exclamation
                    // mark, not a person -- you have to flip it in your
                    // head before it means anything, and the mint figure
                    // opposite is instant. A head is the one shape with
                    // no upside-down version that still says "head".
                    //
                    // Row position already carries whose figure it is,
                    // unambiguously: yours is always the near row and
                    // theirs the far one, and the field never flips. The
                    // COVER still mirrors, which is what makes the two
                    // sides face each other.
                    pointsUp: true,
                    quality: quality,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The figure itself: a head over shoulders, lit.
///
/// Public, with public fields, so a test never needs `as dynamic`
/// (spec §3.6.1).
///
/// The silhouette is the one every avatar placeholder uses -- a round
/// head, a neck gap, wide flat-topped shoulders cut off below -- because
/// it is the only two-shape arrangement people reliably read as "a
/// person" at sixteen pixels. Three earlier attempts all put a small
/// circle on a body that WIDENED toward the base, and a shape that
/// widens toward the base under a small circle is a pawn, a bell or a
/// bowling pin whatever its proportions. Shoulders are the widest part
/// of a person; everything below them is cut off, which also means the
/// figure keeps reading from its top half alone.
///
/// Drawn in a unit space scaled to fit the box, so the proportions hold
/// whatever size it is given -- and the aim tilt only rotates it.
class FieldFigurePainter extends CustomPainter {
  FieldFigurePainter({
    required this.color,
    required this.pointsUp,
    required this.quality,
  });

  final Color color;
  final bool pointsUp;
  final NeonQuality quality;

  /// The box a figure is given, in design points (scaled by `.r`). Wide
  /// enough to hold the bay's mouth (55pt) without crowding it.
  static const double kWidth = 28;
  static const double kHeight = 30;

  // The silhouette in units of its own width. Material's `person` glyph
  // proportions, with a slightly deeper neck gap so the core stroke
  // (1.6pt, straddling each edge) cannot close it.
  static const double _headRadius = 0.24;
  static const double _neckGap = 0.13;
  static const double _shoulderRise = 0.24;
  static const double _chest = 0.22;
  static const double _aspect =
      2 * _headRadius + _neckGap + _shoulderRise + _chest;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Fit the unit silhouette into whatever box we were given, centred
    // across and anchored to the head's end.
    final s = math.min(size.width, size.height / _aspect);
    double x(double u) => size.width / 2 + (u - 0.5) * s;
    double y(double v) => pointsUp ? v * s : size.height - v * s;

    final head = Path()..addOval(
      Rect.fromCircle(
        center: Offset(x(0.5), y(_headRadius)),
        radius: _headRadius * s,
      ),
    );

    final shoulderTop = 2 * _headRadius + _neckGap;
    final shoulderFlat = shoulderTop + _shoulderRise;
    final base = shoulderFlat + _chest;

    // Flat on top, rounded only at the outer corners: the curve leaves
    // each side vertically and arrives at the centre horizontally, so
    // the shoulders are as wide at the top as at the base.
    final body =
        Path()
          ..moveTo(x(0), y(base))
          ..lineTo(x(0), y(shoulderFlat))
          ..cubicTo(
            x(0),
            y(shoulderTop + _shoulderRise / 3),
            x(1 / 3),
            y(shoulderTop),
            x(0.5),
            y(shoulderTop),
          )
          ..cubicTo(
            x(2 / 3),
            y(shoulderTop),
            x(1),
            y(shoulderTop + _shoulderRise / 3),
            x(1),
            y(shoulderFlat),
          )
          ..lineTo(x(1), y(base))
          ..close();

    // One path, so the glow outlines the whole silhouette once. The two
    // pieces do not touch; their halos meet across the neck gap, which
    // is what makes them one lit body rather than two marks.
    final silhouette = Path.combine(PathOperation.union, body, head);

    // Filled, then outlined in its own glow: an actor is the brightest
    // thing on the field (§2.1 tier 3), and a stroke-only mark at this
    // size reads as structure rather than as a person.
    canvas.drawPath(
      silhouette,
      Paint()..color = color.withValues(alpha: NeonTokens.actorAlpha),
    );

    paintGlowPath(
      canvas,
      silhouette,
      GlowStrokeSpec(color: color, alpha: NeonTokens.actorAlpha),
      quality.haloPasses,
    );
  }

  @override
  bool shouldRepaint(FieldFigurePainter old) =>
      old.color != color ||
      old.pointsUp != pointsUp ||
      old.quality != quality;
}
