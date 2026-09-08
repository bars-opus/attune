import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/dots_and_boxes/models/dots_boxes_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// THROWAWAY PROTOTYPE — pass-and-play on one device.
///
/// DOTS_AND_BOXES_SPEC.md §15 recommends not building the real thing
/// next, and this exists to answer the one question a spec cannot: after
/// a mild argument, does one partner win every single time? If they do,
/// the game does not belong in a cooldown slot whatever its other merits.
///
/// So there is deliberately no server, no session, no realtime, no
/// replay cursor and no accessibility work beyond the basics. None of
/// that changes the answer, and all of it is ten to fourteen days.
/// The only piece meant to survive is `dots_boxes_rules.dart`.
class DotsBoxesPrototypeScreen extends StatefulWidget {
  const DotsBoxesPrototypeScreen({super.key});

  @override
  State<DotsBoxesPrototypeScreen> createState() =>
      _DotsBoxesPrototypeScreenState();
}

class _DotsBoxesPrototypeScreenState extends State<DotsBoxesPrototypeScreen> {
  DotsBoard _board = DotsBoard.empty();
  DotsSlot _turn = DotsSlot.a;
  int? _preview;

  /// Kept only so the prototype can report the thing it exists to
  /// measure. Nothing is persisted — the spec's no-record rule stands.
  int _gamesA = 0;
  int _gamesB = 0;

  void _reset() {
    setState(() {
      _board = DotsBoard.empty();
      _turn = DotsSlot.a;
      _preview = null;
    });
  }

