import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false, double? width}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        ),
      );

  /// How large each tile is being drawn: 0 before it arrives, 1 once it
  /// has landed, briefly past 1 on the way.
  ///
  /// By key, because a tile has transforms of its own inside it and those
  /// always read 1.
  Iterable<double> scales(WidgetTester tester) => tester
      .widgetList<Transform>(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return widget is Transform &&
              key is ValueKey<String> &&
              key.value.startsWith('game-letter-tile-');
        }),
      )
      // The x scale. Not getMaxScaleOnAxis: a 2D scale leaves z at 1, so
      // the maximum reads 1 for every tile that is not yet full size.
      .map((t) => t.transform.storage[0]);

  testWidgets('one tile per letter, in capitals', (tester) async {
    await tester.pumpWidget(host(const GameLetterTiles(word: 'done')));
    await tester.pumpAndSettle();

    expect(find.byType(GameTile), findsNWidgets(4));
    for (final letter in ['D', 'O', 'N', 'E']) {
      expect(find.text(letter), findsOneWidget);
    }
  });

  testWidgets('a space is a gap, not a tile', (tester) async {
    await tester.pumpWidget(host(const GameLetterTiles(word: 'ALL DONE')));
    await tester.pumpAndSettle();

    expect(find.byType(GameTile), findsNWidgets(7));
  });

  testWidgets('a screen reader hears the word, not seven letters', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const GameLetterTiles(word: 'COMPLETE')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('COMPLETE'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the tiles land one after another and end at full size', (
    tester,
  ) async {
    await tester.pumpWidget(host(const GameLetterTiles(word: 'PLAY')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Mid-entry the first letter is ahead of the last.
    final mid = scales(tester).toList();
    expect(mid, hasLength(4));
    expect(mid.first, greaterThan(mid.last));

    await tester.pumpAndSettle();
    final end = scales(tester).toList();
    expect(end, hasLength(4));
    expect(end, everyElement(closeTo(1.0, 1e-9)));
  });

  testWidgets('reduce motion shows the word at once', (tester) async {
    await tester.pumpWidget(
      host(const GameLetterTiles(word: 'PLAY'), reduceMotion: true),
    );
    await tester.pump();

    final shown = scales(tester).toList();
    expect(shown, hasLength(4));
    expect(shown, everyElement(closeTo(1.0, 1e-9)));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('art that should not move does not', (tester) async {
    await tester.pumpWidget(
      host(const GameLetterTiles(word: 'PLAY', animate: false)),
    );
    await tester.pump();

    expect(scales(tester), everyElement(closeTo(1.0, 1e-9)));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a long word shrinks to fit instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const GameLetterTiles(word: 'CONGRATULATIONS', animate: false),
        width: 200,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(GameLetterTiles)).width,
      lessThanOrEqualTo(200),
    );
    expect(find.byType(GameTile), findsNWidgets(15));
  });

  testWidgets('a larger text size does not push a letter out of its tile', (
    tester,
  ) async {
    Future<Size> letterAt(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: Center(
                child: GameLetterTiles(word: 'PLAY', animate: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.text('P'));
    }

    final normal = await letterAt(1);
    final largest = await letterAt(2);

    expect(normal.height, greaterThan(0));
    expect(largest, normal);
  });
}
