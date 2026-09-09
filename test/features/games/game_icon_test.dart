import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The SVG tests that used to live here are gone with the SVGs: two
/// games had drawn logos and six did not, which read as unfinished. Every
/// game now has a glyph on its own gradient, so what needs proving is
/// that the set is COMPLETE and DISTINCT rather than that files exist.
void main() {
  const shippedGames = [
    'this_or_that',
    'truth_or_dare',
    '36_questions',
    'mirror',
    'sliding_scale',
    'scenario',
    'love_map',
    'paint_ball',
    'snakes_and_ladders',
    'word_hunt',
  ];

  test('every shipped game has its own palette', () {
    // A game falling through to the neutral slate would sit in the grid
    // looking like a placeholder next to nine coloured tiles.
    final fallback = GamePalette.of('definitely_not_a_game');
    for (final gameType in shippedGames) {
      final palette = GamePalette.of(gameType);
      expect(
        palette.start,
        isNot(fallback.start),
        reason: '$gameType has no palette and renders as the slate fallback',
      );
    }
  });

  test('no two games share a starting colour', () {
    // The colour IS the identity: two games sharing one makes the grid
    // read as a mistake.
    final seen = <Color, String>{};
    for (final gameType in shippedGames) {
      final start = GamePalette.of(gameType).start;
      expect(
        seen[start],
        isNull,
        reason: '$gameType and ${seen[start]} share a colour',
      );
      seen[start] = gameType;
    }
  });

  test('every gradient actually varies', () {
    // start == end is a flat fill wearing a gradient's clothes.
    for (final gameType in shippedGames) {
      final palette = GamePalette.of(gameType);
      expect(palette.start, isNot(palette.end), reason: gameType);
    }
  });

  test('every shipped game has its own glyph', () {
    final glyphs = <IconData, String>{};
    for (final gameType in shippedGames) {
      final glyph = gameGlyphFor(gameType);
      expect(
        glyphs[glyph],
        isNull,
        reason: '$gameType and ${glyphs[glyph]} share a glyph',
      );
      glyphs[glyph] = gameType;
    }
  });

  test('an unknown game still renders something', () {
    // A game_type from a newer build, or a retired one still in history.
    expect(gameGlyphFor('a_game_from_the_future'), isNotNull);
    expect(GamePalette.of('a_game_from_the_future').start, isNotNull);
    expect(GamePalette.of(null).start, isNotNull);
  });

  testWidgets('the tile renders at the size it is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GameIcon(gameType: 'word_hunt', size: 64)),
        ),
      ),
    );
    final size = tester.getSize(find.byType(GameIcon));
    expect(size.width, 64);
    expect(size.height, 64);
  });

  testWidgets('every shipped game renders without throwing', (tester) async {
    for (final gameType in shippedGames) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: GameIcon(gameType: gameType, size: 56)),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: gameType);
    }
  });

  test('the catalogue and the tile set agree on which games exist', () {
    // If a game is in the sheet it needs a tile, and vice versa --
    // otherwise one of the two silently falls back.
    for (final gameType in shippedGames) {
      expect(
        chatGameDestinationForType(gameType),
        isNotNull,
        reason: '$gameType has a tile but is not in the catalogue',
      );
    }
  });
}
