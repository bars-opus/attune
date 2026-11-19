import 'dart:io';

import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';

/// Pictures of the shell, on a phone, a large phone and a tablet.
///
/// These are for looking at. A golden that only ever gets compared to
/// itself proves the screen did not change, not that it was ever right:
/// open the PNGs when they are regenerated.
void main() {
  setUpAll(loadGameTestFonts);

  // Text is drawn slightly differently on each operating system, so a
  // picture made on a Mac does not match pixel for pixel on the Linux CI
  // machine. These are compared where they are made. Everything a golden
  // would catch that a machine can check -- ink colour, layout, overflow --
  // has its own test that runs everywhere.
  final comparedHere = Platform.isMacOS;

  final coachTarget = GlobalKey();

  Widget play({bool coach = false}) {
    final board = Center(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final (i, letter) in 'ATTUNE'.split('').indexed)
            SizedBox(
              key: i == 2 ? coachTarget : null,
              width: 68,
              height: 73,
              child: GameTile(
                onTap: () {},
                selected: i == 4,
                color: i == 4 ? GameColors.wordHunt : GameTheme.tile,
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: i == 4 ? Colors.white : GameTheme.tileInk,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return GameScaffold(
      theme: const GameTheme(primary: GameColors.wordHunt),
      title: 'Round 3 of 10',
      subtitle: 'Tile Tutorial',
      onSettings: () {},
      actions: [
        GameRoundButton(
          icon: Icons.lightbulb_outline_rounded,
          semanticLabel: 'Hint',
          caption: 'Hint',
          onTap: () {},
        ),
        GameRoundButton(
          icon: Icons.undo_rounded,
          semanticLabel: 'Undo',
          caption: 'Undo',
          onTap: () {},
        ),
      ],
      body:
          coach
              ? GameCoach(
                gameType: 'demo',
                steps: [
                  GameCoachStep(
                    text: 'Tap a tile to pick it.',
                    target: coachTarget,
                  ),
                ],
                child: board,
              )
              : board,
    );
  }

  Widget sheetHost(Future<void> Function(BuildContext) open) => Builder(
    builder:
        (context) => GameLandingScreen(
          definition: demoGame(withSettings: true),
          state: const GameLandingState(status: GameLandingStatus.fresh),
          entries: demoEntries,
          onPrimary: () => open(context),
        ),
  );

  final screens = <String, ({Widget Function() build, bool opensSheet})>{
    'landing_fresh': (
      build:
          () => GameLandingScreen(
            definition: demoGame(),
            state: const GameLandingState(status: GameLandingStatus.fresh),
            entries: demoEntries,
            onPrimary: () {},
            onHowToPlay: () {},
          ),
      opensSheet: false,
    ),
    'landing_waiting': (
      build:
          () => GameLandingScreen(
            definition: demoGame(color: GameColors.truthOrDare),
            state: const GameLandingState(
              status: GameLandingStatus.waiting,
              partnerName: 'Ama',
              caption: 'Round 3 of 10',
              canRemind: true,
            ),
            entries: demoEntries,
            onPrimary: () {},
            onRemind: () {},
            onHowToPlay: () {},
          ),
      opensSheet: false,
    ),
    'play': (build: play, opensSheet: false),
    'play_coach': (build: () => play(coach: true), opensSheet: false),
    'settings': (
      build:
          () => sheetHost(
            (context) => showGameSettingsSheet(
              context,
              definition: demoGame(withSettings: true),
              onHowToPlay: () {},
              onLeaveGame: () {},
            ),
          ),
      opensSheet: true,
    ),
    'how_to_play': (
      build:
          () => sheetHost(
            (context) => showGameHowToPlay(context, definition: demoGame()),
          ),
      opensSheet: true,
    ),
    'complete': (
      build:
          () => GameCompleteScreen(
            theme: const GameTheme(primary: GameColors.thisOrThat),
            headline: 'This or That',
            word: 'COMPLETE',
            names: const ['Ama', 'Kofi'],
            summary: const Text(
              'You matched on 7 of 10.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            onPlayAgain: () {},
            onBackToGames: () {},
          ),
      opensSheet: false,
    ),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    for (final MapEntry(key: surface, value: size) in goldenSurfaces.entries) {
      testWidgets('$name on a $surface', (tester) async {
        useSurface(tester, size);
        await tester.pumpWidget(
          gameHost(screen.build(), prefs: await testPrefs()),
        );
        await tester.pumpAndSettle();
        if (screen.opensSheet) {
          await tester.tap(find.byType(GamePrimaryButton));
          await tester.pumpAndSettle();
        }

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/shell_$name.$surface.png'),
        );
      }, skip: !comparedHere);
    }
  }

  testWidgets('landing at the largest text size on a phone', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameLandingScreen(
          definition: demoGame(),
          state: const GameLandingState(status: GameLandingStatus.yourTurn),
          entries: demoEntries,
          onPrimary: () {},
          onHowToPlay: () {},
        ),
        prefs: await testPrefs(),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/shell_landing_large_text.phone.png'),
    );
  }, skip: !comparedHere);
}
