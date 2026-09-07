import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_board.dart';
import 'package:flutter/material.dart';

/// The die, and the only control in the game.
///
/// Tumbles while a roll is in flight, then settles on its face. The
/// tumble is not decoration: the result arrives from the server in
/// milliseconds, and landing instantly on a number would make the roll
/// feel decided rather than rolled.
class SnakesDie extends StatelessWidget {
  const SnakesDie({
    super.key,
    required this.face,
    required this.rolling,
    this.onTap,
    this.enabled = true,
  });

  /// The settled face, or null before the first roll.
  final int? face;
  final bool rolling;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = reduceMotionOf(context);
    final interactive = enabled && onTap != null && !rolling;

    return Semantics(
      button: interactive,
      label:
          rolling
              ? 'Rolling'
              : face == null
              ? 'Roll the die'
              : 'Die showing $face',
      child: GestureDetector(
        onTap: interactive ? onTap : null,
        child: AnimatedOpacity(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
          opacity: interactive || rolling ? 1 : 0.4,
          child: SizedBox(
            width: 96,
            height: 96,
            child:
                rolling && !reduceMotion
                    ? const _TumblingDie()
                    : CustomPaint(painter: _DieFacePainter(face ?? 1)),
          ),
        ),
      ),
    );
  }
}

class _TumblingDie extends StatefulWidget {
  const _TumblingDie();

  @override
  State<_TumblingDie> createState() => _TumblingDieState();
}

class _TumblingDieState extends State<_TumblingDie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..repeat();

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
        // Cycles faces while it turns, so the tumble looks like a die
        // rather than a spinning square.
        final face = 1 + (_controller.value * 6).floor() % 6;
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: CustomPaint(painter: _DieFacePainter(face)),
        );
      },
    );
  }
}

class _DieFacePainter extends CustomPainter {
  _DieFacePainter(this.face);

  final int face;

  /// Pip positions in unit coordinates, the standard arrangement.
  static const _pips = <int, List<Offset>>{
    1: [Offset(0.5, 0.5)],
    2: [Offset(0.28, 0.28), Offset(0.72, 0.72)],
    3: [Offset(0.28, 0.28), Offset(0.5, 0.5), Offset(0.72, 0.72)],
    4: [
      Offset(0.28, 0.28),
      Offset(0.72, 0.28),
      Offset(0.28, 0.72),
      Offset(0.72, 0.72),
    ],
    5: [
      Offset(0.28, 0.28),
      Offset(0.72, 0.28),
      Offset(0.5, 0.5),
      Offset(0.28, 0.72),
      Offset(0.72, 0.72),
    ],
    6: [
      Offset(0.28, 0.24),
      Offset(0.72, 0.24),
      Offset(0.28, 0.5),
      Offset(0.72, 0.5),
      Offset(0.28, 0.76),
      Offset(0.72, 0.76),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(6);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = SnakesPalette.you,
    );

    final pip = Paint()..color = SnakesPalette.you;
    for (final position in _pips[face] ?? _pips[1]!) {
      canvas.drawCircle(
        Offset(
          rect.left + rect.width * position.dx,
          rect.top + rect.height * position.dy,
        ),
        size.width * 0.055,
        pip,
      );
    }
  }

  @override
  bool shouldRepaint(_DieFacePainter old) => old.face != face;
}
