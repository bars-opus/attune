import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered and LOOKED AT, not merely diffed.
///
/// Every visual bug in the other Arcade games -- arches shaped like domes,
/// a triangle sitting on the edge of its cover, tokens clipped by the
/// board -- was found by rendering a golden and opening the PNG. Code that
/// reads correctly draws wrongly often enough that this is the only
/// honest check.
void main() {
  const grid = <String>[
    'QWLOVEZXCV',
    'ASDFGHJKLP',
    'ZXCVBNMQWE',
    'RTYUIOPASD',
    'FGHJKLZXCV',
    'BNMQWERTYU',
    'IOPASDFGHJ',
    'KLZXCVBNMQ',
    'WERTYUIOPA',
    'SDFGHJKLZX',
  ];

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      backgroundColor: WordHuntPalette.field,
      body: Center(child: SizedBox(width: 340, height: 340, child: child)),
    ),
  );

  testWidgets('the plain grid', (tester) async {
    await tester.pumpWidget(
      host(
        const WordHuntBoard(
          grid: grid,
          wordLength: 4,
          enabled: true,
          onSubmit: _noop,
        ),
      ),
    );
    await expectLater(
      find.byType(WordHuntBoard),
      matchesGoldenFile('goldens/word_hunt_grid.png'),
    );
  });

  testWidgets('a found word, locked under its pill', (tester) async {
    await tester.pumpWidget(
      host(
        const WordHuntBoard(
          grid: grid,
          wordLength: 4,
          enabled: false,
          onSubmit: _noop,
          lockedCells: [
            WordHuntCell(0, 2),
            WordHuntCell(0, 3),
            WordHuntCell(0, 4),
            WordHuntCell(0, 5),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(WordHuntBoard),
      matchesGoldenFile('goldens/word_hunt_found.png'),
    );
  });

  testWidgets('a diagonal selection mid-drag', (tester) async {
    await tester.pumpWidget(
      host(
        const WordHuntBoard(
          grid: grid,
          wordLength: 5,
          enabled: true,
          onSubmit: _noop,
          lockedCells: [
            WordHuntCell(2, 1),
            WordHuntCell(3, 2),
            WordHuntCell(4, 3),
            WordHuntCell(5, 4),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(WordHuntBoard),
      matchesGoldenFile('goldens/word_hunt_diagonal.png'),
    );
  });

  testWidgets('the reveal: where it was, for whoever missed it', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const WordHuntBoard(
          grid: grid,
          wordLength: 4,
          enabled: false,
          onSubmit: _noop,
          revealedCells: [
            WordHuntCell(7, 1),
            WordHuntCell(6, 2),
            WordHuntCell(5, 3),
            WordHuntCell(4, 4),
          ],
        ),
      ),
    );
    await expectLater(
      find.byType(WordHuntBoard),
      matchesGoldenFile('goldens/word_hunt_reveal.png'),
    );
  });
}

void _noop(List<WordHuntCell> _) {}
