import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../platform/support/game_test_support.dart';

void main() {
  testWidgets('the hero words can be read on their tiles', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Builder(
          builder:
              (context) => Center(
                child: thisOrThatGame.heroBuilder(context, thisOrThatTheme),
              ),
        ),
        prefs: await testPrefs(),
      ),
    );

    // The two tiles wear the game's two accents, THIS then THAT.
    final tiles = tester.widgetList<GameTile>(find.byType(GameTile)).toList();
    expect(tiles, hasLength(2));
    expect(tiles.map((tile) => tile.color), [
      const Color(0xFFFF8A76),
      const Color(0xFF8DA7FF),
    ]);

    for (final (word, face) in [
      ('THIS', tiles[0].color),
      ('THAT', tiles[1].color),
    ]) {
      // The ink as drawn: the word's own style merged over the tile's.
      final paragraph = tester.widget<RichText>(
        find.descendant(
          of: find.byType(GameTile),
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == word,
          ),
        ),
      );
      final ink = paragraph.text.style!.color!;
      expect(contrast(ink, face), greaterThanOrEqualTo(4.5), reason: word);
    }
    // The control: the default tile face is not what is being measured.
    expect(tiles.first.color, isNot(GameTheme.tile));
  });
}
