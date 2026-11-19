import 'dart:async';

import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_registry.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/games_catalogue.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_landing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';
import 'support/route_recorder.dart';

/// A game's controller that records what the page asks of it. Its
/// [onPrimary] runs until the test calls [finishPrimary], the way a real one
/// runs until the game screen it pushed is closed.
class _FakeController extends GameController {
  _FakeController(this.state, {this.rows = const []});

  final GameLandingState state;
  final List<GameEntry> rows;

  int primaryCalls = 0;
  int remindCalls = 0;
  GameLandingState? primaryState;

  /// When set, [onPrimary] fails with it instead of running.
  Object? primaryError;

  Completer<void> _primary = Completer<void>();

  void finishPrimary() => _primary.complete();

  @override
  GameLandingState watchLanding(WidgetRef ref) => state;

  @override
  Future<void> onPrimary(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) {
    primaryCalls++;
    primaryState = state;
    final error = primaryError;
    if (error != null) return Future.error(error);
    _primary = Completer<void>();
    return _primary.future;
  }

  @override
  Future<void> onRemind(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) async {
    remindCalls++;
  }

  @override
  List<GameEntry> entries(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) => rows;

  @override
  Future<void> openSession(
    BuildContext context,
    WidgetRef ref, {
    required String sessionId,
  }) async {}
}

GameDefinition _otherGame({List<String> howToPlay = const []}) {
  return GameDefinition(
    gameType: 'other',
    title: 'Another Game',
    collectionLabel: 'Elsewhere',
    tagline: 'Not the tile tutorial.',
    theme: const GameTheme(primary: GameColors.truthOrDare),
    icon: Icons.casino_rounded,
    heroBuilder: (context, theme) => const SizedBox.shrink(),
    howToPlay: howToPlay,
    controller: _FakeController(
      const GameLandingState(status: GameLandingStatus.fresh),
    ),
  );
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required String gameType,
  required List<GameDefinition> games,
  Size surface = phone,
}) async {
  useSurface(tester, surface);
  await tester.pumpWidget(
    gameRouterHost(
      home: GameLandingPage(gameType: gameType),
      prefs: await testPrefs(),
      overrides: [gameRegistryProvider.overrideWithValue(GameRegistry(games))],
    ),
  );
  await tester.pump();
}

GamePrimaryButton _button(WidgetTester tester) =>
    tester.widget<GamePrimaryButton>(find.byType(GamePrimaryButton));

