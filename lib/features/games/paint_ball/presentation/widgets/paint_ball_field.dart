import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The three positions a player can take, drawn as shields.
const int kPaintBallPositions = 3;

/// The field's palette is fixed rather than theme-derived.
///
/// This is a diagram, not chrome: it reads as a schematic on black, and a
/// light theme would invert the ground out from under it and leave the thin
/// neon strokes invisible. The colours also carry meaning that must not
/// drift with a theme -- green is yours, red is theirs, yellow is a player
/// and the paint in flight.
class PaintBallPalette {
  const PaintBallPalette._();

  /// The ground. Plain black, so the strokes glow rather than sit on grey.
  static const Color field = Color(0xFF000000);

  /// Yours: the mint of the reference diagram.
  static const Color mine = Color(0xFF5EEAD4);

  /// Theirs.
  static const Color theirs = Color(0xFFFF4D6A);

  /// A player, and the paint they fire. Deliberately neither side's colour:
  /// a triangle reads as a person on the field, not as a piece of the
  /// architecture around them.
  static const Color player = Color(0xFFFFC94D);

  /// The centre line dividing the two halves.
  static const Color divider = Color(0xFF2A2A2A);
}

/// A splatter left by a shot, kept so the field accumulates a record of
/// the match rather than resetting every turn.
@immutable
class PaintSplat {
  const PaintSplat({
    required this.position,
    required this.isMine,
    required this.hit,
    required this.round,
  });

  final int position;
  final bool isMine;
  final bool hit;
  final int round;
}

/// The Paint Ball field.
///
/// Your shields are always the bottom row and theirs the top, whichever
/// player you are: a field that flipped depending on who was looking
/// would make "mine" and "theirs" a thing to work out each turn rather
/// than something you simply see.
///
/// You can see your own triangle behind its shield. You cannot see
/// theirs -- that is the hidden information the whole game turns on, and
/// it appears only after a shot resolves against it.
class PaintBallField extends StatelessWidget {
  const PaintBallField({
    super.key,
    required this.splats,
    required this.myPosition,
    required this.selectedShot,
    required this.revealedPartnerPosition,
    required this.isMyTurn,
    this.shotProgress,
    this.onSelectShot,
  });

  final List<PaintSplat> splats;
  final int? myPosition;
  final int? selectedShot;
  final int? revealedPartnerPosition;
  final bool isMyTurn;

  /// 0 to 1 while a shot travels, null otherwise. Drives the projectile.
  final double? shotProgress;

  final ValueChanged<int>? onSelectShot;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = reduceMotionOf(context);

