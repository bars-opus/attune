import 'dart:ui';

import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import 'field_ground.dart' show PaintBallNeonPalette;
import 'paint_ball_field_keys.dart';

/// What a bay is doing right now.
enum CoverBayState {
  /// One of three hiding places, not chosen.
  rest,

  /// The bay this player is shooting at. With no Fire button this state
  /// IS the confirmation that a target is chosen, so it has to read at a
  /// glance (Stage 2 addendum #2).
  aimed,

  /// Somebody is behind it. Only ever true for a position the viewer is
  /// allowed to know.
  occupied,
}

/// Everything a cover style needs to draw one bay.
///
/// A value object with public fields rather than positional arguments,
/// so adding a state later does not change every style's signature.
class CoverBayPaintContext {
  const CoverBayPaintContext({
    required this.state,
    required this.facing,
    required this.ownerColor,
    required this.quality,
  });

  final CoverBayState state;

  /// True when this is the VIEWER's own row: the arch domes upward with
  /// its legs planted below.
  ///
  /// Replaces `_ShieldPainter.opensDown` with the same polarity. A
  /// device-reported bug had both rows doming the same way, which made
  /// the opponent's cover look like it sheltered someone standing off
  /// the top of the board rather than facing you across the line.
  final bool facing;

  final Color ownerColor;
  final NeonQuality quality;
}

/// How cover is drawn.
///
/// Spec §2.3 renders cover as an ABSENCE of light -- a bay of darkness
/// rather than a drawn object -- because the game turns on hidden
/// information and hiding should look like hiding. That is the design's
/// biggest visual bet, and the spec marks it provisional.
///
/// So it lives behind this interface. Trying a solid or illustrated
/// cover later means writing a new class and passing it in, not
/// operating on the field.
abstract class PaintBallCoverStyle {
  const PaintBallCoverStyle();

  void paint(Canvas canvas, Size size, CoverBayPaintContext context);
}

/// §2.3: cover as a bay of darkness, outlined in dim light.
class DarknessCoverStyle implements PaintBallCoverStyle {
  const DarknessCoverStyle();

  @override
  void paint(Canvas canvas, Size size, CoverBayPaintContext context) {
    // A collapsed parent hands down a zero box during a route
    // transition, and an arc of radius 0 is a division waiting to
    // happen.
    if (size.isEmpty) return;

    final isAimed = context.state == CoverBayState.aimed;

    // The mouth OPENS when aimed: the legs part, so the shot has a
    // visible path through. This is the neon equivalent of the old
    // shield sliding aside, and it exists for the same reason -- a shot
    // should be something you can see a path for, not an abstract
    // selection.
    final mouth = size.width * (isAimed ? 0.34 : 0.14);
    final legInset = (size.width - mouth) / 2;

    final radius = legInset.clamp(1.0, size.width / 2);
    final shoulderY = context.facing ? radius : size.height - radius;
    final footY = context.facing ? size.height : 0.0;

    // Legs and dome as one path, open at the base -- cover you stand
    // behind, not a box you are inside.
    final path =
        Path()
          ..moveTo(legInset, footY)
          ..lineTo(legInset, shoulderY)
          ..arcToPoint(
            Offset(legInset + mouth, shoulderY),
            radius: Radius.circular(radius),
            clockwise: context.facing,
          )
          ..lineTo(legInset + mouth, footY);

    final alpha =
        isAimed
            ? NeonTokens.structureAlphaActive
            : NeonTokens.structureAlphaRest;

    // An aimed bay takes the owner's hue; a resting one stays neutral,
    // so colour keeps meaning ownership and nothing else (§2.2).
    paintGlowPath(
      canvas,
      path,
      GlowStrokeSpec(
        color: isAimed ? context.ownerColor : PaintBallNeonPalette.structure,
        alpha: alpha,
        widthScale: isAimed ? 2.0 : 1.0,
      ),
      // One extra pass when aimed, so it gains presence rather than just
      // opacity -- and still none at all on the plain tier.
      isAimed && context.quality != NeonQuality.plain
          ? context.quality.haloPasses + 1
          : context.quality.haloPasses,
    );
  }
}

/// Paints one bay through its style.
///
/// Public, with public fields, so a test asserts on `facing` directly
/// instead of reaching through `as dynamic` (spec §3.6.1).
class CoverBayPainter extends CustomPainter {
  CoverBayPainter({
    required this.state,
    required this.facing,
    required this.ownerColor,
    required this.quality,
    required this.style,
  });

  final CoverBayState state;
  final bool facing;
  final Color ownerColor;
  final NeonQuality quality;
  final PaintBallCoverStyle style;

  @override
  void paint(Canvas canvas, Size size) => style.paint(
    canvas,
    size,
    CoverBayPaintContext(
      state: state,
      facing: facing,
      ownerColor: ownerColor,
      quality: quality,
    ),
  );

  @override
  bool shouldRepaint(CoverBayPainter old) =>
      old.state != state ||
      old.facing != facing ||
      old.ownerColor != ownerColor ||
      old.quality != quality ||
      old.style != style;
}

/// One of the three hiding places.
class CoverBay extends StatelessWidget {
  const CoverBay({
    super.key,
    required this.position,
    required this.isOpponent,
    required this.state,
    required this.ownerColor,
    this.style,
  });

  final int position;
  final bool isOpponent;
  final CoverBayState state;
  final Color ownerColor;

  /// Overrides the §2.3 darkness, for trying a different cover without
  /// touching the field.
  final PaintBallCoverStyle? style;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: PaintBallFieldKeys.bay(position, isOpponent: isOpponent),
      painter: CoverBayPainter(
        state: state,
        // The viewer's own row is always the near one, whichever player
        // is looking: a field that flipped would make "mine" and
        // "theirs" something to work out each turn.
        facing: !isOpponent,
        ownerColor: ownerColor,
        quality: neonQualityOf(context),
        style: style ?? const DarknessCoverStyle(),
      ),
    );
  }
}
