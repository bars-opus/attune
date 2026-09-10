import 'dart:io';
import 'dart:async';

import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/widgets/round_handoff.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/screens/snakes_game_screen.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/state/snakes_provider.dart';
import 'package:attune/features/games/snakes_and_ladders/services/snakes_service.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_board.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_die.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    test('feature motion follows the drawn ladder and snake', () {
      const size = Size(400, 400);
      const ladder = SnakesFeatureMotion(
        from: 2,
        to: 38,
        progress: 0.5,
        movement: SnakesMovement.ladder,
      );
      const snake = SnakesFeatureMotion(
        from: 98,
        to: 78,
        progress: 0.25,
        movement: SnakesMovement.snake,
      );

      expect(
        snakesFeaturePoint(ladder, size),
        Offset.lerp(snakesCellCentre(2, size), snakesCellCentre(38, size), 0.5),
      );
      expect(
        snakesFeaturePoint(snake, size),
        isNot(
          Offset.lerp(
            snakesCellCentre(98, size),
            snakesCellCentre(78, size),
            0.25,
          ),
        ),
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

  group('session lifecycle', () {
    test('the invitation identifies its initiator', () {
      final session = _session(initiatorId: 'user-a');

      expect(session.initiatorId, 'user-a');
      expect(session.isInitiator('user-a'), isTrue);
      expect(session.isInitiator('user-b'), isFalse);
    });

    test('successful creates never reuse the previous attempt key', () async {
      final gateway = _FakeSnakesGateway();
      final container = ProviderContainer(
        overrides: [snakesGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snakesProvider.notifier);
      await notifier.createSession('relationship');
      await notifier.createSession('relationship');

      expect(gateway.createKeys, hasLength(2));
      expect(gateway.createKeys[1], isNot(gateway.createKeys[0]));
    });

    test('a failed create keeps its key for a safe retry', () async {
      final gateway = _FakeSnakesGateway(failFirstCreate: true);
      final container = ProviderContainer(
        overrides: [snakesGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snakesProvider.notifier);
      expect(await notifier.createSession('relationship'), isNull);
      expect(await notifier.createSession('relationship'), isNotNull);

      expect(gateway.createKeys, hasLength(2));
      expect(gateway.createKeys[1], gateway.createKeys[0]);
    });

    test('a late load from another session cannot replace this game', () async {
      final gateway = _FakeSnakesGateway();
      final oldLoad = Completer<SnakesSession>();
      final newLoad = Completer<SnakesSession>();
      gateway.loadResults
        ..['old'] = oldLoad.future
        ..['new'] = newLoad.future;
      final container = ProviderContainer(
        overrides: [snakesGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(snakesProvider.notifier);
      final first = notifier.load('old');
      final second = notifier.load('new');
      newLoad.complete(_session(sessionId: 'new'));
      await second;
      oldLoad.complete(_session(sessionId: 'old'));
      await first;

      expect(container.read(snakesProvider).session?.sessionId, 'new');
    });

    testWidgets('an initial load failure offers a retry instead of spinning', (
      tester,
    ) async {
      final gateway = _FakeSnakesGateway(loadError: true);
      await tester.pumpWidget(
        _host(gateway, viewer: 'user-a', session: 'missing'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.text('Could not open this game. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping your own invitation shows the board, no die', (
      tester,
    ) async {
      // The single thing this whole flow is for. Tapping the card you
      // sent used to land on a lobby that said "no talking required"
      // over a "Waiting for your partner" line. It now lands on the
      // board itself, with the die put away because there is no turn to
      // take -- a die that cannot be rolled is a button that ignores
      // you.
      final gateway = _FakeSnakesGateway(
        session: _session(initiatorId: 'user-a'),
      );
      await tester.pumpWidget(_host(gateway, viewer: 'user-a'));
      await tester.pumpAndSettle();

      expect(find.byType(SnakesBoardView), findsOneWidget);
      expect(find.byType(SnakesDie), findsNothing);
      expect(find.text("Ama's turn"), findsOneWidget);
      expect(
        find.textContaining('partner'),
        findsNothing,
        reason: 'the board still calls them "partner" rather than by name',
      );
      expect(find.text('Cancel invitation'), findsOneWidget);
      expect(find.text('Join the game'), findsNothing);
      expect(find.text('No talking required.'), findsNothing);
    });

    testWidgets('the invitee is offered the game over the board', (
      tester,
    ) async {
      final gateway = _FakeSnakesGateway(
        session: _session(initiatorId: 'user-a'),
      );
      await tester.pumpWidget(_host(gateway, viewer: 'user-b'));
      await tester.pumpAndSettle();

      expect(find.byType(SnakesBoardView), findsOneWidget);
      expect(find.text('Join the game'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('joining puts the die in the invitee\'s hand', (tester) async {
      // Accepting used to mean a lobby button, a route push and a fresh
      // screen. It is now a reload in place: same board, die appears.
      final gateway = _FakeSnakesGateway(
        session: _session(initiatorId: 'user-a'),
      );
      await tester.pumpWidget(_host(gateway, viewer: 'user-b'));
      await tester.pumpAndSettle();

      gateway.session = _session(
        initiatorId: 'user-a',
        status: 'active',
        currentTurnUserId: 'user-b',
      );
      await tester.tap(find.text('Join the game'));
      await tester.pumpAndSettle();

      expect(gateway.accepted, ['session']);
      expect(find.byType(SnakesDie), findsOneWidget);
      expect(find.text('Join the game'), findsNothing);
    });

    testWidgets('the die is hidden while it is the partner\'s turn', (
      tester,
    ) async {
      // Previously the screen popped itself the moment the turn passed,
      // which is what put the player back on the lobby's "carry on"
      // screen after every roll. It stays now, and simply puts the die
      // away.
      final gateway = _FakeSnakesGateway(
        session: _session(
          initiatorId: 'user-a',
          status: 'active',
          currentTurnUserId: 'user-b',
        ),
      );
      await tester.pumpWidget(_host(gateway, viewer: 'user-a'));
      await tester.pumpAndSettle();

      expect(find.byType(SnakesBoardView), findsOneWidget);
      expect(find.byType(SnakesDie), findsNothing);
      expect(find.text("Ama's turn"), findsOneWidget);
      expect(
        find.textContaining('partner'),
        findsNothing,
        reason: 'the board still calls them "partner" rather than by name',
      );
    });

    testWidgets('a rematch does not inherit the last game\'s hand-off', (
      tester,
    ) async {
      // Play again swaps this screen onto a new session. Carrying the
      // finished game's "you have rolled" flag across would arm the exit
      // on a board this player has not rolled in, closing the rematch
      // the moment it became the partner's turn.
      //
      // The player must genuinely roll first: the flag is only set by a
      // settled turn of their own, so a test that skips the roll proves
      // nothing about carrying it over.
      final gateway = _FakeSnakesGateway(
        session: _session(
          initiatorId: 'user-a',
          status: 'active',
          currentTurnUserId: 'user-a',
        ),
      );
      gateway.rollResult = SnakesTurn.fromJson({
        'round_number': 1,
        'active_partner_id': 'user-a',
        'die_roll': 3,
        'moved_from': 0,
        'rolled_to': 3,
        'moved_to': 3,
        'movement_kind': 'normal',
        'did_bounce': false,
      });

      await tester.pumpWidget(_host(gateway, viewer: 'user-a'));
      await tester.pumpAndSettle();

      // Roll, and let the walk and the read-time settle. The board is
      // now the partner's, so the hand-off is armed.
      gateway.session = _session(
        initiatorId: 'user-a',
        status: 'completed',
        currentTurnUserId: 'user-b',
      );
      await tester.tap(find.byType(SnakesDie));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Play again'), findsOneWidget);

      // The rematch: a fresh session, already the partner's turn.
      gateway.nextSession = _session(
        sessionId: 'session-1',
        initiatorId: 'user-a',
        status: 'active',
        currentTurnUserId: 'user-b',
      );
      await tester.tap(find.text('Play again'));
      await tester.pumpAndSettle();

      expect(
        find.byType(RoundHandoff),
        findsNothing,
        reason: 'the rematch armed the exit before anyone rolled',
      );
      await tester.pump(kRoundHandoffDuration * 2);
      expect(find.byType(SnakesBoardView), findsOneWidget);
    });

    testWidgets('opening a board that is already theirs does not leave', (
      tester,
    ) async {
      // The hold is for a turn you just took. A player who opens the
      // game to look at the board while it is their partner's must not
      // have it close under them -- that is the game walking out of the
      // room.
      final gateway = _FakeSnakesGateway(
        session: _session(
          initiatorId: 'user-a',
          status: 'active',
          currentTurnUserId: 'user-b',
        ),
      );
      await tester.pumpWidget(_host(gateway, viewer: 'user-a'));
      await tester.pumpAndSettle();

      expect(find.byType(RoundHandoff), findsNothing);

      await tester.pump(kRoundHandoffDuration * 2);
      expect(find.byType(SnakesBoardView), findsOneWidget);
    });

    testWidgets('arriving without a session starts one', (tester) async {
      // From the picker. The tap on the game already said what the
      // player wants; a lobby asking them to press "Start a game" was
      // asking the same question twice.
      final gateway = _FakeSnakesGateway();
      await tester.pumpWidget(_host(gateway, viewer: 'user-a', session: null));
      await tester.pumpAndSettle();

      expect(gateway.createKeys, hasLength(1));
      expect(find.byType(SnakesBoardView), findsOneWidget);
    });

    testWidgets('arriving without a session resumes the game in progress', (
      tester,
    ) async {
      final gateway = _FakeSnakesGateway(
        session: _session(
          sessionId: 'in-progress',
          status: 'active',
          currentTurnUserId: 'user-a',
        ),
      );
      await tester.pumpWidget(_host(gateway, viewer: 'user-a', session: null));
      await tester.pumpAndSettle();

      expect(gateway.createKeys, isEmpty);
      expect(find.byType(SnakesDie), findsOneWidget);
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
        chat.contains('snakesGame'),
        isTrue,
        reason: 'tapping the game in the sheet goes nowhere',
      );

      final router = File('lib/app/routing/app_router.dart').readAsStringSync();
      expect(router.contains("name: 'snakesGame'"), isTrue);
      // One route, not two. The lobby is gone and must not come back by
      // accident: every entry point lands on the board.
      expect(router.contains('snakesLobby'), isFalse);
      expect(chat.contains('snakesLobby'), isFalse);
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
      // The screen used to pop itself the moment the turn passed. With
      // the lobby gone there is nothing sensible behind it to pop TO,
      // and popping is what put the player on a "carry on" screen after
      // every roll. It stays and hides the die instead -- covered live
      // by "the die is hidden while it is the partner's turn".
      expect(
        source.contains('_leaving'),
        isFalse,
        reason: 'the screen pops itself again after a roll',
      );
    });
  });
}

SnakesSession _session({
  String sessionId = 'session',
  String initiatorId = 'user-a',
  String status = 'invited',
  String? currentTurnUserId,
}) => SnakesSession.fromJson({
  'session_id': sessionId,
  'initiator_id': initiatorId,
  'status': status,
  'user_a': 'user-a',
  'user_b': 'user-b',
  'position_a': 0,
  'position_b': 0,
  'current_round': 1,
  if (currentTurnUserId != null) 'current_turn_user_id': currentTurnUserId,
  'board': {'ladders': <String, int>{}, 'snakes': <String, int>{}},
  'rounds': <Object>[],
});

/// The game screen under a host route, so a pop has somewhere to go.
///
/// [session] is the session id the chat card pointed at; null stands for
/// arriving from the picker, with no session in hand.
Widget _host(
  _FakeSnakesGateway gateway, {
  required String viewer,
  String? session = 'session',
}) => ProviderScope(
  overrides: [
    snakesGatewayProvider.overrideWithValue(gateway),
    snakesCurrentUserIdProvider.overrideWithValue(viewer),
    gameSessionLiveProvider.overrideWith((_, __) => const Stream<void>.empty()),
    // A real name, so the board is asserted to USE it rather than to
    // fall back to a generic label.
    gamePartnerNameProvider.overrideWith((ref) async => 'Ama'),
  ],
  child: MaterialApp(
    home: SnakesGameScreen(relationshipId: 'relationship', sessionId: session),
  ),
);

class _FakeSnakesGateway implements SnakesGateway {
  _FakeSnakesGateway({
    this.failFirstCreate = false,
    this.loadError = false,
    this.session,
  });

  final bool failFirstCreate;
  final bool loadError;

  /// What getState and getActiveSession both return. Tests reassign it to
  /// stand for the partner acting between two loads.
  SnakesSession? session;

  /// Served instead of the default once createSession runs, so a test
  /// can describe the game a rematch lands on.
  SnakesSession? nextSession;
  final List<String> createKeys = [];
  final List<String> accepted = [];
  final List<String> declined = [];
  final Map<String, Future<SnakesSession>> loadResults = {};

  @override
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  }) async {
    createKeys.add(idempotencyKey);
    if (failFirstCreate && createKeys.length == 1) {
      throw const SnakesApiError(code: 'NETWORK', message: 'Try again.');
    }
    final sessionId = 'session-${createKeys.length}';
    session =
        nextSession ?? _session(sessionId: sessionId, initiatorId: 'user-a');
    return sessionId;
  }

  @override
  Future<SnakesSession> getState(String sessionId) {
    if (loadError) throw StateError('database details must not reach the UI');
    final queued = loadResults[sessionId];
    if (queued != null) return queued;
    final current = session;
    // Only serves the configured session when it IS the one asked for --
    // a fake that answered every id with the same row would hide a
    // screen loading the wrong game.
    if (current != null && current.sessionId == sessionId) {
      return Future.value(current);
    }
    return Future.value(_session(sessionId: sessionId));
  }

  @override
  Future<void> acceptSession(String sessionId) async => accepted.add(sessionId);

  @override
  Future<void> declineSession(String sessionId) async =>
      declined.add(sessionId);

  @override
  Future<SnakesSession?> getActiveSession(String relationshipId) async =>
      session;

  @override
  /// The turn a roll returns, when a test needs one to actually happen.
  SnakesTurn? rollResult;

  @override
  Future<SnakesTurn> rollDie({
    required String sessionId,
    required int roundNumber,
  }) async {
    final turn = rollResult;
    if (turn == null) throw UnimplementedError();
    return turn;
  }
}
