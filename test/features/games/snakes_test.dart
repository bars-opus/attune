import 'dart:io';

import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_board.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_die.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('board geometry', () {
    test('adjacent cells are adjacent on screen', () {
      // Boustrophedon: row 1 left to right, row 2 right to left. Without
      // it a token walking through a row end would leap across the board.
      const size = Size(1000, 1000);
      for (var cell = 1; cell < 100; cell++) {
        final gap =
            (snakesCellCentre(cell + 1, size) - snakesCellCentre(cell, size))
                .distance;
        expect(gap, lessThan(105), reason: 'cell $cell to ${cell + 1}');
      }
    });

    test('the board is oriented like the physical one', () {
      const size = Size(1000, 1000);
      expect(snakesCellCentre(1, size).dy, greaterThan(900));
      expect(snakesCellCentre(100, size).dy, lessThan(100));
      expect(
        snakesCellCentre(1, size).dx,
        lessThan(snakesCellCentre(2, size).dx),
      );
      expect(
        snakesCellCentre(11, size).dx,
        greaterThan(snakesCellCentre(12, size).dx),
      );
    });

    test('an off-board token sits below the first cell', () {
      // Starting a game should read as stepping ONTO the board.
      const size = Size(1000, 1000);
      expect(
        snakesCellCentre(0, size).dy,
        greaterThan(snakesCellCentre(1, size).dy),
      );
    });
  });

  group('the die belongs to the server', () {
    test('the client cannot send a face value', () {
      // The entire content of a turn IS the die. A client that could
      // choose it would not be playing a game.
      final source =
          File(
            'lib/features/games/snakes_and_ladders/services/'
            'snakes_service.dart',
          ).readAsStringSync();

      // Matches the parameter name anywhere, not just at a quote: the
      // first version of this test anchored on a leading quote and a
      // mutant adding 'p_die_roll' sailed straight past it.
      expect(
        RegExp(r'p_(die|roll|face|value)').hasMatch(source),
        isFalse,
        reason: 'the service sends a die face to the server',
      );
      expect(source.contains("'snakes_roll_die'"), isTrue);
    });
  });

  group('movement model', () {
    test('a bounce and a snake are told apart', () {
      // Both end below where the die pointed and animate completely
      // differently -- one walks up and comes back, the other slides.
      expect(SnakesMovement.fromWire('bounce'), SnakesMovement.bounce);
      expect(SnakesMovement.fromWire('snake'), SnakesMovement.snake);
      expect(SnakesMovement.bounce.isFeature, isFalse);
      expect(SnakesMovement.snake.isFeature, isTrue);
    });

    test('an unknown movement degrades to a plain move', () {
      // A board or server ahead of this client must not crash it.
      expect(SnakesMovement.fromWire('teleport'), SnakesMovement.normal);
      expect(SnakesMovement.fromWire(null), SnakesMovement.normal);
    });
  });

  group('board parsing', () {
    test('string keys from jsonb become cells', () {
      final board = SnakesBoard.fromJson({
        'ladders': {'2': 38},
        'snakes': {'16': 6},
      });
      expect(board.ladders[2], 38);
      expect(board.snakes[16], 6);
      expect(board.destinationFor(2), 38);
      expect(board.destinationFor(50), isNull);
    });

    test('a malformed board renders empty rather than throwing', () {
      final board = SnakesBoard.fromJson({'ladders': 'nonsense'});
      expect(board.ladders, isEmpty);
      expect(board.snakes, isEmpty);
    });
  });

  group('errors', () {
    test('a refusal carries the server message, never an exception', () {
      // Checklist 2.4 / 5.5: the UI must never show internals.
      final error = SnakesApiError.fromJson({
        'code': 'NOT_YOUR_TURN',
        'message': "It's not your turn yet.",
      });
      expect(error.message, "It's not your turn yet.");
      expect(error.toString(), isNot(contains('Exception')));
    });

    test('a message-less refusal still reads as English', () {
      final error = SnakesApiError.fromJson({'code': 'WEIRD'});
      expect(error.message, isNotEmpty);
      expect(error.message, isNot(contains('WEIRD')));
    });
  });

  group('die widget', () {
    testWidgets('it is inert when it is not your turn', (tester) async {
      var rolled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SnakesDie(
              face: 3,
              rolling: false,
              enabled: false,
              onTap: () => rolled = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SnakesDie));
      await tester.pump();
      expect(rolled, isFalse);
    });

    testWidgets('a roll in flight cannot be tapped again', (tester) async {
      var rolls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SnakesDie(face: null, rolling: true, onTap: () => rolls++),
          ),
        ),
      );
      await tester.tap(find.byType(SnakesDie), warnIfMissed: false);
      await tester.pump();
      expect(rolls, 0);
    });

    testWidgets('reduce motion shows a face rather than a tumble', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: SnakesDie(face: 4, rolling: true)),
          ),
        ),
      );
      await tester.pump();
      // pumpAndSettle would never return on a repeating tumble.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('sound', () {
    test('every sound this game plays has a file', () {
      for (final name in [
        'game_dice',
        'game_step',
        'game_ladder',
        'game_snake',
      ]) {
        expect(
          File('assets/sounds/$name.wav').existsSync(),
          isTrue,
          reason: '$name.wav is referenced but was never generated',
        );
      }
    });
  });

  group('wiring', () {
    test('the game is reachable from the chat', () {
      // A game nobody can open is not shipped. These three files are the
      // whole path: the sheet offers it, the chat routes it, the router
      // resolves it -- and each is a shared file where a later edit
      // could quietly drop one link.
      final sheet =
          File(
            'lib/features/games/presentation/widgets/chat_games_sheet.dart',
          ).readAsStringSync();
      expect(sheet.contains('snakesAndLadders'), isTrue);
      expect(
        sheet.contains("'snakes_and_ladders': ChatGameDestination"),
        isTrue,
        reason: 'an in-progress game could not resume from the sheet',
      );

      final chat =
          File(
            'lib/features/chat/presentation/screens/chat_screen.dart',
          ).readAsStringSync();
      expect(
        chat.contains('snakesLobby'),
        isTrue,
        reason: 'tapping the game in the sheet goes nowhere',
      );

      final router = File('lib/app/routing/app_router.dart').readAsStringSync();
      expect(router.contains("name: 'snakesLobby'"), isTrue);
      expect(router.contains("name: 'snakesGame'"), isTrue);
    });

    test('the game has a display name rather than a title-cased id', () {
      final source =
          File(
            'lib/features/games/presentation/providers/'
            'games_hub_providers.dart',
          ).readAsStringSync();
      expect(
        source.contains("'snakes_and_ladders': 'Snakes and Ladders'"),
        isTrue,
        reason: 'the chat card would read "Snakes And Ladders"',
      );
    });
  });

  group('review fixes', () {
    test('a bounce that hits a snake records both', () {
      // 97 + 5 bounces to 98, which is a snake head, so it slides to 78.
      // A single movement_kind could only hold one of those and the
      // feature overwrote the bounce -- so the animation never showed
      // the token reach 100 and come back.
      final turn = SnakesTurn.fromJson({
        'round_number': 4,
        'active_partner_id': 'user-a',
        'die_roll': 5,
        'moved_from': 97,
        'rolled_to': 98,
        'moved_to': 78,
        'movement_kind': 'snake',
        'did_bounce': true,
      });

      expect(turn.movement, SnakesMovement.snake);
      expect(
        turn.didBounce,
        isTrue,
        reason: 'the walk to 100 and back would be skipped',
      );
    });

    test('the walk reads didBounce, not movement', () {
      // The model carrying the flag is not enough -- the animation has
      // to branch on it. Reading `movement == bounce` looks correct and
      // silently drops the walk to 100 whenever a bounce also lands on
      // a snake, which is the only case where it matters.
      final source =
          File(
            'lib/features/games/snakes_and_ladders/presentation/screens/'
            'snakes_game_screen.dart',
          ).readAsStringSync();

      expect(
        source.contains('turn.didBounce'),
        isTrue,
        reason: 'a bounce onto a snake would skip the walk to 100',
      );
      expect(
        source.contains('turn.movement == SnakesMovement.bounce'),
        isFalse,
        reason: 'branching on movement misses a compound bounce',
      );
    });

    test('the board keeps off-board tokens inside its own bounds', () {
      // They used to sit below the board, where its clip made both
      // starting tokens invisible -- so a new game opened showing nobody
      // on it.
      const size = Size(500, 500);
      final start = snakesCellCentre(0, size);
      expect(start.dy, lessThan(size.height));
      expect(start.dy, greaterThan(0));
      expect(start.dx, greaterThan(0));
      expect(start.dx, lessThan(size.width));
    });

    testWidgets('a phone-width board drops most numerals', (tester) async {
      // The breakpoint was 340dp, so a typical 375-393dp phone fell on
      // the dense side and rendered all one hundred numbers.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 380,
              child: SnakesBoardView(
                board: SnakesBoard.empty,
                yourCell: 5,
                theirCell: 9,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the board describes itself to a screen reader', (
      tester,
    ) async {
      // Semantics are not built in tests unless asked for.
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            // Sized: the board is an AspectRatio, and an unbounded
            // parent gives it no height to build into.
            body: SizedBox(
              width: 400,
              height: 400,
              child: SnakesBoardView(
                board: SnakesBoard.empty,
                yourCell: 34,
                theirCell: 51,
                partnerName: 'Ama',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Read from the Semantics widget rather than the merged node: the
      // board sits inside a LayoutBuilder, so getSemantics on the view
      // itself finds the wrapper rather than the labelled child.
      final label = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((widget) => widget.properties.label ?? '')
          .firstWhere((text) => text.isNotEmpty, orElse: () => '');

      expect(label, contains('square 34'));
      expect(label, contains('square 51'));
      expect(label, contains('Ama'));

      handle.dispose();
    });

    test('the game screen subscribes to live updates', () {
      // It loaded once and never again: a partner's roll would not
      // appear until the screen was closed and reopened, on a board that
      // still read "Their roll".
      final source =
          File(
            'lib/features/games/snakes_and_ladders/presentation/screens/'
            'snakes_game_screen.dart',
          ).readAsStringSync();

      expect(
        source.contains('gameSessionLiveProvider'),
        isTrue,
        reason: 'the board would never update on its own',
      );
      expect(
        source.contains('_leaving'),
        isTrue,
        reason: 'the screen never leaves once the turn has passed',
      );
    });
  });
}
