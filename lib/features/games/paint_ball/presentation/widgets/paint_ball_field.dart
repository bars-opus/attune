import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The three positions a player can take, drawn as cover.
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

  /// Which cover node it landed on.
  final int position;

  /// Whose shot it was, which decides the colour.
  final bool isMine;

  /// A hit paints the cover; a miss splashes the ground beside it.
  final bool hit;

  final int round;
}

/// The Paint Ball field: two rows of cover, and the paint left on it.
///
/// The old arena was a marker sweeping across a line -- a rhythm game
/// wearing a paintball costume, where nothing you did left a mark and a
/// hit was a number changing. This draws the consequence instead: every
/// shot lands somewhere and stays there, so by the fourth round the field
/// is a record of the fight.
class PaintBallField extends StatelessWidget {
  const PaintBallField({
    super.key,
    required this.splats,
    required this.myPosition,
    required this.selectedShot,
    required this.revealedPartnerPosition,
    required this.isMyTurn,
    this.onSelectShot,
  });

  /// Every shot so far, oldest first.
  final List<PaintSplat> splats;

  /// Where I am hiding this turn, if I have chosen.
  final int? myPosition;

  /// Where I am aiming, if I have chosen.
  final int? selectedShot;

  /// Where my partner was hiding, once a shot has resolved against it.
  /// Null until the reveal -- this is the hidden information.
  final int? revealedPartnerPosition;

  final bool isMyTurn;
  final ValueChanged<int>? onSelectShot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1.15,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // The paint sits under the cover, so a splat reads as landing
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
            Padding(
              padding: EdgeInsets.all(Spacing.lg.w),
              child: Column(
                children: [
                  // Their side: what you shoot at.
                  _CoverRow(
                    isOpponent: true,
                    selected: selectedShot,
                    revealed: revealedPartnerPosition,
                    enabled: isMyTurn && onSelectShot != null,
                    onTap: onSelectShot,
                  ),
                  const Spacer(),
                  Container(
                    height: 1.h,
                    color: colorScheme.outline.withValues(alpha: 0.16),
                  ),
                  const Spacer(),
                  // Your side: where you are hiding.
                  _CoverRow(
                    isOpponent: false,
                    selected: myPosition,
                    revealed: null,
                    enabled: false,
                    onTap: null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverRow extends StatelessWidget {
  const _CoverRow({
    required this.isOpponent,
    required this.selected,
    required this.revealed,
    required this.enabled,
    required this.onTap,
  });

  final bool isOpponent;
  final int? selected;
  final int? revealed;
  final bool enabled;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = isOpponent ? colorScheme.tertiary : colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(kPaintBallPositions, (index) {
        final isSelected = selected == index;
        final wasThere = revealed == index;

        return GestureDetector(
          onTap: enabled ? () => onTap?.call(index) : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 54.w,
            height: 54.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  isSelected
                      ? base.withValues(alpha: 0.85)
                      : base.withValues(alpha: enabled ? 0.18 : 0.12),
              border: Border.all(
                color:
                    wasThere
                        ? base
                        : isSelected
                        ? base
                        : base.withValues(alpha: 0.3),
                width: wasThere ? 3.r : 1.5.r,
              ),
            ),
            child: Center(
              child:
                  wasThere
                      // Where they actually were, shown only after the
                      // shot resolves. This is the whole game: you learn
                      // it too late to use this turn, and it is the best
                      // information you have for the next one.
                      ? Icon(
                        Icons.person_rounded,
                        size: 24.h,
                        color: base,
                      )
                      : isSelected
                      ? Icon(
                        isOpponent
                            ? Icons.my_location_rounded
                            : Icons.shield_rounded,
                        size: 22.h,
                        color: colorScheme.onPrimary,
                      )
                      : null,
            ),
          ),
        );
      }),
    );
  }
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

  /// Beyond this, the oldest splats fade out. Twelve rounds of paint is
  /// already a busy field; the point is atmosphere, not a full ledger.
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
      // Newest at full strength, oldest at a quarter.
      final age = recent.length == 1 ? 1.0 : i / (recent.length - 1);
      final alpha = 0.18 + (0.32 * age);

      final colour = splat.isMine ? mineColor : theirsColor;
      final paint =
          Paint()
            ..color = colour.withValues(alpha: alpha)
            ..style = PaintingStyle.fill;

      // A splat lands on its target's row: my shots on their side (top),
      // theirs on mine (bottom).
      final rowY = splat.isMine ? size.height * 0.22 : size.height * 0.78;
      final slot = (size.width / kPaintBallPositions);
      final centreX = slot * splat.position + slot / 2;

      // A hit sits on the cover; a miss lands off to one side, so the
      // field shows near-misses as well as damage.
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

    // A couple of flecks, which is what makes it read as splatter rather
    // than a shape.
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
