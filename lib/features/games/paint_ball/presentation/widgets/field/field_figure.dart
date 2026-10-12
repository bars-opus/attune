import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

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

        final x = figureCentreX(
              rowWidth: widget.rowWidth,
              coverWidth: widget.coverWidth,
              column: column,
            ) -
            11;

        // Both rows shelter under their own dome and the domes face each
        // other, so "tucked in" is measured from opposite edges. A
        // single inset would have put the opponent outside their arch
        // entirely, standing on top of the cover instead of behind it.
        final baseInset = widget.isOpponent ? 46.0 : 34.0;
        final stepOut = 14.0 * depth;

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
                  size: const Size(22, 20),
                  painter: FieldFigurePainter(
                    color: widget.ownerColor,
                    pointsUp: !widget.isOpponent,
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

/// The figure itself: a lit arrowhead.
///
/// Public, with public fields, so a test never needs `as dynamic`
/// (spec §3.6.1). An arrowhead rather than a body because it has to say
/// which way the player is facing at 20 logical pixels, and because
/// §2.1 allows no illustration to lean on.
class FieldFigurePainter extends CustomPainter {
  FieldFigurePainter({
    required this.color,
    required this.pointsUp,
    required this.quality,
  });

  final Color color;
  final bool pointsUp;
  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..lineTo(0, 0);
    }
    path.close();

    // Filled, then outlined in its own glow: an actor is the brightest
    // thing on the field (§2.1 tier 3), and a stroke-only mark at this
    // size reads as structure rather than as a person.
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: NeonTokens.actorAlpha),
    );

    paintGlowPath(
      canvas,
      path,
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
