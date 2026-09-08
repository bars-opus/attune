import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/models/word_hunt_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fixed colours, no theming.
///
/// The Arcade games are black-only by decision: a light mode would wash
/// out a grid whose whole legibility rests on white letters holding
/// against a black field, and these two games are the only screens in the
/// app that are asked to be a game rather than a document.
class WordHuntPalette {
  const WordHuntPalette._();

  static const field = Color(0xFF000000);
  static const grid = Color(0xFF2A2A2A);
  static const letter = Color(0xFFE9E9E9);

  /// The pill, and the letters under it. The reference is a white capsule
  /// with the letters knocked out.
  static const pill = Color(0xFFF4F4F4);
  static const pillLetter = Color(0xFF0A0A0A);

  /// A found word locks in the same teal the other Arcade games use for
  /// "this is yours".
  static const found = Color(0xFF5EEAD4);

  /// Where the word was, revealed at the end to whoever did not find it.
  static const reveal = Color(0xFFFFC94D);

  static const dim = Color(0xFF6E6E6E);
}

const int kWordHuntGridSize = 10;

/// How the screen tells the board a guess was wrong.
///
/// A GlobalKey plus a dynamic call would work and would also compile
/// after the method is renamed or deleted. This is the same handle with
/// the compiler still watching it.
class WordHuntBoardController extends ChangeNotifier {
  List<WordHuntCell>? _miss;
  int _nonce = 0;

  List<WordHuntCell>? get miss => _miss;
  int get nonce => _nonce;

  /// The same wrong guess made twice must animate twice, so the nonce
  /// changes even when the cells do not.
  void showMiss(List<WordHuntCell> cells) {
    _miss = cells;
    _nonce++;
    notifyListeners();
  }
}

/// The grid, the pill, and the drag.
///
/// TOUCH TARGETS. At about 340dp of usable width a cell is roughly 34px,
/// under the 44px guidance -- and this game asks for a precise PATH
/// across several of them rather than one tap. Three things make that
/// workable, and all three are here rather than left to discovery:
/// hit-testing that ignores the drawn cell bounds and simply asks which
/// cell the finger is nearest, snapping to the eight legal directions,
/// and a direction lock with hysteresis so a wobble holds its line.
class WordHuntBoard extends StatefulWidget {
  const WordHuntBoard({
    super.key,
    required this.grid,
    required this.wordLength,
    required this.enabled,
    required this.onSubmit,
    this.controller,
    this.lockedCells,
    this.revealedCells,
  });

  /// Ten strings of ten uppercase letters.
  final List<String> grid;

  final int wordLength;

  /// False while a submission is in flight, once the attempt is over, and
  /// on the reveal screen.
  final bool enabled;

  final ValueChanged<List<WordHuntCell>> onSubmit;

  /// Optional: the screen uses this to report a rejected guess.
  final WordHuntBoardController? controller;

  /// The found word, drawn permanently.
  final List<WordHuntCell>? lockedCells;

  /// Where the word was, shown at the end to whoever did not find it.
  final List<WordHuntCell>? revealedCells;

  @override
  State<WordHuntBoard> createState() => _WordHuntBoardState();
}

