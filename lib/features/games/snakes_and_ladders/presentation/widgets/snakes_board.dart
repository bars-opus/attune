import 'dart:math' as math;

import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:flutter/material.dart';

/// The board's palette. Fixed, like Paint Ball's, and for the same
/// reason: this is a schematic on a dark ground, and a light theme would
/// leave the thin strokes invisible.
class SnakesPalette {
  const SnakesPalette._();

  static const field = Color(0xFF000000);
  static const grid = Color(0xFF2A2A2A);
  static const numeral = Color(0xFF6E6E6E);

  /// Yours is the mint Paint Ball uses; theirs the same red. A player who
  /// knows one game already knows which token is theirs.
  static const you = Color(0xFF5EEAD4);
  static const them = Color(0xFFFF4D6A);

  static const ladder = Color(0xFF7BD88F);
  static const snake = Color(0xFFFF9E6B);
}

const int kSnakesCells = 100;
const int kSnakesPerRow = 10;

/// Where a cell sits, in board coordinates (0,0 top-left).
///
/// Boustrophedon: row 1 runs left to right, row 2 right to left, so the
/// path from 1 to 100 is continuous and a token's walk never teleports
/// across the board at a row end.
Offset snakesCellCentre(int cell, Size size) {
  if (cell < 1) {
    // Off-board tokens sit below the first cell, so starting a game
    // reads as stepping onto the board rather than appearing on it.
    final cw = size.width / kSnakesPerRow;
    final ch = size.height / kSnakesPerRow;
    return Offset(cw / 2, size.height + ch * 0.42);
  }

  final index = cell - 1;
  final rowFromBottom = index ~/ kSnakesPerRow;
  final withinRow = index % kSnakesPerRow;
  final leftToRight = rowFromBottom.isEven;
  final column = leftToRight ? withinRow : kSnakesPerRow - 1 - withinRow;

  final cw = size.width / kSnakesPerRow;
  final ch = size.height / kSnakesPerRow;
  return Offset(
    cw * column + cw / 2,
    size.height - (ch * rowFromBottom + ch / 2),
  );
}

/// The board: grid, features, tokens.
class SnakesBoardView extends StatelessWidget {
  const SnakesBoardView({
    super.key,
    required this.board,
    required this.yourCell,
    required this.theirCell,
    this.highlightCell,
    this.partnerName,
  });

  final SnakesBoard board;
  final int yourCell;
  final int theirCell;

  /// A cell to lift while a move animates through it.
  final int? highlightCell;

  final String? partnerName;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below this width a full set of numerals is noise rather than
          // information: the player reads the SHAPE of the board and
          // looks up their own cell in the readout underneath.
          final sparseNumerals = constraints.maxWidth < 340;

