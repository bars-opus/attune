import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  const theme = GameTheme(primary: GameColors.thisOrThat);

  Future<FakeSoundService> pump(
    WidgetTester tester, {
    List<String> names = const ['Ama', 'Kofi'],
    Widget? summary,
    VoidCallback? onPlayAgain,
    VoidCallback? onBackToGames,
    Map<String, Object> stored = const {},
    bool reduceMotion = false,
    double textScale = 1,
    FakeSoundService? sound,
  }) async {
    useSurface(tester, phone);
    final fake = sound ?? FakeSoundService();
    await tester.pumpWidget(
      gameHost(
        GameCompleteScreen(
          theme: theme,
          headline: 'This or That',
          word: 'COMPLETE',
          names: names,
          summary: summary,
          onPlayAgain: onPlayAgain,
          onBackToGames: onBackToGames ?? () {},
        ),
        prefs: await testPrefs(stored),
        sound: fake,
        reduceMotion: reduceMotion,
        textScale: textScale,
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('spells the word one tile per letter', (tester) async {
    await pump(tester);

    expect(find.text('This or That'), findsOneWidget);
    expect(find.byType(GameTile), findsNWidgets('COMPLETE'.length));
  });

  testWidgets('names the two people who played', (tester) async {
    await pump(tester);

    expect(find.text('Ama & Kofi'), findsOneWidget);
  });

  testWidgets('a name that has not loaded is left out, not shown blank', (
    tester,
  ) async {
    await pump(tester, names: const ['Ama', '  ']);

    expect(find.text('Ama'), findsOneWidget);
    expect(find.textContaining('&'), findsNothing);
  });

  testWidgets('shows what the game has to say about the result', (
    tester,
  ) async {
    await pump(tester, summary: const Text('You matched on 7 of 10.'));

    expect(find.text('You matched on 7 of 10.'), findsOneWidget);
  });

  testWidgets('everything written on the ground can be read there', (
    tester,
  ) async {
    await pump(tester, summary: const Text('You matched on 7 of 10.'));

    final ink = inkOnGround(tester, of: find.byType(GameCompleteScreen));
    expect(
      ink.map((piece) => piece.text),
      containsAll(['This or That', 'Ama & Kofi', 'You matched on 7 of 10.']),
    );
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
    );
  });

  testWidgets('the result sits in the middle of the space above the buttons', (
    tester,
  ) async {
    await pump(tester, onPlayAgain: () {});

    final top = tester.getRect(find.text('This or That')).top;
    final bottom = tester.getRect(find.text('Ama & Kofi')).bottom;
    final buttons = tester.getRect(find.text('Play again')).top;

    final above = top;
    final below = buttons - bottom;
    expect(above, greaterThan(100), reason: 'not pinned to the top');
    // The button's own padding sits between the two, so near, not equal.
    expect((above - below).abs(), lessThan(40));
  });

  testWidgets('both buttons report their own tap', (tester) async {
    final taps = <String>[];
    await pump(
      tester,
      onPlayAgain: () => taps.add('again'),
      onBackToGames: () => taps.add('back'),
    );

    await tester.tap(find.text('Play again'));
    await tester.tap(find.text('Back to games'));

    expect(taps, ['again', 'back']);
  });

  testWidgets('there is no Play again when the game cannot be replayed', (
    tester,
  ) async {
    // The control is the test above, where the same lookup finds it.
    await pump(tester);

    expect(find.text('Play again'), findsNothing);
    expect(find.text('Back to games'), findsOneWidget);
  });

  testWidgets('the win sound plays once, however often the screen rebuilds', (
    tester,
  ) async {
    final sound = await pump(tester);
    expect(sound.played, [AppSound.gameComplete]);

    // A rebuild with new content is not a second win.
    await pump(
      tester,
      summary: const Text('You matched on 7 of 10.'),
      sound: sound,
    );

    expect(find.text('You matched on 7 of 10.'), findsOneWidget);
    expect(sound.played, [AppSound.gameComplete]);
  });

  testWidgets('with sound switched off the screen arrives silently', (
    tester,
  ) async {
    final sound = await pump(
      tester,
      stored: {GamePrefsNotifier.soundKey: false},
    );

    expect(sound.played, isEmpty);
  });

  testWidgets('reduce motion shows the finished screen on the first frame', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameCompleteScreen(
          theme: theme,
          headline: 'This or That',
          word: 'COMPLETE',
          onBackToGames: () {},
        ),
        prefs: await testPrefs(),
        reduceMotion: true,
      ),
    );
    await tester.pump();

    expect(find.byType(GameTile), findsNWidgets('COMPLETE'.length));
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'nothing is still animating',
    );
  });

  testWidgets('the largest text size scrolls instead of overflowing', (
    tester,
  ) async {
    await pump(
      tester,
      summary: const Text(
        'You matched on 7 of 10, and disagreed most about mornings, '
        'holidays and what counts as being on time.',
      ),
      onPlayAgain: () {},
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Back to games'), findsOneWidget);
  });
}
