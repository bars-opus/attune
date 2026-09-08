import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = <String>[
    'ABCDEFGHIJ',
    'KLMNOPQRST',
    'UVWXYZABCD',
    'EFGHIJKLMN',
    'OPQRSTUVWX',
    'YZABCDEFGH',
    'IJKLMNOPQR',
    'STUVWXYZAB',
    'CDEFGHIJKL',
    'MNOPQRSTUV',
  ];

  /// 400x400 makes each cell exactly 40px, so a coordinate maps to a cell
  /// without any rounding to reason about.
  Future<List<List<WordHuntCell>>> mount(
    WidgetTester tester, {
    bool enabled = true,
    int wordLength = 4,
    WordHuntBoardController? controller,
  }) async {
    final submissions = <List<WordHuntCell>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: WordHuntBoard(
                grid: grid,
                wordLength: wordLength,
                enabled: enabled,
                controller: controller,
                onSubmit: submissions.add,
              ),
            ),
          ),
        ),
      ),
    );
    return submissions;
  }

  Offset centre(int row, int col) =>
      Offset(200 - 200 + col * 40 + 20, 200 - 200 + row * 40 + 20);

  testWidgets('a horizontal drag submits the cells it crossed', (tester) async {
    final submissions = await mount(tester);
    final board = tester.getTopLeft(find.byType(WordHuntBoard));

    final gesture = await tester.startGesture(board + centre(2, 1));
    await tester.pump();
    await gesture.moveTo(board + centre(2, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submissions, hasLength(1));
    expect(submissions.single, const [
      WordHuntCell(2, 1),
      WordHuntCell(2, 2),
      WordHuntCell(2, 3),
      WordHuntCell(2, 4),
    ]);
  });

  testWidgets('a drag longer than the word stops at the word length', (
    tester,
  ) async {
    final submissions = await mount(tester, wordLength: 3);
    final board = tester.getTopLeft(find.byType(WordHuntBoard));

    final gesture = await tester.startGesture(board + centre(5, 0));
    await tester.pump();
    await gesture.moveTo(board + centre(5, 9));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submissions.single, hasLength(3));
  });

  testWidgets('a single tap-and-release is not submitted', (tester) async {
    // A stray tap is not a guess. Submitting it would burn a rate-limit
    // slot and flash a dismissal for nothing.
    final submissions = await mount(tester);
    final board = tester.getTopLeft(find.byType(WordHuntBoard));

    final gesture = await tester.startGesture(board + centre(3, 3));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submissions, isEmpty);
  });

  testWidgets('a disabled board ignores drags entirely', (tester) async {
    final submissions = await mount(tester, enabled: false);
    final board = tester.getTopLeft(find.byType(WordHuntBoard));

    final gesture = await tester.startGesture(board + centre(1, 1));
    await tester.pump();
    await gesture.moveTo(board + centre(1, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submissions, isEmpty);
  });

  testWidgets('a diagonal drag produces a diagonal path', (tester) async {
    final submissions = await mount(tester);
    final board = tester.getTopLeft(find.byType(WordHuntBoard));

    final gesture = await tester.startGesture(board + centre(1, 1));
    await tester.pump();
    await gesture.moveTo(board + centre(4, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(submissions.single, const [
      WordHuntCell(1, 1),
      WordHuntCell(2, 2),
      WordHuntCell(3, 3),
      WordHuntCell(4, 4),
    ]);
  });

  testWidgets('the controller reports a miss without crashing the board', (
    tester,
  ) async {
    final controller = WordHuntBoardController();
    await mount(tester, controller: controller);

    controller.showMiss(const [WordHuntCell(0, 0), WordHuntCell(0, 1)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('every cell carries a semantic label and a tap target', (
    tester,
  ) async {
    // Tap-first-letter then tap-last-letter is the only path that works
    // with switch control, so it is not a convenience.
    final submissions = await mount(tester);
    final semantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^A, row 1, column 1')),
    );
    expect(semantics.label, contains('row 1, column 1'));

    // Activated through the SEMANTICS TREE, which is what assistive
    // technology actually does -- and what the board supports, because a
    // real tap recogniser in this layer would beat the pan that every
    // dragging player relies on.
    final handle = tester.ensureSemantics();
    tester.semantics.performAction(
      find.semantics.byLabel(RegExp(r'^U, row 3, column 1')),
      SemanticsAction.tap,
    );
    await tester.pump();
    tester.semantics.performAction(
      find.semantics.byLabel(RegExp(r'^X, row 3, column 4')),
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    handle.dispose();

    expect(submissions, hasLength(1));
    expect(submissions.single.first, const WordHuntCell(2, 0));
    expect(submissions.single.last, const WordHuntCell(2, 3));
  });
}