          return Container(
            decoration: BoxDecoration(
              color: SnakesPalette.field,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: _BoardPainter(
                board: board,
                yourCell: yourCell,
                theirCell: theirCell,
                highlightCell: highlightCell,
                sparseNumerals: sparseNumerals,
                textDirection: Directionality.of(context),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.yourCell,
    required this.theirCell,
    required this.highlightCell,
    required this.sparseNumerals,
    required this.textDirection,
  });

  final SnakesBoard board;
  final int yourCell;
  final int theirCell;
  final int? highlightCell;
  final bool sparseNumerals;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintFeatures(canvas, size);
    _paintTokens(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final cw = size.width / kSnakesPerRow;
    final ch = size.height / kSnakesPerRow;

    // A hairline: the grid orients, the snakes and ladders are what a
    // player actually reads.
    final line =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = SnakesPalette.grid;

    for (var i = 0; i <= kSnakesPerRow; i++) {
      canvas.drawLine(Offset(cw * i, 0), Offset(cw * i, size.height), line);
      canvas.drawLine(Offset(0, ch * i), Offset(size.width, ch * i), line);
    }

    for (var cell = 1; cell <= kSnakesCells; cell++) {
      final show =
          !sparseNumerals ||
          cell == 1 ||
          cell % 10 == 0 ||
          cell == yourCell ||
          cell == theirCell ||
          board.ladders.containsKey(cell) ||
          board.snakes.containsKey(cell);
      if (!show) continue;

      final centre = snakesCellCentre(cell, size);
      final painter = TextPainter(
        text: TextSpan(
          text: '$cell',
          style: TextStyle(
            color: SnakesPalette.numeral,
            fontSize: math.min(cw, ch) * 0.30,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: textDirection,
      )..layout();

      painter.paint(
        canvas,
        Offset(centre.dx - cw / 2 + 3, centre.dy - ch / 2 + 2),
      );
    }
  }

  void _paintFeatures(Canvas canvas, Size size) {
    board.ladders.forEach((from, to) => _paintLadder(canvas, size, from, to));
    board.snakes.forEach((from, to) => _paintSnake(canvas, size, from, to));
  }

  /// Two rails and rungs, so a ladder reads as a ladder rather than a
  /// green line.
  void _paintLadder(Canvas canvas, Size size, int from, int to) {
    final a = snakesCellCentre(from, size);
    final b = snakesCellCentre(to, size);
    final along = b - a;
    final length = along.distance;
    if (length == 0) return;

    final normal = Offset(-along.dy, along.dx) / length;
    final halfWidth = math.min(size.width / kSnakesPerRow, 40) * 0.16;

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = SnakesPalette.ladder.withValues(alpha: 0.75);

    canvas.drawLine(a + normal * halfWidth, b + normal * halfWidth, paint);
    canvas.drawLine(a - normal * halfWidth, b - normal * halfWidth, paint);

    final rungs = math.max(2, (length / 26).round());
    for (var i = 1; i < rungs; i++) {
      final t = i / rungs;
      final point = Offset.lerp(a, b, t)!;
      canvas.drawLine(
        point + normal * halfWidth,
        point - normal * halfWidth,
        paint,
      );
    }
  }

  /// A tapering curve with a head, so which end bites is unmistakable.
  void _paintSnake(Canvas canvas, Size size, int from, int to) {
    final a = snakesCellCentre(from, size);
    final b = snakesCellCentre(to, size);
    final along = b - a;
    final length = along.distance;
    if (length == 0) return;

    final normal = Offset(-along.dy, along.dx) / length;
    final wave = math.min(length * 0.16, 26.0);

    final path =
        Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(
            (a + along * 0.33 + normal * wave).dx,
            (a + along * 0.33 + normal * wave).dy,
            (a + along * 0.66 - normal * wave).dx,
            (a + along * 0.66 - normal * wave).dy,
            b.dx,
            b.dy,
          );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = SnakesPalette.snake.withValues(alpha: 0.8),
    );

    // The head sits at the cell that bites.
    canvas.drawCircle(a, 4.2, Paint()..color = SnakesPalette.snake);
  }

  void _paintTokens(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / kSnakesPerRow * 0.26;

    if (highlightCell != null) {
      canvas.drawCircle(
        snakesCellCentre(highlightCell!, size),
        radius * 1.9,
        Paint()..color = Colors.white.withValues(alpha: 0.07),
      );
    }

    // Drawn with a small offset each so two tokens on one cell are both
    // visible -- they share cells freely, since there is no capture.
    _paintToken(
      canvas,
      snakesCellCentre(theirCell, size) + Offset(radius * 0.5, 0),
      radius,
      SnakesPalette.them,
    );
    _paintToken(
      canvas,
      snakesCellCentre(yourCell, size) - Offset(radius * 0.5, 0),
      radius,
      SnakesPalette.you,
    );
  }

  void _paintToken(Canvas canvas, Offset centre, double radius, Color color) {
    canvas.drawCircle(
      centre,
      radius * 1.5,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(centre, radius, Paint()..color = color);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = SnakesPalette.field,
    );
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.yourCell != yourCell ||
      old.theirCell != theirCell ||
      old.highlightCell != highlightCell ||
      old.sparseNumerals != sparseNumerals ||
      old.board != board;
}
