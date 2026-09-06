import 'dart:math' as math;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  /// 0 to 1 while a shot travels, null otherwise. Drives the projectile.
  final double? shotProgress;

  final ValueChanged<int>? onSelectShot;

  /// Tapping your own cover moves you there. Null disables repositioning.
  final ValueChanged<int>? onSelectHide;

  /// Tapping your own triangle fires, once a target is chosen.
  final VoidCallback? onFire;

  /// 0 to 1 while a resolved round replays, null otherwise. During a replay
  /// BOTH sides emerge, aim and fire, so it drives more than the shot alone.
  final double? replayProgress;

  /// Where the opponent shot during the replay. Only known once the round
  /// resolved, which is the same moment their position becomes visible.
  final int? theirRevealedShot;

  /// A round is playing back. Both sides emerge and fire; the board is not
  /// accepting input.
  final bool isReplaying;

  /// Whose cover the top row is. Named rather than "THEIR COVER" because
  /// the person across the field is someone specific, and this app is
  /// about that person -- a generic pronoun makes them an opponent.
  final String? partnerName;

  /// Rounds running they have held the same cover. Shown only from two,
  /// and only during a replay -- it is a remark on what you just watched,
  /// not a readout kept on the board.
  final int theirStreak;

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

          // The replay's four beats. Emerging and aiming are given room to
          // read before anything is fired -- the point of the replay is
          // seeing the two decisions meet, and a shot that left before the
          // aim landed would skip the part worth watching.
          final replay = replayProgress;
          final emerged = replay == null || replay > 0.12;
          final aimed = replay == null || replay > 0.34;
          final firing = replay != null && replay > 0.52;
          // Remapped so the paintball still crosses the whole field in the
          // slice of the replay given to flight.
          final flightProgress =
              firing ? ((replay - 0.52) / 0.34).clamp(0.0, 1.0) : null;

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
                  child: _FieldLabel(
                    // Staying put is the most interesting thing a player
                    // can do -- it is stubbornness, or a bluff, or a dare
                    // to try the same spot twice -- and it goes unnoticed
                    // unless someone is counting. So the board counts.
                    label:
                        isReplaying && theirStreak > 1
                            ? 'SAME SPOT x$theirStreak'
                            : partnerName == null
                            ? 'THEIR COVER'
                            : partnerName!.toUpperCase(),
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
                    aimingAt: aimed ? theirRevealedShot : null,
                    emerged: emerged,
                    aimedAt: selectedShot,
                    enabled: isMyTurn && onSelectShot != null,
                    onTap: onSelectShot,
                    onTapCharacter: null,
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
                    // Your own triangle tilts toward whatever you are
                    // aiming at, so the aim is visible on the field
                    // rather than only in a control strip.
                    aimingAt: aimed ? selectedShot : null,
                    emerged: emerged,
                    aimedAt: null,
                    enabled: isMyTurn && onSelectHide != null,
                    onTap: onSelectHide,
                    onTapCharacter: onFire,
                    reduceMotion: reduceMotion,
                  ),
                ),

                // The replay's two paintballs, in flight at once. Both
                // players fired without seeing the other, so the shots
                // must cross rather than take turns -- watching them
                // pass mid-air is the moment the round becomes a duel
                // rather than two separate turns.
                if (flightProgress != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ProjectilePainter(
                          progress: flightProgress,
                          from: Offset(
                            myPosition == null
                                ? width / 2
                                : slot * myPosition! + slot / 2,
                            height * 0.80,
                          ),
                          to: Offset(
                            selectedShot == null
                                ? width / 2
                                : slot * selectedShot! + slot / 2,
                            height * 0.20,
                          ),
                          color: PaintBallPalette.player,
                        ),
                      ),
                    ),
                  ),
                if (flightProgress != null && theirRevealedShot != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ProjectilePainter(
                          progress: flightProgress,
                          from: Offset(
                            revealedPartnerPosition == null
                                ? width / 2
                                : slot * revealedPartnerPosition! + slot / 2,
                            height * 0.20,
                          ),
                          to: Offset(
                            slot * theirRevealedShot! + slot / 2,
                            height * 0.80,
                          ),
                          color: PaintBallPalette.player,
                        ),
                      ),
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
///
/// The row is the controller as well as the picture: tapping a shield is
/// how a player repositions or aims, and tapping the triangle fires. A
/// separate button strip would teach the player the board is a picture.
class _ShieldRow extends StatelessWidget {
  const _ShieldRow({
    required this.isOpponent,
    required this.hiddenAt,
    required this.aimedAt,
    required this.enabled,
    required this.onTap,
    required this.reduceMotion,
    this.aimingAt,
    this.onTapCharacter,
    this.emerged = true,
  });