    return AspectRatio(
      aspectRatio: 1.05,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final slot = width / kPaintBallPositions;

          // Where a shot starts and ends: from my shield's row up to the
          // targeted shield.
          final originX =
              myPosition == null ? width / 2 : slot * myPosition! + slot / 2;
          final targetX =
              selectedShot == null
                  ? width / 2
                  : slot * selectedShot! + slot / 2;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
              color: PaintBallPalette.field,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Paint sits under everything, so a splat reads as landing
                // ON the field rather than floating over the pieces.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SplatPainter(
                      splats: splats,
                      mineColor: PaintBallPalette.mine,
                      theirsColor: PaintBallPalette.theirs,
                    ),
                  ),
                ),

                // Their row, at the top: what you shoot at.
                Positioned(
                  top: height * 0.035,
                  left: 0,
                  right: 0,
                  child: const _FieldLabel(
                    label: 'THEIR COVER',
                    color: PaintBallPalette.theirs,
                  ),
                ),

                Positioned(
                  top: height * 0.105,
                  left: 0,
                  right: 0,
                  child: _ShieldRow(
                    isOpponent: true,
                    hiddenAt: revealedPartnerPosition,
                    aimedAt: selectedShot,
                    enabled: isMyTurn && onSelectShot != null,
                    onTap: onSelectShot,
                    reduceMotion: reduceMotion,
                  ),
                ),

                Positioned(
                  top: height * 0.5,
                  left: Spacing.lg.w,
                  right: Spacing.lg.w,
                  child: Container(
                    height: 1.h,
                    color: PaintBallPalette.divider,
                  ),
                ),

                // Your row, at the bottom: you can see yourself.
                Positioned(
                  bottom: height * 0.035,
                  left: 0,
                  right: 0,
                  child: const _FieldLabel(
                    label: 'YOUR COVER',
                    color: PaintBallPalette.mine,
                  ),
                ),

                Positioned(
                  bottom: height * 0.105,
                  left: 0,
                  right: 0,
                  child: _ShieldRow(
                    isOpponent: false,
                    hiddenAt: myPosition,
                    aimedAt: null,
                    enabled: false,
                    onTap: null,
                    reduceMotion: reduceMotion,
                  ),
                ),

                // The travelling paintball.
                if (shotProgress != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ProjectilePainter(
                          progress: shotProgress!,
                          from: Offset(originX, height * 0.80),
                          to: Offset(targetX, height * 0.20),
                          color: PaintBallPalette.player,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color.withValues(alpha: 0.72),
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}

/// One row of three shields, with a triangle hiding behind one of them.
class _ShieldRow extends StatelessWidget {
  const _ShieldRow({
    required this.isOpponent,
    required this.hiddenAt,
    required this.aimedAt,
    required this.enabled,
    required this.onTap,
    required this.reduceMotion,
  });

  /// Where the player behind this row is hiding, when it may be shown.
  /// Always set for your own row; set for theirs only after a reveal.
  final int? hiddenAt;

  /// The shield being aimed at, which steps aside to open the shot.
  final int? aimedAt;

  final bool isOpponent;
  final bool enabled;
  final ValueChanged<int>? onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final base = isOpponent ? PaintBallPalette.theirs : PaintBallPalette.mine;

    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 320);
    final alignmentX = switch (hiddenAt) {
      0 => -0.68,
      2 => 0.68,
      _ => 0.0,
    };

    return SizedBox(
      height: 92.h,
      child: Stack(
        children: [
          // One persistent triangle travels across the whole row. Rendering a
          // triangle inside every slot only cross-fades two copies and reads as
          // teleportation rather than taking cover.
          Positioned.fill(
            child: AnimatedAlign(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment(alignmentX, isOpponent ? 0.12 : -0.12),
              child: AnimatedOpacity(
                duration:
                    reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                opacity: hiddenAt == null ? 0 : 1,
                child: CustomPaint(
                  size: Size(22.w, 20.h),
                  painter: _TrianglePainter(
                    color: PaintBallPalette.player,
                    pointsUp: !isOpponent,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: List.generate(kPaintBallPositions, (index) {
                final isAimed = aimedAt == index;
                final positionName = paintBallPositionName(index);

                return Expanded(
                  child: Semantics(
                    button: enabled,
                    enabled: enabled,
                    selected: isAimed,
                    label:
                        isOpponent
                            ? '$positionName target'
                            : '$positionName cover',
                    hint: enabled ? 'Select where to shoot' : null,
                    child: GestureDetector(
                      onTap: enabled ? () => onTap?.call(index) : null,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox.expand(
                        child: Center(
                          child: AnimatedSlide(
                            duration:
                                reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            offset:
                                isAimed ? const Offset(0.20, 0) : Offset.zero,
                            child: AnimatedOpacity(
                              duration:
                                  reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                              opacity:
                                  isAimed
                                      ? 1
                                      : enabled
                                      ? 0.75
                                      : 0.58,
                              child: CustomPaint(
                                size: Size(38.w, 62.h),
                                painter: _ShieldPainter(
                                  color: base,
                                  strokeWidth: isAimed ? 2.4.r : 1.6.r,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

String paintBallPositionName(int position) => switch (position) {
  0 => 'Left',
  1 => 'Middle',
  2 => 'Right',
  _ => 'Unknown',
};

/// A shield, drawn as the reference's outlined arch: straight legs, a
/// rounded top, and an open base. Stroked rather than filled -- the whole
/// field is a line diagram, and a solid block would read as a wall rather
/// than as cover you are standing behind.
class _ShieldPainter extends CustomPainter {
  _ShieldPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    final radius = size.width / 2;
    final path =
        Path()
          ..moveTo(0, size.height)
          ..lineTo(0, radius)
          ..arcToPoint(
            Offset(size.width, radius),
            radius: Radius.circular(radius),
            clockwise: true,
          )
          ..lineTo(size.width, size.height);

    canvas.drawPath(path, paint);

    // The dots that cap each leg in the reference diagram.
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(0, radius), strokeWidth * 1.6, dot);
    canvas.drawCircle(Offset(size.width, radius), strokeWidth * 1.6, dot);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color, required this.pointsUp});

  final Color color;
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    if (pointsUp) {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
      path.lineTo(0, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) =>
      old.color != color || old.pointsUp != pointsUp;
}

/// The paintball in flight, with a short trail behind it.
class _ProjectilePainter extends CustomPainter {
  _ProjectilePainter({
    required this.progress,
    required this.from,
    required this.to,
    required this.color,
  });

  final double progress;
  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeInOutCubic.transform(progress.clamp(0, 1));
    final control = Offset(
      (from.dx + to.dx) / 2 + (to.dx - from.dx) * 0.08,
      math.min(from.dy, to.dy) - size.height * 0.08,
    );
    final position = _quadratic(from, control, to, eased);

    // A trail rather than a bare dot: at this speed a single circle reads
    // as a jump between frames rather than a thing travelling.
    for (var i = 1; i <= 5; i++) {
      final trailAt = (eased - i * 0.035).clamp(0.0, 1.0);
      final point = _quadratic(from, control, to, trailAt);
      canvas.drawCircle(
        point,
        7.0 - i * 0.9,
        Paint()..color = color.withValues(alpha: 0.42 - i * 0.07),
      );
    }

    // A soft halo under the ball so it reads as lit on black rather than
    // as a flat sticker.
    canvas.drawCircle(
      position,
      12,
      Paint()..color = color.withValues(alpha: 0.22),
    );
    canvas.drawCircle(position, 7, Paint()..color = color);
  }

  Offset _quadratic(Offset start, Offset control, Offset end, double t) {
    final inverse = 1 - t;
    return Offset(
      inverse * inverse * start.dx +
          2 * inverse * t * control.dx +
          t * t * end.dx,
      inverse * inverse * start.dy +
          2 * inverse * t * control.dy +
          t * t * end.dy,
    );
  }

  @override
  bool shouldRepaint(_ProjectilePainter old) => old.progress != progress;
}

/// Draws the paint. Older splats fade rather than being dropped, so a
/// long match stays readable instead of turning into mud.
class _SplatPainter extends CustomPainter {
  _SplatPainter({
    required this.splats,
    required this.mineColor,
    required this.theirsColor,
  });

  final List<PaintSplat> splats;
  final Color mineColor;
  final Color theirsColor;

  static const _visible = 12;

  @override
  void paint(Canvas canvas, Size size) {
    if (splats.isEmpty) return;

    final recent =
        splats.length <= _visible
            ? splats
            : splats.sublist(splats.length - _visible);

    for (var i = 0; i < recent.length; i++) {
      final splat = recent[i];
      final age = recent.length == 1 ? 1.0 : i / (recent.length - 1);
      final alpha = 0.18 + (0.32 * age);

      final colour = splat.isMine ? mineColor : theirsColor;
      final paint =
          Paint()
            ..color = colour.withValues(alpha: alpha)
            ..style = PaintingStyle.fill;

      final rowY = splat.isMine ? size.height * 0.20 : size.height * 0.80;
      final slot = size.width / kPaintBallPositions;
      final centreX = slot * splat.position + slot / 2;

      final seed = splat.round * 31 + splat.position * 7;
      final rng = math.Random(seed);
      final offsetX = splat.hit ? 0.0 : (rng.nextDouble() - 0.5) * slot * 0.8;
      final offsetY = (rng.nextDouble() - 0.5) * 18;

      _drawSplat(
        canvas,
        Offset(centreX + offsetX, rowY + offsetY),
        splat.hit ? 26.0 : 16.0,
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
  bool shouldRepaint(_SplatPainter oldDelegate) =>
      oldDelegate.splats.length != splats.length ||
      List.generate(splats.length, (index) {
        final current = splats[index];
        final old = oldDelegate.splats[index];
        return current.round != old.round ||
            current.position != old.position ||
            current.isMine != old.isMine ||
            current.hit != old.hit;
      }).any((changed) => changed);
}
