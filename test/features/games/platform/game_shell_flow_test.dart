import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';

/// A game with no rules at all, built from nothing but the shell.
///
/// If the pieces only work one at a time, the first real game to use them
/// finds out. This walks the whole path a player takes -- landing, play,
/// settings, the end, and back -- with real navigation between them.
class _DemoLanding extends StatelessWidget {
  const _DemoLanding({required this.definition});

  final GameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return GameLandingScreen(
      definition: definition,
      state: const GameLandingState(status: GameLandingStatus.fresh),
      entries: demoEntries,
      onHowToPlay: () => showGameHowToPlay(context, definition: definition),
      onPrimary:
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DemoPlay(definition: definition),
            ),
          ),
    );
  }
}

class _DemoPlay extends ConsumerWidget {
  const _DemoPlay({required this.definition});

  final GameDefinition definition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GameScaffold(
      theme: definition.theme,
      title: 'Round 1',
      subtitle: definition.title,
      onSettings:
          () => showGameSettingsSheet(
            context,
            definition: definition,
            onLeaveGame: () {
              // Close the sheet, then leave the game.
              Navigator.of(context)
                ..pop()
                ..pop();
            },
          ),
      body: Center(
        child: GameTile(
          semanticLabel: 'Finish',
          onTap: () {
            ref.read(gameFeedbackProvider).fire(GameEvent.place);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder:
                    (context) => GameCompleteScreen(
                      theme: definition.theme,
                      headline: definition.title,
                      word: 'DONE',
                      names: const ['Ama', 'Kofi'],
                      onBackToGames: () => Navigator.of(context).pop(),
                    ),
              ),
            );
          },
          child: const Text('Finish'),
        ),
      ),
    );
  }
}

void main() {
  Future<FakeSoundService> start(WidgetTester tester) async {
    useSurface(tester, phone);
    final sound = FakeSoundService();
    await tester.pumpWidget(
      gameHost(
        _DemoLanding(definition: demoGame(withSettings: true)),
        prefs: await testPrefs(),
        sound: sound,
      ),
    );
    await tester.pump();
    return sound;
  }

  testWidgets('a player can go from the landing page to the end and back', (
    tester,
  ) async {
    final sound = await start(tester);
    expect(find.byType(GameLandingScreen), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Round 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Finish'));
    await tester.pumpAndSettle();
    expect(find.byType(GameCompleteScreen), findsOneWidget);
    expect(find.text('Ama & Kofi'), findsOneWidget);
    expect(sound.played, [AppSound.gameAnswer, AppSound.gameComplete]);

    await tester.tap(find.text('Back to games'));
    await tester.pumpAndSettle();
    expect(find.byType(GameLandingScreen), findsOneWidget);
    expect(find.byType(GameCompleteScreen), findsNothing);
  });

  testWidgets('how to play opens over the landing page and closes back to it', (
    tester,
  ) async {
    await start(tester);

    await tester.tap(find.bySemanticsLabel('How to play'));
    await tester.pumpAndSettle();
    expect(find.text('1. Tap a tile to pick it.'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(GameHowToPlaySheet), findsNothing);
    expect(find.byType(GameLandingScreen), findsOneWidget);
  });

  testWidgets('sound switched off in settings silences the rest of the game', (
    tester,
  ) async {
    final sound = await start(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(GameSettingsSheet), findsNothing);

    await tester.tap(find.bySemanticsLabel('Finish'));
    await tester.pumpAndSettle();

    // The first test is the control: the same taps with sound on play two
    // sounds.
    expect(find.byType(GameCompleteScreen), findsOneWidget);
    expect(sound.played, isEmpty);
  });

  testWidgets('Leave game in settings returns to the landing page', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    // With the game's own tab in the row, Support starts past the edge.
    await tester.ensureVisible(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave game'));
    await tester.pumpAndSettle();

    expect(find.byType(GameSettingsSheet), findsNothing);
    expect(find.text('Round 1'), findsNothing);
    expect(find.byType(GameLandingScreen), findsOneWidget);
  });
}
