import 'package:flutter/foundation.dart';

/// Dots and Boxes on a 3×3 grid of boxes.
///
/// PROTOTYPE. This file is the one piece of the prototype meant to
/// survive into the real implementation, because it is the game's actual
/// rules and the server will need the identical logic in SQL. Everything
/// else in this feature folder is throwaway (see DOTS_AND_BOXES_SPEC.md
/// §15 — this build exists to answer one question: does one partner win
/// every time?).
///
/// Geometry, from §3.1 and verified by enumeration in the tests:
///   - 3×3 boxes means a 4×4 grid of dots
///   - horizontal edges: 4 rows × 3 cols = 12
///   - vertical edges:   3 rows × 4 cols = 12
///   - 24 edges, 9 boxes
///   - 9 is odd, so a completed game cannot be drawn
///
/// Canonical index: horizontal edges first in row-major order (0–11),
/// then vertical (12–23). The server stores edges in this order, so the
/// mapping is part of the contract rather than a rendering detail.
const int kDotsBoxSize = 3;
const int kDotsEdgeCount = 24;
const int kDotsBoxCount = 9;

/// Which relationship member owns something.
///
/// Slots, not user ids — §8.1. The durable record of a finished game
/// should not carry an identity that can be deleted out from under it.
enum DotsSlot {
  a(1),
  b(2);

  const DotsSlot(this.wire);
  final int wire;

  DotsSlot get other => this == DotsSlot.a ? DotsSlot.b : DotsSlot.a;

  static DotsSlot? fromWire(Object? raw) => switch (raw) {
    1 => DotsSlot.a,
    2 => DotsSlot.b,
    _ => null,
  };
}

/// An edge, by orientation and position.
@immutable
class DotsEdge {
  const DotsEdge(this.horizontal, this.row, this.col);

  final bool horizontal;
  final int row;
  final int col;

  /// A horizontal edge spans dots (row, col)–(row, col+1), so it has
  /// 4 rows and 3 columns. A vertical edge spans (row, col)–(row+1, col),
  /// so 3 rows and 4 columns.
  bool get inBounds =>
      horizontal
          ? (row >= 0 && row <= kDotsBoxSize && col >= 0 && col < kDotsBoxSize)
          : (row >= 0 && row < kDotsBoxSize && col >= 0 && col <= kDotsBoxSize);

  int get index {
    if (horizontal) return row * kDotsBoxSize + col;
    return (kDotsBoxSize + 1) * kDotsBoxSize + row * (kDotsBoxSize + 1) + col;
  }

  static DotsEdge fromIndex(int index) {
    const horizontalCount = (kDotsBoxSize + 1) * kDotsBoxSize; // 12
    if (index < horizontalCount) {
      return DotsEdge(true, index ~/ kDotsBoxSize, index % kDotsBoxSize);
    }
    final v = index - horizontalCount;
    return DotsEdge(false, v ~/ (kDotsBoxSize + 1), v % (kDotsBoxSize + 1));
  }

  @override
  bool operator ==(Object other) =>
      other is DotsEdge &&
      other.horizontal == horizontal &&
      other.row == row &&
      other.col == col;

  @override
  int get hashCode => Object.hash(horizontal, row, col);

  @override
  String toString() => '${horizontal ? 'h' : 'v'}($row,$col)';
}

/// The four edges bounding box (row, col), by canonical index.
///
/// From §3.1: box (r,c) is bounded by (h,r,c), (h,r+1,c), (v,r,c) and
/// (v,r,c+1).
List<int> dotsBoxEdges(int boxIndex) {
  final r = boxIndex ~/ kDotsBoxSize;
  final c = boxIndex % kDotsBoxSize;
  return [
    DotsEdge(true, r, c).index,
    DotsEdge(true, r + 1, c).index,
    DotsEdge(false, r, c).index,
    DotsEdge(false, r, c + 1).index,
  ];
}