class _WordHuntBoardState extends State<WordHuntBoard>
    with SingleTickerProviderStateMixin {
  WordHuntSelection? _selection;
  (int, int)? _lockedDirection;
  int _lastHapticLength = 0;

  /// A wrong guess animates the pill off rather than saying anything.
  /// Being told "wrong" every few seconds while hunting is the kind of
  /// nagging that makes a small game feel like a test.
  late final AnimationController _dismiss = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  List<WordHuntCell>? _dismissing;

  /// Tap-first-letter then tap-last-letter, the complete alternative to
  /// dragging. This is also the only path that works with switch control,
  /// so it is not a convenience.
  WordHuntCell? _tapAnchor;

  int _seenMissNonce = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(WordHuntBoard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller == null) return;
    if (controller.nonce == _seenMissNonce) return;
    _seenMissNonce = controller.nonce;
    final cells = controller.miss;
    if (cells != null) _showMiss(cells);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _dismiss.dispose();
    super.dispose();
  }

  WordHuntCell? _cellAt(Offset local, Size size) {
    final cell = size.width / kWordHuntGridSize;
    if (cell <= 0) return null;
    // Deliberately not bounds-checked against the drawn cell: the finger
    // does not have to be centred, and a drag that strays a few pixels
    // past the last column should hold the last column rather than
    // dropping the selection.
    final col = (local.dx / cell).floor().clamp(0, kWordHuntGridSize - 1);
    final row = (local.dy / cell).floor().clamp(0, kWordHuntGridSize - 1);
    return WordHuntCell(row, col);
  }

  void _beginAt(WordHuntCell cell) {
    _dismiss.stop();
    setState(() {
      _dismissing = null;
      _tapAnchor = null;
      _selection = WordHuntSelection.at(cell);
      _lockedDirection = null;
      _lastHapticLength = 1;
    });
    HapticFeedback.selectionClick();
  }

  void _updateTo(WordHuntCell cell) {
    final selection = _selection;
    if (selection == null) return;

    final anchor = selection.anchor;
    final dRow = cell.row - anchor.row;
    final dCol = cell.col - anchor.col;

    // HYSTERESIS. The direction is locked as soon as the drag is two
    // cells long, and only released if the finger comes back to the
    // anchor. Without this a diagonal drag flickers between the diagonal
    // and its neighbouring axis on every frame near the boundary, and the
    // pill strobes.
    if (dRow == 0 && dCol == 0) {
      _lockedDirection = null;
    } else if (_lockedDirection == null &&
        (dRow.abs() >= 2 || dCol.abs() >= 2)) {
      _lockedDirection = WordHuntSelection.nearestDirection(
        dRow: dRow,
        dCol: dCol,
      );
    }

    final next = WordHuntSelection.extend(
      anchor: anchor,
      target: cell,
      maxLength: widget.wordLength,
      lockedDirection: _lockedDirection,
    );

    if (next == selection) return;
    setState(() => _selection = next);

    // One light tick per NEW letter entered, not per frame.
    if (next.length > _lastHapticLength) {
      HapticFeedback.selectionClick();
    }
    _lastHapticLength = next.length;
  }

  void _end() {
    final selection = _selection;
    if (selection == null) return;

    // A single cell is a stray tap, not a guess. Submitting it would burn
    // a rate-limit slot and flash a dismissal for nothing.
    if (selection.length < 2) {
      setState(() {
        _selection = null;
        _lockedDirection = null;
      });
      return;
    }

    final cells = List<WordHuntCell>.unmodifiable(selection.cells);
    setState(() {
      _selection = null;
      _lockedDirection = null;
    });
    widget.onSubmit(cells);
  }

  void _showMiss(List<WordHuntCell> cells) {
    if (!mounted) return;
    if (reduceMotionOf(context)) return;
    setState(() => _dismissing = cells);
    _dismiss.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _dismissing = null);
    });
  }

  void _handleTap(WordHuntCell cell) {
    if (!widget.enabled) return;
    final anchor = _tapAnchor;
    if (anchor == null) {
      setState(() {
        _tapAnchor = cell;
        _selection = WordHuntSelection.at(cell);
      });
      HapticFeedback.selectionClick();
      return;
    }
    if (anchor == cell) {
      setState(() {
        _tapAnchor = null;
        _selection = null;
      });
      return;
    }

    final selection = WordHuntSelection.extend(
      anchor: anchor,
      target: cell,
      maxLength: widget.wordLength,
    );
    setState(() {
      _tapAnchor = null;
      _selection = null;
    });
    if (selection.length >= 2) {
      widget.onSubmit(List<WordHuntCell>.unmodifiable(selection.cells));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final size = Size(side, side);

        return SizedBox(
          width: side,
          height: side,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart:
                widget.enabled
                    ? (d) {
                      final cell = _cellAt(d.localPosition, size);
                      if (cell != null) _beginAt(cell);
                    }
                    : null,
            onPanUpdate:
                widget.enabled
                    ? (d) {
                      final cell = _cellAt(d.localPosition, size);
                      if (cell != null) _updateTo(cell);
                    }
                    : null,
            onPanEnd: widget.enabled ? (_) => _end() : null,
            onPanCancel:
                widget.enabled
                    ? () => setState(() {
                      _selection = null;
                      _lockedDirection = null;
                    })
                    : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _dismiss,
                    builder:
                        (context, _) => CustomPaint(
                          painter: _WordHuntBoardPainter(
                            grid: widget.grid,
                            selection: _selection?.cells,
                            locked: widget.lockedCells,
                            revealed: widget.revealedCells,
                            dismissing: _dismissing,
                            dismissProgress: _dismiss.value,
                          ),
                        ),
                  ),
                ),
                // The accessible path. Semantics nodes sit over the cells
                // so a screen reader can read the grid and activate the
                // tap-first/tap-last selection, which is the only way to
                // play this game without a precise drag.
                Positioned.fill(
                  child: _SemanticGrid(
                    grid: widget.grid,
                    anchor: _tapAnchor,
                    enabled: widget.enabled,
                    onTap: _handleTap,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SemanticGrid extends StatelessWidget {
  const _SemanticGrid({
    required this.grid,
    required this.anchor,
    required this.enabled,
    required this.onTap,
  });

  final List<String> grid;
  final WordHuntCell? anchor;
  final bool enabled;
  final ValueChanged<WordHuntCell> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < kWordHuntGridSize; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < kWordHuntGridSize; col++)
                  Expanded(
                    child: Semantics(
                      button: enabled,
                      selected: anchor == WordHuntCell(row, col),
                      label:
                          '${grid[row][col]}, '
                          'row ${row + 1}, column ${col + 1}',
                      hint:
                          anchor == null
                              ? 'Double tap the first letter of the word'
                              : 'Double tap the last letter of the word',
                      // NO GestureDetector HERE, deliberately.
                      //
                      // Two attempts got this wrong in opposite
                      // directions, both caught by widget tests. A
                      // detector with deferToChild over a
                      // SizedBox.expand paints nothing, so taps never
                      // landed and the accessible path silently did not
                      // work. Making it translucent fixed the tap and
                      // broke every drag, because a tap recogniser in
                      // this layer beats a pan that has not yet crossed
                      // touch slop.
                      //
                      // So this layer contributes a SEMANTICS ACTION
                      // rather than a gesture. Assistive technology
                      // activates onTapHint through the semantics tree,
                      // which never enters the gesture arena at all, and
                      // the board's single pan detector keeps every
                      // pointer event.
                      onTap:
                          enabled ? () => onTap(WordHuntCell(row, col)) : null,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WordHuntBoardPainter extends CustomPainter {
  const _WordHuntBoardPainter({
    required this.grid,
    required this.selection,
    required this.locked,
    required this.revealed,
    required this.dismissing,
    required this.dismissProgress,
  });

  final List<String> grid;
  final List<WordHuntCell>? selection;
  final List<WordHuntCell>? locked;
  final List<WordHuntCell>? revealed;
  final List<WordHuntCell>? dismissing;
  final double dismissProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kWordHuntGridSize;
    if (cell <= 0) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = WordHuntPalette.field);

    // The pill first, so letters draw on top and can be knocked out.
    if (revealed != null) {
      // Opaque, deliberately. At 30% this amber composited against black
      // into a brown smear whose letters stayed light on top of it --
      // rendered and looked at before it was changed. This pill exists to
      // show a player who did NOT find the word exactly where it was, so
      // it has to be the most legible thing on the board.
      _pill(canvas, revealed!, cell, WordHuntPalette.reveal);
    }
    if (locked != null) {
      _pill(canvas, locked!, cell, WordHuntPalette.found);
    }
    if (dismissing != null && dismissProgress < 1) {
      _pill(
        canvas,
        dismissing!,
        cell,
        WordHuntPalette.pill.withValues(alpha: 0.55 * (1 - dismissProgress)),
      );
    }
    if (selection != null && selection!.length >= 2) {
      _pill(canvas, selection!, cell, WordHuntPalette.pill);
    } else if (selection != null && selection!.length == 1) {
      // A single anchor reads as a ring rather than a full pill: nothing
      // has been selected yet, and a filled cell would look like a guess.
      final c = selection!.first;
      canvas.drawCircle(
        Offset((c.col + 0.5) * cell, (c.row + 0.5) * cell),
        cell * 0.38,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = WordHuntPalette.pill.withValues(alpha: 0.7),
      );
    }

    // Every solid pill knocks its letters out. A light letter left on top
    // of the amber reveal pill was unreadable -- checked by rendering it.
    final inPill = <WordHuntCell>{
      if (selection != null && selection!.length >= 2) ...selection!,
      if (locked != null) ...locked!,
      if (revealed != null) ...revealed!,
    };

    for (var row = 0; row < kWordHuntGridSize; row++) {
      for (var col = 0; col < kWordHuntGridSize; col++) {
        final centre = Offset((col + 0.5) * cell, (row + 0.5) * cell);
        final isInPill = inPill.contains(WordHuntCell(row, col));

        final painter = TextPainter(
          text: TextSpan(
            text: grid[row][col],
            style: TextStyle(
              color:
                  isInPill
                      ? WordHuntPalette.pillLetter
                      : WordHuntPalette.letter,
              fontSize: cell * 0.46,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          centre - Offset(painter.width / 2, painter.height / 2),
        );
      }
    }

    // Grid lines last and faint: the letters are the content, and a
    // heavy lattice competes with them.
    final line =
        Paint()
          ..color = WordHuntPalette.grid
          ..strokeWidth = 1;
    for (var i = 1; i < kWordHuntGridSize; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), line);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), line);
    }
  }

  /// A capsule along the drag axis with a radius of half a cell, matching
  /// the reference.
  void _pill(
    Canvas canvas,
    List<WordHuntCell> cells,
    double cell,
    Color color,
  ) {
    if (cells.isEmpty) return;
    final first = cells.first;
    final last = cells.last;
    final a = Offset((first.col + 0.5) * cell, (first.row + 0.5) * cell);
    final b = Offset((last.col + 0.5) * cell, (last.row + 0.5) * cell);
    final radius = cell * 0.42;

    final paint = Paint()..color = color;
    if (a == b) {
      canvas.drawCircle(a, radius, paint);
      return;
    }

    canvas.save();
    canvas.translate(a.dx, a.dy);
    canvas.rotate(math.atan2(b.dy - a.dy, b.dx - a.dx));
    final length = (b - a).distance;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-radius, -radius, length + radius, radius),
        Radius.circular(radius),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordHuntBoardPainter old) =>
      old.grid != grid ||
      !_sameCells(old.selection, selection) ||
      !_sameCells(old.locked, locked) ||
      !_sameCells(old.revealed, revealed) ||
      !_sameCells(old.dismissing, dismissing) ||
      old.dismissProgress != dismissProgress;

  static bool _sameCells(List<WordHuntCell>? a, List<WordHuntCell>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
