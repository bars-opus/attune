import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/neon/attune_neon_quality.dart';
import 'package:attune/core/ui/neon/bloom_flash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'field/cover_row.dart';
import 'field/field_figure.dart' show figureCentreX;
import 'field/field_ground.dart';
import 'field/field_paint.dart';
import 'field/field_replay.dart';
import 'field/paint_ball_field_keys.dart';

/// The three positions a player can take, drawn as shields.
const int kPaintBallPositions = 3;

/// The width of one cover's box, in design units.
///
/// Shared by the row that lays the covers out and the triangle that
/// travels between them: when those two disagreed about how wide a cover
/// was, the character drifted off-centre.
const double kPaintBallCoverWidth = 74;

/// How much larger the opponent's covers are drawn than your own.
///
/// You are aiming AT their row and merely standing in yours, so theirs
/// are the targets and want the bigger, more forgiving surface. It also
/// gives the board a shallow sense of depth -- the thing you are shooting
/// at reads as the thing you are facing.
const double kPaintBallTargetScale = 1.22;

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
    this.onSelectHide,
    this.onFire,
    this.replayProgress,
    this.theirRevealedShot,
    this.isReplaying = false,
    this.partnerName,
    this.theirStreak = 1,
  });

  final List<PaintSplat> splats;
  final int? myPosition;
  final int? selectedShot;
  final int? revealedPartnerPosition;
  final bool isMyTurn;

  /// 0 to 1 while a shot travels, null otherwise.
  final double? shotProgress;

  final ValueChanged<int>? onSelectShot;

  /// Tapping your own cover moves you there. Null disables repositioning.
  final ValueChanged<int>? onSelectHide;

  /// Tapping your own figure fires, once a target is chosen.
  final VoidCallback? onFire;

  /// 0 to 1 while a resolved round replays. During a replay BOTH sides
  /// emerge, aim and fire, so it drives more than the shot alone.
  final double? replayProgress;

  /// Where the opponent shot during the replay.
  final int? theirRevealedShot;

  final bool isReplaying;

  /// Whose cover the far row is. Named rather than "THEIR COVER"
  /// because the person across the field is someone specific.
  final String? partnerName;

  /// Rounds running they have held the same cover.
  final int theirStreak;

  @override
  Widget build(BuildContext context) {
    // Read here and passed down. The component widgets take a plain
    // bool, so this is the only place the OS setting can enter -- and
    // defaulting it to false would turn every reduce-motion guarantee
    // below it silently off.
    final reduceMotion = reduceMotionOf(context);

    // Declared HERE rather than at a route or a menu, because this is
    // the widget that consumes the tiering and no routing decision can
    // bypass it. The first attempt put it in the games hub's theme
    // wrapper, which covers only the picker sheet -- the games are
    // separate routes that never pass through it.
    return AttuneNeonQuality.wrap(
      context,
      child: AspectRatio(
      aspectRatio: 1.05,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          // The replay's beats. Emerging and aiming are given room to
          // read before anything is fired: the point of the replay is
          // seeing the two decisions meet, and a shot that left before
          // the aim landed would skip the part worth watching.
          // One mapping from the controller's value to the beats, so the
          // field reads timing rather than deciding it (§3.2).
          final beats = ReplayBeats.from(replayProgress);

          // Both rows' geometry comes from the one formula the figures
          // and paint already use, so a projectile cannot leave from
          // somewhere its shooter is not standing.
          double columnX(int? position, {required bool isOpponent}) {
            if (position == null) return width / 2;
            return figureCentreX(
              rowWidth: width,
              coverWidth:
                  kPaintBallCoverWidth.w *
                  (isOpponent ? kPaintBallTargetScale : 1),
              column: position.toDouble(),
            );
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
            child: FieldGround(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Paint sits under everything, so a splat reads as
                  // landing ON the field rather than floating over the
                  // pieces.
                  Positioned.fill(
                    child: FieldPaint(
                      splats: splats,
                      mineColor: PaintBallPalette.mine,
                      theirsColor: PaintBallPalette.theirs,
                    ),
                  ),

                  Positioned(
                    top: height * 0.035,
                    left: 0,
                    right: 0,
                    child: FieldRowLabel(
                      label: fieldRowLabelText(
                        partnerName: partnerName,
                        isReplaying: isReplaying,
                        theirStreak: theirStreak,
                      ),
                      color: PaintBallPalette.theirs,
                    ),
                  ),

                  Positioned(
                    top: height * 0.105,
                    left: 0,
                    right: 0,
                    child: CoverRow(
                      isOpponent: true,
                      hiddenAt: revealedPartnerPosition,
                      aimedAt: selectedShot,
                      aimingAt: beats.aimed ? theirRevealedShot : null,
                      emerged: beats.emerged,
                      enabled: isMyTurn && onSelectShot != null,
                      ownerColor: PaintBallPalette.theirs,
                      reduceMotion: reduceMotion,
                      onTap: onSelectShot,
                    ),
                  ),

                  Positioned(
                    bottom: height * 0.035,
                    left: 0,
                    right: 0,
                    child: const FieldRowLabel(
                      label: 'YOUR COVER',
                      color: PaintBallPalette.mine,
                    ),
                  ),

                  Positioned(
                    bottom: height * 0.105,
                    left: 0,
                    right: 0,
                    child: CoverRow(
                      isOpponent: false,
                      hiddenAt: myPosition,
                      aimedAt: null,
                      // Your own figure leans toward whatever you are
                      // aiming at, so the aim is visible on the field
                      // rather than only in a control strip.
                      aimingAt: beats.aimed ? selectedShot : null,
                      emerged: beats.emerged,
                      enabled: isMyTurn && onSelectHide != null,
                      ownerColor: PaintBallPalette.mine,
                      reduceMotion: reduceMotion,
                      onTap: onSelectHide,
                      onTapFigure: onFire,
                    ),
                  ),

                  // The replay's two paintballs, in flight at once.
                  // Both players fired without seeing the other, so the
                  // shots cross rather than take turns -- watching them
                  // pass is the moment the round becomes a duel rather
                  // than two separate moves.
                  // The ball stops being drawn the moment it lands: the
                  // bloom takes over. Left up, it sat ON its own impact
                  // and the frame read as a ball wearing a glow rather
                  // than as something arriving.
                  if (beats.firing && !beats.impacting)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: PaintBallFieldKeys.projectile(isMine: true),
                          painter: ProjectilePainter(
                            progress: beats.flightProgress!,
                            from: Offset(
                              columnX(myPosition, isOpponent: false),
                              height * 0.80,
                            ),
                            to: Offset(
                              columnX(selectedShot, isOpponent: true),
                              height * 0.20,
                            ),
                            color: PaintBallPalette.mine,
                          ),
                        ),
                      ),
                    ),
                  if (beats.firing && !beats.impacting && theirRevealedShot != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: PaintBallFieldKeys.projectile(isMine: false),
                          painter: ProjectilePainter(
                            progress: beats.flightProgress!,
                            from: Offset(
                              columnX(
                                revealedPartnerPosition,
                                isOpponent: true,
                              ),
                              height * 0.20,
                            ),
                            to: Offset(
                              columnX(theirRevealedShot, isOpponent: false),
                              height * 0.80,
                            ),
                            color: PaintBallPalette.theirs,
                          ),
                        ),
                      ),
                    ),

                  // A single shot outside a replay.
                  if (shotProgress != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: PaintBallFieldKeys.projectile(isMine: true),
                          painter: ProjectilePainter(
                            progress: shotProgress!,
                            from: Offset(
                              columnX(myPosition, isOpponent: false),
                              height * 0.80,
                            ),
                            to: Offset(
                              columnX(selectedShot, isOpponent: true),
                              height * 0.20,
                            ),
                            color: PaintBallPalette.mine,
                          ),
                        ),
                      ),
                    ),

                  // Beats 5 and 6: the shots land. §2.6's hero moment --
                  // a white instant, then the shooter's paint blooming
                  // outward. The bloom carries the SHOOTER's hue, not
                  // the target's: it is their paint arriving.
                  if (beats.impacting && selectedShot != null)
                    Positioned.fill(
                      child: BloomFlash(
                        at: Offset(
                          columnX(selectedShot, isOpponent: true),
                          height * 0.20,
                        ),
                        color: PaintBallPalette.mine,
                        progress: beats.impactProgress ?? 0,
                        hit: revealedPartnerPosition == selectedShot,
                      ),
                    ),
                  if (beats.impacting && theirRevealedShot != null)
                    Positioned.fill(
                      child: BloomFlash(
                        at: Offset(
                          columnX(theirRevealedShot, isOpponent: false),
                          height * 0.80,
                        ),
                        color: PaintBallPalette.theirs,
                        hit: myPosition == theirRevealedShot,
                        progress: beats.impactProgress ?? 0,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
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

/// The paintball in flight, with a short trail behind it.
/// The paintball in flight.
///
/// Public, with public fields, so a test reads `progress` directly
/// rather than through `as dynamic` on a privately-named painter -- the
/// trap spec §3.6.1 exists to close. Kept in this file for now: the
/// replay is Stage 4's work and moving it would change flight behaviour
/// in a commit that is only meant to compose.
class ProjectilePainter extends CustomPainter {
  ProjectilePainter({
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
  bool shouldRepaint(ProjectilePainter old) => old.progress != progress;
}

