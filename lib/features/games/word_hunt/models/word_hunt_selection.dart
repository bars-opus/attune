import 'dart:math' as math;

import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:flutter/foundation.dart';

/// The eight legal directions, in the server's order.
const kWordHuntDirections = <(int, int)>[
  (0, 1), // east
  (0, -1), // west
  (1, 0), // south
  (-1, 0), // north
  (1, 1), // south-east
  (-1, -1), // north-west
  (1, -1), // south-west
  (-1, 1), // north-east
];

/// A selection in progress: an anchor, and wherever the finger is now.
///
/// SNAPPED TO THE EIGHT LEGAL DIRECTIONS, always. A finger on glass is
/// not precise, and a game that only accepts a perfectly straight drag
/// across 34px cells is a game about dexterity. So the anchor plus the
/// current cell resolve to the nearest legal line, and the pill is drawn
/// along that line rather than under the finger.
@immutable
class WordHuntSelection {
  const WordHuntSelection({required this.anchor, required this.cells});

  /// Where the drag began. Kept separately because the cells list is
  /// derived and the anchor is not.
  final WordHuntCell anchor;

  /// The snapped path, anchor first. Never empty.
  final List<WordHuntCell> cells;

  WordHuntCell get head => cells.last;
  int get length => cells.length;

  bool contains(WordHuntCell cell) => cells.contains(cell);

  /// A selection of just the anchor, before the finger has moved.
  factory WordHuntSelection.at(WordHuntCell anchor) =>
      WordHuntSelection(anchor: anchor, cells: [anchor]);

  /// Extends from [anchor] towards [target], snapping to a legal line and
  /// stopping at [maxLength] cells.
  ///
  /// [maxLength] is the word's length: dragging past it cannot make a
  /// longer word, and letting the pill run on would suggest it could.
  static WordHuntSelection extend({
    required WordHuntCell anchor,
    required WordHuntCell target,
    required int maxLength,
    (int, int)? lockedDirection,
  }) {
    final dRow = target.row - anchor.row;
    final dCol = target.col - anchor.col;

    if (dRow == 0 && dCol == 0) return WordHuntSelection.at(anchor);

    final direction =
        lockedDirection ?? nearestDirection(dRow: dRow, dCol: dCol);
    final (stepRow, stepCol) = direction;

    // How far along that axis the finger has travelled. Projecting onto
    // the direction rather than taking the larger delta means a finger
    // drifting sideways does not also drift backwards along the line.
    final projected = dRow * stepRow + dCol * stepCol;
    final axisLength = (stepRow != 0 && stepCol != 0) ? 2 : 1;
    var steps = (projected / axisLength).round();

    if (steps < 0) steps = 0;
    if (steps > maxLength - 1) steps = maxLength - 1;

    final cells = <WordHuntCell>[];
    for (var i = 0; i <= steps; i++) {
      final cell = WordHuntCell(
        anchor.row + stepRow * i,
        anchor.col + stepCol * i,
      );
      // Running off the board truncates rather than wraps or clamps: a
      // clamped cell would be selected twice and a wrapped one would be
      // somewhere the player never dragged.
      if (!cell.inBounds) break;
      cells.add(cell);
    }

    if (cells.isEmpty) return WordHuntSelection.at(anchor);
    return WordHuntSelection(anchor: anchor, cells: cells);
  }

  /// The legal direction closest to the raw drag vector.
  ///
  /// Compared by angle rather than by rounding each component, because
  /// rounding sends a drag of (1, 3) -- clearly eastward -- to the
  /// diagonal, and the diagonals would swallow most of the plane.
  static (int, int) nearestDirection({required int dRow, required int dCol}) {
    final angle = math.atan2(dRow.toDouble(), dCol.toDouble());
    var best = kWordHuntDirections.first;
    var bestDelta = double.infinity;

    for (final direction in kWordHuntDirections) {
      final (r, c) = direction;
      final candidate = math.atan2(r.toDouble(), c.toDouble());
      var delta = (angle - candidate).abs();
      if (delta > math.pi) delta = 2 * math.pi - delta;
      if (delta < bestDelta) {
        bestDelta = delta;
        best = direction;
      }
    }
    return best;
  }

  /// The direction this selection runs in, once it has more than a cell.
  (int, int)? get direction {
    if (cells.length < 2) return null;
    return (cells[1].row - cells[0].row, cells[1].col - cells[0].col);
  }

  @override
  bool operator ==(Object other) =>
      other is WordHuntSelection &&
      other.anchor == anchor &&
      listEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(anchor, Object.hashAll(cells));
}