void main() {
  testWidgets('shows the game the route names', (tester) async {
    final games = [
      demoGame(
        controller: _FakeController(
          const GameLandingState(status: GameLandingStatus.fresh),
        ),
      ),
      _otherGame(),
    ];

    await _pumpPage(tester, gameType: 'other', games: games);
    expect(find.text('Another Game'), findsOneWidget);
    expect(find.text('Not the tile tutorial.'), findsOneWidget);
    expect(find.text('Tile Tutorial'), findsNothing);

    // The control: the other game's route shows that game instead.
    await _pumpPage(tester, gameType: 'demo', games: games);
    expect(find.text('Tile Tutorial'), findsOneWidget);
    expect(find.text('Learn how the shell fits together.'), findsOneWidget);
    expect(find.text('Another Game'), findsNothing);
  });

  testWidgets('the button and rows come from the game\'s controller', (
    tester,
  ) async {
    final rowTaps = <String>[];
    final controller = _FakeController(
      const GameLandingState(
        status: GameLandingStatus.yourTurn,
        sessionId: 's-1',
      ),
      rows: [
        GameEntry(title: 'Gentle', onTap: (_) => rowTaps.add('Gentle')),
        GameEntry(
          title: 'Spicy',
          subtitle: 'Turn it up',
          onTap: (_) => rowTaps.add('Spicy'),
        ),
      ],
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('1. Gentle'), findsOneWidget);
    expect(find.text('2. Spicy'), findsOneWidget);
    expect(find.text('Turn it up'), findsOneWidget);
    expect(find.text('3. Past games'), findsNothing);

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(controller.primaryCalls, 1);
    expect(controller.primaryState?.sessionId, 's-1');
    controller.finishPrimary();
    await tester.pump();

    await tester.tap(find.text('2. Spicy'));
    await tester.pump();
    expect(rowTaps, ['Spicy']);
  });

  testWidgets('a second tap while the first is still starting does nothing', (
    tester,
  ) async {
    // Review Focus 1.
    final controller = _FakeController(
      const GameLandingState(status: GameLandingStatus.fresh),
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(_button(tester).busy, isTrue);
    await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
    await tester.pump();
    expect(controller.primaryCalls, 1);
    controller.finishPrimary();
    await tester.pump();
    expect(_button(tester).busy, isFalse);
    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(
      controller.primaryCalls,
      2,
      reason: 'the control: it is tappable again once the first finished',
    );
    controller.finishPrimary();
    await tester.pump();
  });

  testWidgets('a second tap on a row while the first is still starting does '
      'nothing', (tester) async {
    var rowCalls = 0;
    var running = Completer<void>();
    Future<void> startTone(BuildContext _) {
      rowCalls++;
      running = Completer<void>();
      return running.future;
    }

    final controller = _FakeController(
      const GameLandingState(status: GameLandingStatus.fresh),
      rows: [
        GameEntry(title: 'Gentle', onTap: startTone),
        GameEntry(title: 'Spicy', onTap: startTone),
      ],
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    await tester.tap(find.text('1. Gentle'));
    await tester.pump();
    expect(rowCalls, 1);
    // The button waits with the row: one game is being started.
    expect(_button(tester).busy, isTrue);

    await tester.tap(find.text('1. Gentle'), warnIfMissed: false);
    await tester.tap(find.text('2. Spicy'), warnIfMissed: false);
    await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
    await tester.pump();
    expect(rowCalls, 1);
    expect(controller.primaryCalls, 0);

    running.complete();
    await tester.pump();
    expect(_button(tester).busy, isFalse);
    await tester.tap(find.text('2. Spicy'));
    await tester.pump();
    expect(
      rowCalls,
      2,
      reason: 'the control: it is tappable again once the first finished',
    );
    running.complete();
    await tester.pump();
  });

  testWidgets('a start that fails is reported and the button can be pressed '
      'again', (tester) async {
    final controller = _FakeController(
      const GameLandingState(status: GameLandingStatus.fresh),
    )..primaryError = StateError('no connection');
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();

    // Reported to FlutterError, not lost and not escaping as an uncaught
    // error: the test binding hands it over here.
    expect(tester.takeException(), isA<StateError>());
    expect(_button(tester).busy, isFalse);

    controller.primaryError = null;
    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(controller.primaryCalls, 2);
    controller.finishPrimary();
    await tester.pump();
  });

  testWidgets('a game the app does not know gets a readable page, not a '
      'crash', (tester) async {
    // Review Focus 4.
    await _pumpPage(tester, gameType: 'made_up', games: gameCatalogue);

    expect(tester.takeException(), isNull);
    expect(find.text('This game is not available.'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);

    final ink = inkOnGround(tester, of: find.byType(GameLandingPage));
    expect(ink, isNotEmpty);
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
      reason: 'dark ink on the dark ground',
    );
  });

  testWidgets('a coming-soon game cannot be started', (tester) async {
    // Every state that is not a game in progress, and no controller at all.
    final notInProgress = [
      GameLandingStatus.fresh,
      GameLandingStatus.finished,
      GameLandingStatus.loading,
    ];
    final controllers = <_FakeController?>[
      for (final status in notInProgress)
        _FakeController(
          GameLandingState(status: status),
          rows: const [GameEntry(title: 'Gentle')],
        ),
      null,
    ];
    expect(controllers, hasLength(4));

    for (final controller in controllers) {
      await _pumpPage(
        tester,
        gameType: 'demo',
        games: [
          demoGame(
            availability: GameAvailability.comingSoon,
            controller: controller,
          ),
        ],
      );
      final reason = '${controller?.state.status ?? 'no controller'}';

      expect(find.text('Coming soon'), findsOneWidget, reason: reason);
      expect(_button(tester).onTap, isNull, reason: reason);
      expect(find.text('1. Gentle'), findsNothing, reason: reason);
      await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
      await tester.pump();
      expect(controller?.primaryCalls ?? 0, 0, reason: reason);
    }
    // The control is the next test: the same game with a session in
    // progress opens.
  });

  testWidgets('a coming-soon game already in progress can still be opened', (
    tester,
  ) async {
    final controller = _FakeController(
      const GameLandingState(
        status: GameLandingStatus.yourTurn,
        sessionId: 's-1',
      ),
      rows: const [GameEntry(title: 'Gentle')],
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [
        demoGame(
          availability: GameAvailability.comingSoon,
          controller: controller,
        ),
      ],
    );

    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
    expect(_button(tester).onTap, isNotNull);
    expect(find.text('1. Gentle'), findsOneWidget);

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(controller.primaryCalls, 1);
    controller.finishPrimary();
    await tester.pump();
  });

  testWidgets('the reminder reaches the game', (tester) async {
    final controller = _FakeController(
      const GameLandingState(
        status: GameLandingStatus.waiting,
        partnerName: 'Ama',
        canRemind: true,
      ),
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    expect(find.text('Waiting for Ama'), findsOneWidget);
    await tester.tap(find.text('Send a reminder'));
    await tester.pump();

    expect(controller.remindCalls, 1);
    expect(controller.primaryCalls, 0);
  });

  testWidgets('there is no help button for a game with no rules written', (
    tester,
  ) async {
    await _pumpPage(tester, gameType: 'other', games: [_otherGame()]);
    expect(find.text('Another Game'), findsOneWidget);
    expect(find.bySemanticsLabel('How to play'), findsNothing);

    // The control: a game with rules shows it, and it opens them.
    await _pumpPage(
      tester,
      gameType: 'other',
      games: [
        _otherGame(howToPlay: const ['Pick one.', 'See theirs.']),
      ],
    );
    expect(find.bySemanticsLabel('How to play'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('How to play'));
    await tester.pumpAndSettle();
    expect(find.text('1. Pick one.'), findsOneWidget);
  });

  testWidgets('a long name on a small phone does not overflow', (tester) async {
    // Review Focus 6.
    final controller = _FakeController(
      const GameLandingState(
        status: GameLandingStatus.waiting,
        partnerName: 'Bartholomew-James',
        canRemind: true,
      ),
      rows: demoEntries,
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
      surface: const Size(320, 568),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Waiting for Bartholomew-James'), findsOneWidget);
  });
}