  void _tapEdge(int index) {
    if (_board.isComplete) return;

    // Already drawn: consume the tap and do nothing, rather than
    // selecting a nearby undrawn edge the finger did not mean (§7.1).
    if (_board.isDrawn(index)) return;

    // Two-step commit: an edge is the whole move and cannot be undone,
    // so the first tap only previews (§7.1).
    if (_preview != index) {
      setState(() => _preview = index);
      HapticFeedback.selectionClick();
      return;
    }

    final result = _board.draw(index, _turn);
    HapticFeedback.mediumImpact();
    setState(() {
      _board = result.board;
      _preview = null;
      if (!result.keepsTurn) _turn = _turn.other;
    });

    if (result.board.isComplete) {
      final winner = result.board.winner;
      setState(() {
        if (winner == DotsSlot.a) {
          _gamesA++;
        } else {
          _gamesB++;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = _board.isComplete;
    final winner = _board.winner;

    return Scaffold(
      backgroundColor: _DotsPalette.field,
      appBar: AppBar(
        backgroundColor: _DotsPalette.field,
        foregroundColor: _DotsPalette.line,
        elevation: 0,
        title: const Text('Dots and Boxes'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text(
              'New game',
              style: TextStyle(color: _DotsPalette.dim, fontSize: 14),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ScorePill(
                    label: 'A',
                    score: _board.scoreOf(DotsSlot.a),
                    colour: _DotsPalette.a,
                    active: !complete && _turn == DotsSlot.a,
                    games: _gamesA,
                  ),
                  _ScorePill(
                    label: 'B',
                    score: _board.scoreOf(DotsSlot.b),
                    colour: _DotsPalette.b,
                    active: !complete && _turn == DotsSlot.b,
                    games: _gamesB,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _DotsBoardView(
                      board: _board,
                      preview: _preview,
                      previewSlot: _turn,
                      onTapEdge: _tapEdge,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child:
                  complete
                      ? Column(
                        children: [
                          Text(
                            winner == DotsSlot.a
                                ? 'A took ${_board.scoreOf(DotsSlot.a)}, '
                                    'B took ${_board.scoreOf(DotsSlot.b)}.'
                                : 'B took ${_board.scoreOf(DotsSlot.b)}, '
                                    'A took ${_board.scoreOf(DotsSlot.a)}.',
                            style: const TextStyle(
                              color: _DotsPalette.line,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _reset,
                            style: FilledButton.styleFrom(
                              backgroundColor: _DotsPalette.a,
                              foregroundColor: const Color(0xFF04201C),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Play again'),
                          ),
                        ],
                      )
                      : SizedBox(
                        // FIXED HEIGHT, deliberately. The two hint
                        // strings wrap to different line counts at some
                        // widths, and the board above is sized by what
                        // is left over -- so the whole grid jumped ten
                        // pixels the moment a preview began, moving the
                        // target out from under the finger mid-move.
                        // Found because taps in a widget test started
                        // missing after the first one.
                        height: 48,
                        child: Center(
                          child: Text(
                            _preview == null
                                ? 'Tap a gap to choose a line.'
                                : 'Tap it again to draw it.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _DotsPalette.dim,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsPalette {
  const _DotsPalette._();
  static const field = Color(0xFF000000);
  static const line = Color(0xFFE9E9E9);
  static const dot = Color(0xFF6E6E6E);
  static const dim = Color(0xFF6E6E6E);
  static const a = Color(0xFF5EEAD4);
  static const b = Color(0xFFFF4D6A);
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.label,
    required this.score,
    required this.colour,
    required this.active,
    required this.games,
  });

  final String label;
  final int score;
  final Color colour;
  final bool active;
  final int games;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: active ? colour : const Color(0xFF2A2A2A),
        width: active ? 2 : 1,
      ),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colour,
            fontSize: 12,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$score',
          style: TextStyle(
            color: active ? colour : _DotsPalette.line,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (games > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$games won',
            style: const TextStyle(color: _DotsPalette.dim, fontSize: 11),
          ),
        ],
      ],
    ),
  );
}

class _DotsBoardView extends StatelessWidget {
  const _DotsBoardView({
    required this.board,
    required this.preview,
    required this.previewSlot,
    required this.onTapEdge,
  });

  final DotsBoard board;
  final int? preview;
  final DotsSlot previewSlot;
  final ValueChanged<int> onTapEdge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        // Inset so the dots on the boundary are not half-clipped.
        const inset = 8.0;
        final gap = (side - inset * 2) / kDotsBoxSize;

        Offset dotAt(int r, int c) => Offset(inset + c * gap, inset + r * gap);

        // Nearest-edge hit-testing (§7.1): the tap target is the gap, not
        // the 2px stroke. Every edge's midpoint competes for the tap and
        // the closest wins, so a finger never has to land on the line.
        void handleTap(Offset local) {
          var best = -1;
          var bestDistance = double.infinity;
          for (var i = 0; i < kDotsEdgeCount; i++) {
            final e = DotsEdge.fromIndex(i);
            final from = dotAt(e.row, e.col);
            final to =
                e.horizontal
                    ? dotAt(e.row, e.col + 1)
                    : dotAt(e.row + 1, e.col);
            final mid = (from + to) / 2;
            final d = (local - mid).distance;
            if (d < bestDistance) {
              bestDistance = d;
              best = i;
            }
          }
          if (best >= 0 && bestDistance < gap * 0.5) onTapEdge(best);
        }

        // SizedBox around BOTH the gesture layer and the painter, so
        // the tap coordinates and the drawing share one origin. Passing
        // size: Size(side, side) to a CustomPaint whose parent fills the
        // width does not shrink the canvas -- the first render came out
        // stretched and left-hugging, which the golden showed and the
        // code did not.
        //
        // The board also has to be inset by the dot radius: dots sit ON
        // the boundary at columns 0 and 3, so half of each edge dot fell
        // outside the paint area.
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => handleTap(d.localPosition),
              child: CustomPaint(
                size: Size(side, side),
                painter: _DotsPainter(
                  board: board,
                  preview: preview,
                  previewSlot: previewSlot,
                  reduceMotion: reduceMotionOf(context),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter({
    required this.board,
    required this.preview,
    required this.previewSlot,
    required this.reduceMotion,
  });

  final DotsBoard board;
  final int? preview;
  final DotsSlot previewSlot;
  final bool reduceMotion;

  Color _colour(DotsSlot slot) =>
      slot == DotsSlot.a ? _DotsPalette.a : _DotsPalette.b;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final gap = (size.shortestSide - inset * 2) / kDotsBoxSize;
    Offset dotAt(int r, int c) => Offset(inset + c * gap, inset + r * gap);

    canvas.drawRect(Offset.zero & size, Paint()..color = _DotsPalette.field);

    // Owned boxes first, so lines and dots draw over them.
    for (var box = 0; box < kDotsBoxCount; box++) {
      final owner = board.boxOwners[box];
      if (owner == null) continue;
      final r = box ~/ kDotsBoxSize;
      final c = box % kDotsBoxSize;
      canvas.drawRect(
        Rect.fromLTWH(inset + c * gap, inset + r * gap, gap, gap),
        Paint()..color = _colour(owner).withValues(alpha: 0.16),
      );
      // The initial, so the board never depends on colour alone (§3.3).
      final label = TextPainter(
        text: TextSpan(
          text: owner == DotsSlot.a ? 'A' : 'B',
          style: TextStyle(
            color: _colour(owner),
            fontSize: gap * 0.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        dotAt(r, c) +
            Offset(gap / 2, gap / 2) -
            Offset(label.width / 2, label.height / 2),
      );
    }

    for (var i = 0; i < kDotsEdgeCount; i++) {
      final e = DotsEdge.fromIndex(i);
      final from = dotAt(e.row, e.col);
      final to =
          e.horizontal ? dotAt(e.row, e.col + 1) : dotAt(e.row + 1, e.col);
      final owner = board.edgeOwners[i];

      if (owner != null) {
        canvas.drawLine(
          from,
          to,
          Paint()
            ..color = _colour(owner)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
      } else if (preview == i) {
        // Dashed ghost: chosen, not yet drawn.
        _dashed(canvas, from, to, _colour(previewSlot).withValues(alpha: 0.8));
      }
    }

    for (var r = 0; r <= kDotsBoxSize; r++) {
      for (var c = 0; c <= kDotsBoxSize; c++) {
        canvas.drawCircle(dotAt(r, c), 3.5, Paint()..color = _DotsPalette.dot);
      }
    }
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Color colour) {
    const dash = 6.0;
    const space = 4.0;
    final total = (to - from).distance;
    final direction = (to - from) / total;
    final paint =
        Paint()
          ..color = colour
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;

    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + space;
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.board != board ||
      old.preview != preview ||
      old.previewSlot != previewSlot;
}