  /// Where the player behind this row is hiding, when it may be shown.
  /// Always set for your own row; set for theirs only after a reveal.
  final int? hiddenAt;

  /// The shield being aimed at, which steps aside to open the shot.
  final int? aimedAt;

  /// Where the occupant of THIS row is pointing. Drives the triangle's
  /// tilt, so an aim is something you can see rather than infer.
  final int? aimingAt;

  final bool isOpponent;
  final bool enabled;
  final ValueChanged<int>? onTap;
  final VoidCallback? onTapCharacter;

  /// False during the first beat of a replay, while both players are
  /// still behind cover and about to step out.
  final bool emerged;

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final base = isOpponent ? PaintBallPalette.theirs : PaintBallPalette.mine;
    final isAiming = aimingAt != null && hiddenAt != null && emerged;

    // Per-column lean, in TURNS. Kept small deliberately: the tilt says
    // which cover is being aimed at, and a triangle rotated far enough to
    // lose its "pointing" silhouette stops communicating that at all.
    final rowTilt =
        isAiming
            ? (aimingAt! - hiddenAt!) * (isOpponent ? -0.045 : 0.045)
            : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 92.h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _coverRow(context, base),
              // One triangle for the whole row, so it can cross between
              // covers as a single body.
              if (hiddenAt != null)
                _TravellingPlayer(
                  position: hiddenAt!,
                  isOpponent: isOpponent,
                  rowWidth: constraints.maxWidth,
                  coverWidth:
                      kPaintBallCoverWidth.w *
                      (isOpponent ? kPaintBallTargetScale : 1),
                  rowHeight: 92.h,
                  isAiming: isAiming,
                  tilt: rowTilt,
                  reduceMotion: reduceMotion,
                  onTap: onTapCharacter,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _coverRow(BuildContext context, Color base) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(kPaintBallPositions, (index) {
        final isAimed = aimedAt == index;

        return Semantics(
          // container: true so this becomes its own node rather than
          // merging into the row -- without it a screen reader announces
          // one undifferentiated strip instead of three targets.
          container: true,
          button: enabled,
          // Named by position rather than index: a screen-reader user
          // hears "Middle target", which is the thing on the board, not
          // "cover 2", which is an implementation detail.
          label:
              isOpponent
                  ? '${paintBallPositionName(index)} target'
                  : '${paintBallPositionName(index)} cover',
          child: GestureDetector(
            onTap: enabled ? () => onTap?.call(index) : null,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width:
                  kPaintBallCoverWidth.w *
                  (isOpponent ? kPaintBallTargetScale : 1),
              height: 92.h,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // The shield. When aimed at, it slides aside to open a
                  // clear line -- so a shot is something you can see a path
                  // for, not an abstract selection.
                  AnimatedPositioned(
                    duration: Duration(milliseconds: reduceMotion ? 0 : 260),
                    curve: Curves.easeOutBack,
                    left: isAimed ? 30.w : 18.w,
                    bottom: isOpponent ? 8.h : null,
                    top: isOpponent ? null : 8.h,
                    child: AnimatedOpacity(
                      duration: Duration(milliseconds: reduceMotion ? 0 : 220),
                      // A wide gap between aimed and not. With no Fire
                      // button, the aimed cover IS the confirmation that
                      // a target is chosen, so it has to be obvious at a
                      // glance rather than a subtle tint.
                      opacity:
                          isAimed
                              ? 1.0
                              : enabled
                              ? 0.45
                              : 0.35,
                      child: CustomPaint(
                        size: Size(
                          38.w * (isOpponent ? kPaintBallTargetScale : 1),
                          62.h * (isOpponent ? kPaintBallTargetScale : 1),
                        ),
                        painter: _ShieldPainter(
                          color: base,
                          strokeWidth: isAimed ? 3.4.r : 1.5.r,
                          opensDown: isOpponent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
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
  _ShieldPainter({
    required this.color,
    required this.strokeWidth,
    required this.opensDown,
  });

  final Color color;
  final double strokeWidth;

  /// Which way the arch's open side faces.
  ///
  /// The two rows face each other across the centre line: yours domes
  /// upward with its legs planted below, theirs domes downward with its
  /// legs above. Drawing both the same way made the opponent's cover look
  /// like it was sheltering someone standing off the top of the board
  /// rather than facing you.
  final bool opensDown;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    final radius = size.width / 2;

    // The shoulder is where the legs meet the arc: near the top for a
    // cover that domes upward, near the bottom for one that domes down.
    final shoulderY = opensDown ? size.height - radius : radius;
    final footY = opensDown ? 0.0 : size.height;

    final path =
        Path()
          ..moveTo(0, footY)
          ..lineTo(0, shoulderY)
          ..arcToPoint(
            Offset(size.width, shoulderY),
            radius: Radius.circular(radius),
            // Sweeping the other way is what turns the dome over.
            clockwise: !opensDown,
          )
          ..lineTo(size.width, footY);

    canvas.drawPath(path, paint);

    // The dots that cap each leg in the reference diagram.
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(0, shoulderY), strokeWidth * 1.6, dot);
    canvas.drawCircle(Offset(size.width, shoulderY), strokeWidth * 1.6, dot);
  }

  @override
  bool shouldRepaint(_ShieldPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.opensDown != opensDown;
}

/// A player's triangle, travelling across its whole row.
///
/// Repositioning is a journey, not a cross-fade. A triangle that faded out
/// of one cover and into another would read as two triangles; this one
/// leaves cover, crosses, and enters the new cover as a single body, which
/// is what makes taking cover feel like moving rather than being
/// reassigned.
///
/// Three beats:
///   1. BACK  -- step out of the current cover, away from the line
///   2. ACROSS -- travel laterally to the new column
///   3. FORWARD -- settle into the new cover
///
/// It lives above the row rather than inside a cover because a child
/// cannot travel outside its parent's box, which is exactly what a journey
/// between covers requires.
class _TravellingPlayer extends StatefulWidget {
  const _TravellingPlayer({
    required this.position,
    required this.isOpponent,
    required this.rowWidth,
    required this.coverWidth,
    required this.rowHeight,
    required this.isAiming,
    required this.tilt,
    required this.reduceMotion,
    this.onTap,
  });

  final int position;
  final bool isOpponent;

  /// The full row, and one cover inside it. Both are needed because the
  /// covers are a fixed width laid out with even gaps, so their spacing
  /// is not simply the row divided three ways.
  final double rowWidth;
  final double coverWidth;

  final double rowHeight;
  final bool isAiming;
  final double tilt;
  final bool reduceMotion;
  final VoidCallback? onTap;

  @override
  State<_TravellingPlayer> createState() => _TravellingPlayerState();
}

class _TravellingPlayerState extends State<_TravellingPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _from;
  late int _to;

  @override
  void initState() {
    super.initState();
    _from = widget.position;
    _to = widget.position;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(_TravellingPlayer old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      _from = old.position;
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // The lateral move happens in the MIDDLE of the journey, so the
        // triangle is clear of cover while it crosses. Sliding sideways
        // while still tucked in would read as passing through the wall.
        final lateral = Curves.easeInOut.transform(
          ((t - 0.25) / 0.5).clamp(0.0, 1.0),
        );
        final column = _from + (_to - _from) * lateral;

        // Depth: 0 is tucked in cover, 1 is stepped out. It rises for the
        // crossing and falls again on arrival -- and stays out while
        // aiming, since an aiming player is deliberately exposed.
        final travelling = _controller.value < 1;
        final depth =
            travelling
                ? Curves.easeInOut.transform(1 - (2 * t - 1).abs())
                : (widget.isAiming ? 1.0 : 0.0);

        // Centre on the COVER, not on a notional slot.
        //
        // spaceEvenly lays three fixed-width covers out with four equal
        // gaps, so a cover's centre is gap*(i+1) + coverWidth*(i+0.5) --
        // which equals a slot centre only when the row happens to be
        // exactly three covers wide. Using slot maths drifted the triangle
        // off-centre everywhere else, worst at the outer covers.
        final gap =
            (widget.rowWidth - kPaintBallPositions * widget.coverWidth) /
            (kPaintBallPositions + 1);
        final coverCentre =
            gap * (column + 1) + widget.coverWidth * (column + 0.5);
        final x = coverCentre - 11.w;
        // Both rows shelter under their own dome, and the domes now face
        // each other -- yours crowns at the top of its box, theirs at the
        // bottom. So "tucked in" is measured from opposite edges, and a
        // single inset would have put the opponent outside their arch
        // entirely, standing on top of the cover instead of behind it.
        final baseInset = widget.isOpponent ? 46.h : 34.h;
        final stepOut = 14.h * depth;

        return Positioned(
          left: x,
          top: widget.isOpponent ? baseInset + stepOut : null,
          bottom: widget.isOpponent ? null : baseInset + stepOut,
          // The triangle only takes taps when it IS the fire control.
          // Otherwise it must be transparent to them: it stands over a
          // cover that is itself a tap target, and intercepting there
          // would make the cover beneath it unreachable -- silently
          // costing the player one of their three hiding places.
          child: IgnorePointer(
            ignoring: widget.onTap == null,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedRotation(
                duration: Duration(milliseconds: widget.reduceMotion ? 0 : 260),
                curve: Curves.easeOut,
                turns: widget.isAiming ? widget.tilt : 0,
                child: CustomPaint(
                  size: Size(22.w, 20.h),
                  painter: _TrianglePainter(
                    color: PaintBallPalette.player,
                    pointsUp: !widget.isOpponent,
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
