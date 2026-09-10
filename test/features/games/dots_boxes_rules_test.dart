import 'dart:math' as math;

import 'package:attune/features/games/dots_and_boxes/models/dots_boxes_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometry, enumerated rather than assumed', () {
    test('24 edges: 12 horizontal, 12 vertical', () {
      final horizontal = <DotsEdge>[];
      final vertical = <DotsEdge>[];
      for (var i = 0; i < kDotsEdgeCount; i++) {
        final e = DotsEdge.fromIndex(i);
        (e.horizontal ? horizontal : vertical).add(e);
      }
      expect(horizontal, hasLength(12));
      expect(vertical, hasLength(12));
    });

    test('index and fromIndex round-trip for every edge', () {
      for (var i = 0; i < kDotsEdgeCount; i++) {
        expect(DotsEdge.fromIndex(i).index, i);
      }
    });

    test('every generated edge is in bounds', () {
      for (var i = 0; i < kDotsEdgeCount; i++) {
        expect(DotsEdge.fromIndex(i).inBounds, isTrue, reason: 'index $i');
      }
    });

    test('horizontal spans 4 rows x 3 cols, vertical 3 x 4', () {
      final h = [
        for (var i = 0; i < kDotsEdgeCount; i++) DotsEdge.fromIndex(i),
      ].where((e) => e.horizontal);
      final v = [
        for (var i = 0; i < kDotsEdgeCount; i++) DotsEdge.fromIndex(i),
      ].where((e) => !e.horizontal);
      expect(h.map((e) => e.row).toSet(), {0, 1, 2, 3});
      expect(h.map((e) => e.col).toSet(), {0, 1, 2});
      expect(v.map((e) => e.row).toSet(), {0, 1, 2});
      expect(v.map((e) => e.col).toSet(), {0, 1, 2, 3});
    });

    test('an edge touches at most two boxes, and the relation is mutual', () {
      // §3.1 states this bound and the scoring loop depends on it.
      for (var i = 0; i < kDotsEdgeCount; i++) {
        final touching = dotsBoxesTouching(i);
        expect(touching.length, lessThanOrEqualTo(2), reason: 'edge $i');
        expect(touching.toSet().length, touching.length);
        // If an edge names a box, that box must name the edge back.
        for (final box in touching) {
          expect(
            dotsBoxEdges(box),
            contains(i),
            reason: 'edge $i claims box $box but the box disagrees',
          );
        }
      }
    });

    test('every box has exactly four distinct in-range edges', () {
      for (var box = 0; box < kDotsBoxCount; box++) {
        final edges = dotsBoxEdges(box);
        expect(edges, hasLength(4));
        expect(edges.toSet().length, 4);
        for (final e in edges) {
          expect(e, inInclusiveRange(0, kDotsEdgeCount - 1));
          expect(dotsBoxesTouching(e), contains(box));
        }
      }
    });

    test('exactly four edges border two boxes each on a 3x3 board', () {
      // The interior edges. These are the only ones a single move can
      // use to close two boxes at once, so the count is worth pinning.
      final interior = [
        for (var i = 0; i < kDotsEdgeCount; i++)
          if (dotsBoxesTouching(i).length == 2) i,
      ];
      expect(interior, hasLength(12));
    });
  });

  group('drawing', () {
    test('an empty board closes nothing, whichever edge is drawn', () {
      for (var i = 0; i < kDotsEdgeCount; i++) {
        final result = DotsBoard.empty().draw(i, DotsSlot.a);
        expect(result.boxesClosed, isEmpty, reason: 'edge $i');
        expect(result.keepsTurn, isFalse);
      }
    });

    test('the fourth edge of a box closes exactly that box', () {
      for (var box = 0; box < kDotsBoxCount; box++) {
        var board = DotsBoard.empty();
        final edges = dotsBoxEdges(box);
        for (final e in edges.take(3)) {
          board = board.draw(e, DotsSlot.a).board;
        }
        final result = board.draw(edges.last, DotsSlot.b);
        expect(result.boxesClosed, [box]);
        expect(result.keepsTurn, isTrue);
        // Closed by whoever drew the LAST edge, not the first three.
        expect(result.board.boxOwners[box], DotsSlot.b);
        expect(result.board.scoreOf(DotsSlot.b), 1);
        expect(result.board.scoreOf(DotsSlot.a), 0);
      }
    });

    test('one edge can close two boxes and scores both', () {
      // Take an interior edge, complete both its boxes except for it.
      final shared =
          [
            for (var i = 0; i < kDotsEdgeCount; i++)
              if (dotsBoxesTouching(i).length == 2) i,
          ].first;
      final both = dotsBoxesTouching(shared);

      var board = DotsBoard.empty();
      for (final box in both) {
        for (final e in dotsBoxEdges(box)) {
          if (e == shared || board.isDrawn(e)) continue;
          board = board.draw(e, DotsSlot.a).board;
        }
      }
      final result = board.draw(shared, DotsSlot.b);
      expect(result.boxesClosed.toSet(), both.toSet());
      expect(result.board.scoreOf(DotsSlot.b), 2);
      expect(result.keepsTurn, isTrue);
    });

    test('drawing a drawn edge throws rather than silently passing', () {
      final board = DotsBoard.empty().draw(0, DotsSlot.a).board;
      expect(() => board.draw(0, DotsSlot.b), throwsStateError);
    });

    test('an out-of-range index throws', () {
      expect(() => DotsBoard.empty().draw(-1, DotsSlot.a), throwsArgumentError);
      expect(() => DotsBoard.empty().draw(24, DotsSlot.a), throwsArgumentError);
    });

    test('draw does not mutate the board it was called on', () {
      final board = DotsBoard.empty();
      board.draw(5, DotsSlot.a);
      expect(board.isDrawn(5), isFalse);
      expect(board.movesPlayed, 0);
    });
  });

  group('the whole game', () {
    test('9 boxes is odd, so a completed board always has one winner', () {
      // The property §3.2 rests on. Played out, not argued.
      final random = math.Random(20260908);
      for (var game = 0; game < 300; game++) {
        var board = DotsBoard.empty();
        var turn = DotsSlot.a;
        while (!board.isComplete) {
          final legal = [
            for (var i = 0; i < kDotsEdgeCount; i++)
              if (!board.isDrawn(i)) i,
          ];
          final pick = legal[random.nextInt(legal.length)];
          final result = board.draw(pick, turn);
          board = result.board;
          if (!result.keepsTurn) turn = turn.other;
        }
        expect(
          board.scoreOf(DotsSlot.a) + board.scoreOf(DotsSlot.b),
          kDotsBoxCount,
        );
        expect(
          board.scoreOf(DotsSlot.a),
          isNot(board.scoreOf(DotsSlot.b)),
          reason: 'a draw occurred, which 9 boxes should make impossible',
        );
        expect(board.winner, isNotNull);
      }
    });

    test('invariants hold after every move of every random game', () {
      // The property test the real implementation's deferred validator
      // will do in SQL: replay from empty and assert the board is
      // internally consistent at every step.
      final random = math.Random(7);
      for (var game = 0; game < 200; game++) {
        var board = DotsBoard.empty();
        var turn = DotsSlot.a;
        var moves = 0;

        while (!board.isComplete) {
          final legal = [
            for (var i = 0; i < kDotsEdgeCount; i++)
              if (!board.isDrawn(i)) i,
          ];
          final result = board.draw(legal[random.nextInt(legal.length)], turn);
          board = result.board;
          moves++;

          // movesPlayed tracks drawn edges exactly.
          expect(board.movesPlayed, moves);

          // A box is owned IFF all four of its edges are drawn.
          for (var box = 0; box < kDotsBoxCount; box++) {
            final surrounded = dotsBoxEdges(box).every((e) => board.isDrawn(e));
            expect(
              board.boxOwners[box] != null,
              surrounded,
              reason: 'box $box ownership disagrees with its edges',
            );
          }

          // Scores are derivable from the board, never drifting.
          expect(
            board.scoreOf(DotsSlot.a) + board.scoreOf(DotsSlot.b),
            board.boxOwners.where((o) => o != null).length,
          );

          // At most two boxes per move, and a closed box stays closed.
          expect(result.boxesClosed.length, lessThanOrEqualTo(2));

          if (!result.keepsTurn) turn = turn.other;
        }
        expect(moves, kDotsEdgeCount);
        expect(board.boxesRemaining, 0);
      }
    });

    test('a box, once owned, never changes hands', () {
      final random = math.Random(99);
      var board = DotsBoard.empty();
      var turn = DotsSlot.a;
      final settled = <int, DotsSlot>{};

      while (!board.isComplete) {
        final legal = [
          for (var i = 0; i < kDotsEdgeCount; i++)
            if (!board.isDrawn(i)) i,
        ];
        final result = board.draw(legal[random.nextInt(legal.length)], turn);
        board = result.board;
        for (var box = 0; box < kDotsBoxCount; box++) {
          final owner = board.boxOwners[box];
          if (owner == null) continue;
          expect(
            settled[box] ?? owner,
            owner,
            reason: 'box $box changed hands',
          );
          settled[box] = owner;
        }
        if (!result.keepsTurn) turn = turn.other;
      }
    });

    test('a chain keeps the turn for as long as it keeps closing', () {
      // The rule the whole turn machinery has to survive (§4.1): one
      // player closing several boxes without the turn passing.
      //
      // Building this by hand is fiddly because ADJACENT BOXES SHARE
      // EDGES -- the first attempt drew "all but the last edge" of each
      // top-row box and accidentally completed its neighbour, so only
      // one closure was left. Instead: draw every edge on the board
      // except one per box in the top row, chosen so no two of those
      // held-back edges belong to the same box.
      var board = DotsBoard.empty();
      final holdBack = <int>{
        for (var box = 0; box < kDotsBoxSize; box++)
          // The box's top edge belongs to that box and (for row 0) to
          // nothing above it, so holding it back isolates the closure.
          DotsEdge(true, 0, box).index,
      };

      for (var i = 0; i < kDotsEdgeCount; i++) {
        if (holdBack.contains(i)) continue;
        board = board.draw(i, DotsSlot.a).board;
      }

      // Every top-row box now needs exactly its held-back top edge.
      var kept = 0;
      for (final e in holdBack) {
        final result = board.draw(e, DotsSlot.b);
        board = result.board;
        expect(result.boxesClosed, isNotEmpty);
        if (result.keepsTurn) kept++;
      }

      expect(
        kept,
        kDotsBoxSize,
        reason: 'each closure should have kept the turn',
      );
      expect(board.scoreOf(DotsSlot.b), kDotsBoxSize);
      expect(board.isComplete, isTrue);
    });
  });

  group('resign framing', () {
    test('a decided game is recognised as decided', () {
      // §5.4: past this point the button reads "concede" rather than
      // "resign", because conceding a decided game is a different act.
      var board = DotsBoard.empty();
      // Give A five boxes, which is a majority of nine.
      for (var box = 0; box < 5; box++) {
        for (final e in dotsBoxEdges(box)) {
          if (!board.isDrawn(e)) board = board.draw(e, DotsSlot.a).board;
        }
      }
      expect(board.scoreOf(DotsSlot.a), 5);
      expect(board.isDecidedAgainst(DotsSlot.b), isTrue);
      expect(board.isDecidedAgainst(DotsSlot.a), isFalse);
    });

    test('an even game is not decided against either player', () {
      final board = DotsBoard.empty();
      expect(board.isDecidedAgainst(DotsSlot.a), isFalse);
      expect(board.isDecidedAgainst(DotsSlot.b), isFalse);
    });
  });

  test('slots are their own opposites, and map to the wire', () {
    expect(DotsSlot.a.other, DotsSlot.b);
    expect(DotsSlot.b.other, DotsSlot.a);
    expect(DotsSlot.fromWire(1), DotsSlot.a);
    expect(DotsSlot.fromWire(2), DotsSlot.b);
    expect(DotsSlot.fromWire(0), isNull);
    expect(DotsSlot.fromWire(null), isNull);
  });
}
