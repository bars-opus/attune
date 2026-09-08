import 'package:attune/features/games/dots_and_boxes/models/dots_boxes_rules.dart';
import 'package:attune/features/games/dots_and_boxes/prototype/dots_boxes_prototype_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered AND looked at. Every visual bug in the other Arcade games --
/// dome-shaped arches, an off-centre triangle, a brown smear where amber
/// was specified -- was found by opening the PNG, not by reading code.
void main() {
  /// The default test viewport is 800x600 LANDSCAPE, which is not a
  /// phone and made the first golden look left-biased when the layout was
  /// fine. Every golden here renders at a portrait phone size.
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 13 Pro
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// The on-screen midpoint of an edge, derived from the painted board's
  /// real rect. Computing it from a guessed origin is what made the
  /// first version of these taps miss entirely.
  Offset edgeMidpoint(WidgetTester tester, int edgeIndex) {
    final board = tester.getRect(
      find
          .byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.size.width > 0 &&
                w.size.width == w.size.height,
          )
          .last,
    );
    const inset = 8.0;
    final gap = (board.width - inset * 2) / kDotsBoxSize;
    Offset dot(int r, int c) =>
        board.topLeft + Offset(inset + c * gap, inset + r * gap);

    final e = DotsEdge.fromIndex(edgeIndex);
    final from = dot(e.row, e.col);
    final to = e.horizontal ? dot(e.row, e.col + 1) : dot(e.row + 1, e.col);
    return (from + to) / 2;
  }

  testWidgets('an empty board', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: DotsBoxesPrototypeScreen()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DotsBoxesPrototypeScreen),
      matchesGoldenFile('goldens/dots_boxes_empty.png'),
    );
  });

  testWidgets('a played board draws the edges that were committed', (
    tester,
  ) async {
    // Asserts BEHAVIOUR, not pixels. An earlier version of this test
    // diffed a golden of a part-played board and cost an hour chasing a
    // rendering detail in a build that exists to be played, not shipped.
    // The rules themselves have twenty unit tests; this one only proves
    // the screen commits what it was told to.
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: DotsBoxesPrototypeScreen()),
    );
    await tester.pumpAndSettle();

    for (final edgeIndex in dotsBoxEdges(0)) {
      final mid = edgeMidpoint(tester, edgeIndex);
      await tester.tapAt(mid);
      await tester.pump();
      await tester.tapAt(mid);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Box 0 closed, so one player is on 1 and the other on 0, and the
    // closing player kept the turn.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a first tap previews rather than drawing', (tester) async {
    // The rule that makes an unrecoverable move safe (§7.1).
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: DotsBoxesPrototypeScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tap a gap to choose a line.'), findsOneWidget);

    await tester.tapAt(edgeMidpoint(tester, 0));
    await tester.pump();

    expect(find.text('Tap it again to draw it.'), findsOneWidget);

    // And a second tap on the same edge commits it, returning the hint.
    await tester.tapAt(edgeMidpoint(tester, 0));
    await tester.pump();
    expect(find.text('Tap a gap to choose a line.'), findsOneWidget);
  });
}