/// The boxes an edge borders — at most two, verified by enumeration.
List<int> dotsBoxesTouching(int edgeIndex) {
  final edge = DotsEdge.fromIndex(edgeIndex);
  final out = <int>[];
  if (edge.horizontal) {
    if (edge.row - 1 >= 0) out.add((edge.row - 1) * kDotsBoxSize + edge.col);
    if (edge.row < kDotsBoxSize) out.add(edge.row * kDotsBoxSize + edge.col);
  } else {
    if (edge.col - 1 >= 0) out.add(edge.row * kDotsBoxSize + edge.col - 1);
    if (edge.col < kDotsBoxSize) out.add(edge.row * kDotsBoxSize + edge.col);
  }
  return out;
}

/// What one move did.
@immutable
class DotsMoveResult {
  const DotsMoveResult({required this.boxesClosed, required this.board});

  /// 0, 1 or 2 box indices. Never more — one edge touches at most two.
  final List<int> boxesClosed;

  final DotsBoard board;

  /// THE RULE THE WHOLE GAME TURNS ON: close a box and you go again.
  bool get keepsTurn => boxesClosed.isNotEmpty;
}

/// The board, and the pure rule for advancing it.
///
/// Immutable: [draw] returns a new board rather than mutating, so a
/// caller can replay a move list from empty and compare — which is
/// exactly what the real implementation's deferred validator will do in
/// SQL (§8.2).
@immutable
class DotsBoard {
  const DotsBoard({required this.edgeOwners, required this.boxOwners});

  /// 24 entries, null where undrawn.
  final List<DotsSlot?> edgeOwners;

  /// 9 entries, null where unclosed.
  final List<DotsSlot?> boxOwners;

  factory DotsBoard.empty() => DotsBoard(
    edgeOwners: List<DotsSlot?>.filled(kDotsEdgeCount, null),
    boxOwners: List<DotsSlot?>.filled(kDotsBoxCount, null),
  );

  bool isDrawn(int edgeIndex) => edgeOwners[edgeIndex] != null;

  int scoreOf(DotsSlot slot) =>
      boxOwners.where((owner) => owner == slot).length;

  int get movesPlayed => edgeOwners.where((owner) => owner != null).length;

  bool get isComplete => movesPlayed == kDotsEdgeCount;

  /// Boxes nobody has closed yet.
  int get boxesRemaining => boxOwners.where((owner) => owner == null).length;

  /// The winner of a finished board. Never null once complete, because 9
  /// is odd — §3.2.
  DotsSlot? get winner {
    if (!isComplete) return null;
    final a = scoreOf(DotsSlot.a);
    final b = scoreOf(DotsSlot.b);
    return a > b ? DotsSlot.a : DotsSlot.b;
  }

  /// Whether [slot] can still catch up. Drives whether the button reads
  /// "resign" or "concede" — §5.4.
  bool isDecidedAgainst(DotsSlot slot) {
    final mine = scoreOf(slot);
    final theirs = scoreOf(slot.other);
    return theirs > mine + boxesRemaining;
  }

  /// Draw [edgeIndex] for [slot].
  ///
  /// Pure: no clock, no session, no player identity beyond the slot. The
  /// caller checks turn order; this checks only that the move is legal on
  /// this board.
  DotsMoveResult draw(int edgeIndex, DotsSlot slot) {
    if (edgeIndex < 0 || edgeIndex >= kDotsEdgeCount) {
      throw ArgumentError.value(edgeIndex, 'edgeIndex', 'outside 0..23');
    }
    if (edgeOwners[edgeIndex] != null) {
      throw StateError('edge $edgeIndex is already drawn');
    }

    final nextEdges = List<DotsSlot?>.from(edgeOwners);
    nextEdges[edgeIndex] = slot;

    final nextBoxes = List<DotsSlot?>.from(boxOwners);
    final closed = <int>[];
    for (final box in dotsBoxesTouching(edgeIndex)) {
      if (nextBoxes[box] != null) continue;
      final complete = dotsBoxEdges(box).every((e) => nextEdges[e] != null);
      if (complete) {
        nextBoxes[box] = slot;
        closed.add(box);
      }
    }

    return DotsMoveResult(
      boxesClosed: List.unmodifiable(closed),
      board: DotsBoard(
        edgeOwners: List.unmodifiable(nextEdges),
        boxOwners: List.unmodifiable(nextBoxes),
      ),
    );
  }
}
