import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/models/word_hunt_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nearestDirection', () {
    test('snaps the four axes exactly', () {
      expect(WordHuntSelection.nearestDirection(dRow: 0, dCol: 4), (0, 1));
      expect(WordHuntSelection.nearestDirection(dRow: 0, dCol: -4), (0, -1));
      expect(WordHuntSelection.nearestDirection(dRow: 4, dCol: 0), (1, 0));
      expect(WordHuntSelection.nearestDirection(dRow: -4, dCol: 0), (-1, 0));
    });

    test('snaps the four diagonals exactly', () {
      expect(WordHuntSelection.nearestDirection(dRow: 3, dCol: 3), (1, 1));
      expect(WordHuntSelection.nearestDirection(dRow: -3, dCol: -3), (-1, -1));
      expect(WordHuntSelection.nearestDirection(dRow: 3, dCol: -3), (1, -1));
      expect(WordHuntSelection.nearestDirection(dRow: -3, dCol: 3), (-1, 1));
    });

    test('a shallow drag stays on the axis rather than falling diagonal', () {
      // (1, 3) is 18 degrees off east. Rounding each component would send
      // it to the south-east diagonal, which is 27 degrees away -- the
      // diagonals would swallow most of the plane and a player dragging
      // along a row would keep dropping onto a diagonal.
      expect(WordHuntSelection.nearestDirection(dRow: 1, dCol: 3), (0, 1));
      expect(WordHuntSelection.nearestDirection(dRow: -1, dCol: 4), (0, 1));
      expect(WordHuntSelection.nearestDirection(dRow: 3, dCol: 1), (1, 0));
    });

    test('the boundary between an axis and a diagonal is the halfway angle', () {
      // 22.5 degrees is the tie point. Just under holds the axis, just
      // over commits to the diagonal.
      expect(WordHuntSelection.nearestDirection(dRow: 4, dCol: 10), (0, 1));
      expect(WordHuntSelection.nearestDirection(dRow: 6, dCol: 10), (1, 1));
    });
  });

  group('extend', () {
    const anchor = WordHuntCell(4, 4);

    test('a stationary finger selects only the anchor', () {
      final s = WordHuntSelection.extend(
        anchor: anchor,
        target: anchor,
        maxLength: 5,
      );
      expect(s.cells, [anchor]);
    });

    test('extends along the snapped line, one cell per step', () {
      final s = WordHuntSelection.extend(
        anchor: anchor,
        target: const WordHuntCell(4, 7),
        maxLength: 6,
      );
      expect(s.cells, const [
        WordHuntCell(4, 4),
        WordHuntCell(4, 5),
        WordHuntCell(4, 6),
        WordHuntCell(4, 7),
      ]);
    });

    test('a diagonal advances both coordinates together', () {
      final s = WordHuntSelection.extend(
        anchor: anchor,
        target: const WordHuntCell(7, 7),
        maxLength: 6,
      );
      expect(s.cells, const [
        WordHuntCell(4, 4),
        WordHuntCell(5, 5),
        WordHuntCell(6, 6),
        WordHuntCell(7, 7),
      ]);
    });

    test('stops at the word length rather than running on', () {
      // Dragging six cells for a four-letter word cannot make a longer
      // word, and a pill that kept growing would suggest it could.
      final s = WordHuntSelection.extend(
        anchor: anchor,
        target: const WordHuntCell(4, 9),
        maxLength: 4,
      );
      expect(s.length, 4);
      expect(s.head, const WordHuntCell(4, 7));
    });

    test('truncates at the board edge instead of wrapping or clamping', () {
      // A clamped cell would appear twice in the path; a wrapped one
      // would be somewhere the finger never went.
      final s = WordHuntSelection.extend(
        anchor: const WordHuntCell(0, 8),
        target: const WordHuntCell(0, 20),
        maxLength: 6,
      );
      expect(s.cells, const [WordHuntCell(0, 8), WordHuntCell(0, 9)]);
      expect(s.cells.toSet().length, s.cells.length);
    });

    test('dragging backwards past the anchor does not invert the line', () {
      // Projection is clamped at zero, so pulling back through the anchor
      // shrinks the selection to the anchor rather than growing it the
      // other way -- which would silently change which cell is first, and
      // the server compares an ordered path.
      final s = WordHuntSelection.extend(
        anchor: anchor,
        target: const WordHuntCell(4, 0),
        maxLength: 5,
        lockedDirection: (0, 1),
      );
      expect(s.cells, [anchor]);
    });

    test('a locked direction holds through a wobble', () {
      // Once a drag establishes an axis it keeps it: a finger crossing
      // into a neighbouring direction mid-drag should not flicker the
      // whole pill onto a diagonal.
      final wobbled = WordHuntSelection.extend(
        anchor: anchor,
        target: const WordHuntCell(5, 7),
        maxLength: 6,
        lockedDirection: (0, 1),
      );
      expect(wobbled.direction, (0, 1));
      expect(wobbled.head, const WordHuntCell(4, 7));
    });

    test('projection keeps the length honest when the finger drifts', () {
      // Three cells east and one row down: the projection onto east is 3,
      // so three steps -- not two (the smaller delta) and not four.
      final s = WordHuntSelection.extend(
        anchor: anchor,
        target: const WordHuntCell(5, 7),
        maxLength: 8,
        lockedDirection: (0, 1),
      );
      expect(s.length, 4);
    });

    test('every produced path is a straight line of distinct cells', () {
      // The property the server independently enforces. Checked here over
      // a sweep so a future change to the snapping cannot quietly start
      // producing paths the server will reject as malformed.
      for (var row = 0; row < 10; row++) {
        for (var col = 0; col < 10; col++) {
          final s = WordHuntSelection.extend(
            anchor: const WordHuntCell(5, 5),
            target: WordHuntCell(row, col),
            maxLength: 7,
          );
          expect(s.cells.toSet().length, s.cells.length,
              reason: 'duplicate cell targeting ($row,$col)');
          expect(s.cells.every((c) => c.inBounds), isTrue,
              reason: 'out of bounds targeting ($row,$col)');
          if (s.cells.length >= 2) {
            final dr = s.cells[1].row - s.cells[0].row;
            final dc = s.cells[1].col - s.cells[0].col;
            expect(kWordHuntDirections.contains((dr, dc)), isTrue,
                reason: 'illegal step targeting ($row,$col)');
            for (var i = 2; i < s.cells.length; i++) {
              expect(s.cells[i].row - s.cells[i - 1].row, dr);
              expect(s.cells[i].col - s.cells[i - 1].col, dc);
            }
          }
        }
      }
    });
  });
}
