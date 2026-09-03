import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The three positions a player can take, drawn as shields.
const int kPaintBallPositions = 3;

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
    final colorScheme = Theme.of(context).colorScheme;

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
              myPosition == null
                  ? width / 2
                  : slot * myPosition! + slot / 2;
          final targetX =
              selectedShot == null
                  ? width / 2
                  : slot * selectedShot! + slot / 2;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.35,
              ),
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
                      mineColor: colorScheme.primary,
                      theirsColor: colorScheme.tertiary,
                    ),
                  ),
                ),

                // Their row, at the top: what you shoot at.
                Positioned(
                  top: height * 0.12,
                  left: 0,
                  right: 0,
                  child: _ShieldRow(
                    isOpponent: true,
                    hiddenAt: revealedPartnerPosition,
                    aimedAt: selectedShot,
                    enabled: isMyTurn && onSelectShot != null,
                    onTap: onSelectShot,
                  ),
                ),

                Positioned(
                  top: height * 0.5,
                  left: Spacing.lg.w,
                  right: Spacing.lg.w,
                  child: Container(
                    height: 1.h,
                    color: colorScheme.outline.withValues(alpha: 0.16),
                  ),
                ),

                // Your row, at the bottom: you can see yourself.
                Positioned(
                  bottom: height * 0.12,
                  left: 0,
                  right: 0,
                  child: _ShieldRow(
                    isOpponent: false,
                    hiddenAt: myPosition,
                    aimedAt: null,
                    enabled: false,
                    onTap: null,
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
                          color: colorScheme.primary,
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

/// One row of three shields, with a triangle hiding behind one of them.
class _ShieldRow extends StatelessWidget {
  const _ShieldRow({
    required this.isOpponent,
    required this.hiddenAt,
    required this.aimedAt,
    required this.enabled,
    required this.onTap,
  });

  /// Where the player behind this row is hiding, when it may be shown.
  /// Always set for your own row; set for theirs only after a reveal.
  final int? hiddenAt;

  /// The shield being aimed at, which steps aside to open the shot.
  final int? aimedAt;

  final bool isOpponent;
  final bool enabled;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = isOpponent ? colorScheme.tertiary : colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(kPaintBallPositions, (index) {
        final isAimed = aimedAt == index;
        final isOccupied = hiddenAt == index;

        return GestureDetector(
          onTap: enabled ? () => onTap?.call(index) : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 74.w,
            height: 78.h,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The triangle sits BEHIND its shield, and slides between
                // positions rather than teleporting -- the movement is
                // what makes taking cover read as an action.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  // Opponent triangles peek above their shield; yours
                  // below, so each stays on its own side of the line.
                  top: isOpponent ? 6.h : null,
                  bottom: isOpponent ? null : 6.h,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: isOccupied ? 1 : 0,
                    child: CustomPaint(
                      size: Size(26.w, 24.h),
                      painter: _TrianglePainter(
                        color: base,
                        pointsUp: !isOpponent,
                      ),
                    ),
                  ),
                ),

                // The shield. When aimed at, it slides aside to open a
                // clear line -- so a shot is something you can see a path
                // for, not an abstract selection.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  left: isAimed ? 22.w : 0,
                  right: isAimed ? 0 : 0,
                  bottom: isOpponent ? 8.h : null,
                  top: isOpponent ? null : 8.h,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 52.w,
                    height: 34.h,
                    decoration: BoxDecoration(
                      color: base.withValues(
                        alpha:
                            isAimed
                                ? 0.9
                                : enabled
                                ? 0.42
                                : 0.30,
                      ),
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.sm.r,
                      ),
                      border: Border.all(
                        color: base.withValues(alpha: isAimed ? 1 : 0.45),
                        width: isAimed ? 2.r : 1.r,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
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
    final position = Offset.lerp(from, to, progress)!;

    // A trail rather than a bare dot: at this speed a single circle reads
    // as a jump between frames rather than a thing travelling.
    for (var i = 0; i < 4; i++) {
      final trailAt = (progress - i * 0.06).clamp(0.0, 1.0);
      final point = Offset.lerp(from, to, trailAt)!;
      canvas.drawCircle(
        point,
        7.0 - i * 1.4,
        Paint()..color = color.withValues(alpha: 0.55 - i * 0.12),
      );
    }

    canvas.drawCircle(position, 7, Paint()..color = color);
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
      oldDelegate.splats.length != splats.length;
}
