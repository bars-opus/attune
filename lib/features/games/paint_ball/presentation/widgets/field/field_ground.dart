import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/light_well.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import 'paint_ball_field_keys.dart';

/// The words over the far row.
///
/// A pure function rather than logic inside a build method, because its
/// four branches are the kind of thing a widget test can only reach by
/// pumping four whole fields.
///
/// Precedence matters: the streak remark OUTRANKS the partner's name,
/// but only while a replay is on screen. Between rounds the board goes
/// back to saying who. A streak left up would be the same free clue as
/// a paint trail -- a readout of the partner's habits, which is exactly
/// what this game asks you to earn.
String fieldRowLabelText({
  required String? partnerName,
  required bool isReplaying,
  required int theirStreak,
}) {
  // From two upward. Every round is trivially a streak of one, and
  // announcing that would call out a position the player only just took.
  if (isReplaying && theirStreak > 1) return 'SAME SPOT x$theirStreak';
  if (partnerName != null) return partnerName.toUpperCase();
  return 'THEIR COVER';
}

/// One row's caption.
class FieldRowLabel extends StatelessWidget {
  const FieldRowLabel({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color.withValues(alpha: NeonTokens.structureAlphaActive),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}

/// The field's ground: near-black, a light well for a middle, and the
/// centre line dividing the two halves.
///
/// Spec §2.1 tier 1 -- it receives light and emits none. Everything the
/// field draws sits on top of this, which is why the well's alpha is as
/// low as it is: a ground bright enough to notice would compete with the
/// actors, and then nothing on the field reads as lit.
class FieldGround extends StatelessWidget {
  const FieldGround({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: PaintBallFieldKeys.ground,
      child: LightWell(
        child: Stack(
          // The divider must span the FIELD, not whatever the child
          // happens to measure. Without this the Stack sizes to its
          // children, so an unconstrained or small child collapses it
          // and the divider is painted at that child's width -- or, at
          // zero size, not painted at all.
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              right: 0,
              child: CustomPaint(
                key: PaintBallFieldKeys.divider,
                painter: FieldDividerPainter(
                  quality: neonQualityOf(context),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// The centre line.
///
/// Public, and with public fields, so a test can assert on it without
/// reaching through `as dynamic` -- the trap spec §3.6.1 exists to close.
class FieldDividerPainter extends CustomPainter {
  FieldDividerPainter({required this.quality});

  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final y = size.height / 2;
    final inset = size.width * 0.06;

    paintGlowPath(
      canvas,
      Path()
        ..moveTo(inset, y)
        ..lineTo(size.width - inset, y),
      const GlowStrokeSpec(
        color: PaintBallNeonPalette.structure,
        alpha: NeonTokens.structureAlphaRest,
      ),
      quality.haloPasses,
    );
  }

  @override
  bool shouldRepaint(FieldDividerPainter old) => old.quality != quality;
}

/// The field's own neon colours.
///
/// Separate from PaintBallPalette, which stays as it is: three screens
/// outside this work read it (history, knockout, battle), so changing
/// those values would reach past the field. These are the field's.
class PaintBallNeonPalette {
  const PaintBallNeonPalette._();

  /// Bays and the divider. Neutral, so the two owner hues stay the only
  /// colours that mean anything (§2.2).
  static const structure = Color(0xFF8A8AA0);

  /// The instant of impact, and nothing else on the field, ever (§2.2).
  static const impact = Color(0xFFFFFFFF);
}
