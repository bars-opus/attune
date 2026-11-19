import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    GameDefinition? definition,
    double textScale = 1,
  }) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showGameHowToPlay(
                        context,
                        definition: definition ?? demoGame(),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
        prefs: await testPrefs(),
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opened from above the game, in a light app, it is dark', (
    tester,
  ) async {
    // `open` calls it from a plain Scaffold: no GameBackdrop above.
    await open(tester);

    expect(
      Theme.of(tester.element(find.text('open'))).brightness,
      Brightness.light,
      reason: 'the control: the app is light where the sheet was opened',
    );
    expect(
      Theme.of(tester.element(find.byType(GameHowToPlaySheet))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('lists the rules in order, numbered', (tester) async {
    await open(tester);

    expect(find.text('How to play'), findsOneWidget);
    final first = find.text('1. Tap a tile to pick it.');
    final second = find.text('2. Your partner answers the same question.');
    final third = find.text('3. See both answers together.');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(third).dy));
  });

  testWidgets('the rules can be read on the sheet', (tester) async {
    await open(tester);

    final ink = inkOnGround(tester, of: find.byType(GameHowToPlaySheet));
    expect(
      ink.map((piece) => piece.text),
      containsAll(['How to play', '1. Tap a tile to pick it.']),
    );
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
    );
  });

  testWidgets('Got it closes the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.byType(GameHowToPlaySheet), findsNothing);
  });

  testWidgets('many long rules scroll, and Got it stays on screen', (
    tester,
  ) async {
    final long = GameDefinition(
      gameType: 'long',
      title: 'Long',
      collectionLabel: 'Demo',
      tagline: 'Many rules.',
      theme: const GameTheme(primary: GameColors.wordHunt),
      icon: Icons.extension_rounded,
      heroBuilder: (_, __) => const SizedBox(),
      howToPlay: [
        for (var i = 0; i < 30; i++)
          'Rule number $i says a fairly long thing about how the game works.',
      ],
    );
    await open(tester, definition: long, textScale: 2);

    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.text('Got it'));
    expect(button.bottom, lessThanOrEqualTo(phone.height));
    expect(button.top, greaterThan(0));
  });
}
