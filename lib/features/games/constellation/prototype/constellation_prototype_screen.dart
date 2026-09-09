import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/constellation/prototype/constellation_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// THROWAWAY PROTOTYPE — pass-and-play on one device.
///
/// Two questions a spec cannot answer, and this is the cheapest way to
/// ask them:
///
///   1. Does a game with no stakes feel worth opening?
///   2. Does the finished picture read as something two people MADE,
///      or as a progress bar with stars on it?
///
/// Everything server-shaped is deliberately absent. The scene format and
/// the turn rules are the only parts meant to survive.
class ConstellationPrototypeScreen extends StatefulWidget {
  const ConstellationPrototypeScreen({super.key});

  @override
  State<ConstellationPrototypeScreen> createState() =>
      _ConstellationPrototypeScreenState();
}

class _ConstellationPrototypeScreenState
    extends State<ConstellationPrototypeScreen>
    with SingleTickerProviderStateMixin {
  SessionState? _session;
  String? _error;
  int? _pressing;

  /// For the golden tests: they drive real taps, but need to know which
  /// star each offered choice sits on to aim at it.
  @visibleForTesting
  SessionState? get debugSession => _session;

  /// Jumps the completion animation to its end. Golden tests want the
  /// finished picture, and a ticking controller leaks across tests.
  @visibleForTesting
  void debugFinishAnimations() {
    _bloom
      ..stop()
      ..value = 1;
  }

  late final AnimationController _bloom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scene = await Scene.load(
        'assets/constellation/scenes/drift_v1.json',
      );
      if (!mounted) return;
      setState(() => _session = SessionState.start(scene));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _bloom.dispose();
    super.dispose();
  }

  void _take(SceneChoice choice) {
    final session = _session;
    if (session == null || session.isComplete) return;

    HapticFeedback.selectionClick();
    final next = session.take(choice);
    setState(() {
      _session = next;
      _pressing = null;
    });

    if (next.isComplete) {
      HapticFeedback.mediumImpact();
      if (!reduceMotionOf(context)) {
        _bloom.forward(from: 0);
      } else {
        _bloom.value = 1;
      }
    }
  }

  void _restart() {
    final scene = _session?.scene;
    if (scene == null) return;
    _bloom.reset();
    setState(() => _session = SessionState.start(scene));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return Scaffold(
      backgroundColor: _Palette.field,
      appBar: AppBar(
        backgroundColor: _Palette.field,
        foregroundColor: _Palette.ink,
        elevation: 0,
        title: const Text('Constellation'),
        actions: [
          if (session != null)
            TextButton(
              onPressed: _restart,
              child: const Text(
                'Restart',
                style: TextStyle(color: _Palette.dim, fontSize: 14),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child:
            _error != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _Palette.dim),
                    ),
                  ),
                )
                : session == null
                ? const Center(
                  child: CircularProgressIndicator(color: _Palette.a),
                )
                : _body(session),
      ),
    );
  }

  Widget _body(SessionState session) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child:
              session.isComplete
                  ? const Text(
                    'You made this together.',
                    style: TextStyle(
                      color: _Palette.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        session.turn == Slot.a ? "A's turn" : "B's turn",
                        style: TextStyle(
                          color:
                              session.turn == Slot.a ? _Palette.a : _Palette.b,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${session.movesPlayed} of ${session.scene.depth}',
                        style: const TextStyle(
                          color: _Palette.dim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide;
                    return SizedBox(
                      width: side,
                      height: side,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // §7.1: highlight on pointer-down, commit on
                        // pointer-up inside the target. A slip should not
                        // commit, but a decision with no wrong answer
                        // does not deserve a modal.
                        onTapDown:
                            (d) => setState(
                              () =>
                                  _pressing = _nearest(
                                    session,
                                    d.localPosition,
                                    side,
                                  ),
                            ),
                        onTapCancel: () => setState(() => _pressing = null),
                        onTapUp: (d) {
                          final hit = _nearest(session, d.localPosition, side);
                          final pressed = _pressing;
                          setState(() => _pressing = null);
                          if (hit != null && hit == pressed) {
                            _take(session.offered[hit]);
                          }
                        },
                        child: AnimatedBuilder(
                          animation: _bloom,
                          builder:
                              (context, _) => CustomPaint(
                                size: Size(side, side),
                                painter: _ConstellationPainter(
                                  session: session,
                                  pressing: _pressing,
                                  bloom: session.isComplete ? _bloom.value : 0,
                                ),
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: SizedBox(
            height: 52,
            child:
                session.isComplete
                    ? FilledButton(
                      onPressed: _restart,
                      style: FilledButton.styleFrom(
                        backgroundColor: _Palette.a,
                        foregroundColor: const Color(0xFF04201C),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Again'),
                    )
                    : const Center(
                      child: Text(
                        'Tap a glowing star.',
                        style: TextStyle(color: _Palette.dim, fontSize: 14),
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  /// Nearest offered choice by its destination star, within a threshold.
  /// The tap target is the region around the star, not the drawn dot.
  int? _nearest(SessionState session, Offset local, double side) {
    if (session.isComplete) return null;
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < session.offered.length; i++) {
      final star = session.scene.stars[session.offered[i].toStar]!;
      final p = Offset(star.x * side, star.y * side);
      final d = (local - p).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return bestDistance < side * 0.16 ? best : null;
  }
}

class _Palette {
  const _Palette._();
  static const field = Color(0xFF000000);
  static const ink = Color(0xFFE9E9E9);
  static const dim = Color(0xFF6E6E6E);
  static const star = Color(0xFF4A4A4A);
  static const a = Color(0xFF5EEAD4);
  static const b = Color(0xFFFF4D6A);
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter({
    required this.session,
    required this.pressing,
    required this.bloom,
  });

  final SessionState session;
  final int? pressing;
  final double bloom;

  Color _slotColour(Slot s) => s == Slot.a ? _Palette.a : _Palette.b;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    Offset at(Star s) => Offset(s.x * side, s.y * side);

    canvas.drawRect(Offset.zero & size, Paint()..color = _Palette.field);

    // Every star that could exist, faintly — so the field reads as a sky
    // rather than as a menu of two options.
    for (final star in session.scene.stars.values) {
      canvas.drawCircle(
        at(star),
        1.4,
        Paint()..color = _Palette.star.withValues(alpha: 0.5),
      );
    }

    // The completion bloom brightens in the order the pattern was
    // actually built (§7.3), so the animation is a record of taking
    // turns rather than a generic sweep.
    final total = session.moves.length;
    for (var i = 0; i < total; i++) {
      final move = session.moves[i];
      final from = session.scene.stars[move.choice.fromStar]!;
      final to = session.scene.stars[move.choice.toStar]!;
      final colour = _slotColour(move.slot);

      double reveal = 1;
      if (bloom > 0) {
        // A travelling window: each move lights in sequence.
        final start = i / total;
        reveal = ((bloom - start) * total * 1.8).clamp(0.0, 1.0);
      }
      if (reveal <= 0) continue;

      final glow = bloom > 0 ? 0.35 + 0.65 * reveal : 0.85;

      canvas.drawLine(
        at(from),
        at(to),
        Paint()
          ..color = colour.withValues(alpha: 0.85 * glow)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );

      // The layers this choice revealed — filaments belonging to the
      // line that made them.
      for (final layer in move.choice.variantLayers) {
        for (final s in LayerGeometry.strokes(layer, from, to)) {
          canvas.drawLine(
            Offset(s.x1 * side, s.y1 * side),
            Offset(s.x2 * side, s.y2 * side),
            Paint()
              ..color = colour.withValues(alpha: 0.42 * glow)
              ..strokeWidth = 1.0
              ..strokeCap = StrokeCap.round,
          );
        }
      }

      canvas.drawCircle(
        at(to),
        2.6,
        Paint()..color = colour.withValues(alpha: glow),
      );
    }

    if (session.isComplete) return;

    // The offered stars, pulsing.
    for (var i = 0; i < session.offered.length; i++) {
      final choice = session.offered[i];
      final from = session.scene.stars[choice.fromStar]!;
      final to = session.scene.stars[choice.toStar]!;
      final colour = _slotColour(session.turn);
      final isPressed = pressing == i;

      // A ghost of the line this choice would draw.
      canvas.drawLine(
        at(from),
        at(to),
        Paint()
          ..color = colour.withValues(alpha: isPressed ? 0.5 : 0.16)
          ..strokeWidth = isPressed ? 1.6 : 1.0,
      );

      canvas.drawCircle(
        at(to),
        isPressed ? 9 : 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colour.withValues(alpha: isPressed ? 0.95 : 0.55),
      );
      canvas.drawCircle(
        at(to),
        3,
        Paint()..color = colour.withValues(alpha: isPressed ? 1 : 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      old.session != session || old.pressing != pressing || old.bloom != bloom;
}
