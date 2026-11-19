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
import 'package:go_router/go_router.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';
import 'support/route_recorder.dart';

/// How many times a game re-read its state on coming back.
final _reReads = StateProvider<int>((ref) => 0);

/// A game's controller that records what the page asks of it. Its
/// [onPrimary] stays pending until the test calls [finishPrimary], so a test
/// can hold a start in flight -- a consent dialog, the call that creates the
/// game -- and see what the page does meanwhile. A real one completes once
/// navigation has begun.
class _FakeController extends GameController {
  _FakeController(this.state, {this.rows = const []});

  final GameLandingState state;
  final List<GameEntry> rows;

  int primaryCalls = 0;
  int remindCalls = 0;
  GameLandingState? primaryState;

  int resumeCalls = 0;

  /// When set, [onPrimary] fails with it instead of running.
  Object? primaryError;

  /// When set, [onPrimary] also does this as it starts, such as pushing the
  /// game's screen. Its own future is not what [onPrimary] returns.
  Future<void> Function(BuildContext context)? primaryBody;

  /// Each start's future, oldest first.
  final List<Completer<void>> runs = [];

  void finishPrimary() => runs.last.complete();

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
    final run = Completer<void>();
    runs.add(run);
    final body = primaryBody;
    if (body != null) unawaited(body(context));
    return run.future;
  }

  /// When set, [onResume] also does this, as a real re-read would.
  void Function(WidgetRef ref)? resumeBody;

  @override
  void onResume(WidgetRef ref) {
    resumeCalls++;
    resumeBody?.call(ref);
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
  List<RouteBase> routes = const [],
}) async {
  useSurface(tester, surface);
  await tester.pumpWidget(
    gameRouterHost(
      home: GameLandingPage(gameType: gameType),
      prefs: await testPrefs(),
      overrides: [gameRegistryProvider.overrideWithValue(GameRegistry(games))],
      routes: routes,
    ),
  );
  await tester.pump();
}

/// Lets a push or pop finish. Not pumpAndSettle: a busy button's ring
/// spins for as long as it is busy, and a test of whether it stopped must
/// fail on the assertion, not time out.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
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

  testWidgets('two taps in the same frame start one game', (tester) async {
    // Review Focus 1, at its sharpest: no frame between the taps, so the
    // button has not been rebuilt as busy and still answers the second.
    final controller = _FakeController(
      const GameLandingState(status: GameLandingStatus.fresh),
    );
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(controller.primaryCalls, 1);

    controller.finishPrimary();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    expect(
      controller.primaryCalls,
      2,
      reason: 'the control: the same tap starts one once the first finished',
    );
    controller.finishPrimary();
    await tester.pump();
  });

  testWidgets('two taps on rows in the same frame start one game', (
    tester,
  ) async {
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
    await tester.tap(find.text('2. Spicy'));
    await tester.pump();
    expect(rowCalls, 1);

    running.complete();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('2. Spicy'));
    await tester.pump();
    expect(
      rowCalls,
      2,
      reason: 'the control: the same tap starts one once the first finished',
    );
    running.complete();
    await tester.pump();
  });

  group('a start that opens the game at once', () {
    // A start keeping the contract completes as soon as it has asked for
    // the push; the pushed route only reaches the tree on the next frame.
    // Until then the page is still in front and must still be busy.
    late int screensOpened;
    late _FakeController controller;
    late int rowCalls;

    Future<void> pumpOpeningAtOnce(WidgetTester tester) async {
      screensOpened = 0;
      rowCalls = 0;
      void open(BuildContext context) {
        screensOpened++;
        unawaited(context.pushNamed('gamesHub'));
      }

      controller = _FakeController(
        const GameLandingState(status: GameLandingStatus.fresh),
        rows: [
          GameEntry(
            title: 'Gentle',
            onTap: (context) {
              rowCalls++;
              open(context);
            },
          ),
        ],
      );
      controller.primaryBody = (context) async {
        open(context);
        controller.finishPrimary();
      };
      await _pumpPage(
        tester,
        gameType: 'demo',
        games: [demoGame(controller: controller)],
      );
    }

    testWidgets('two taps in the same frame open one game screen', (
      tester,
    ) async {
      await pumpOpeningAtOnce(tester);

      await tester.tap(find.byType(GamePrimaryButton));
      await tester.tap(find.byType(GamePrimaryButton));
      await _settleRoute(tester);

      expect(controller.primaryCalls, 1);
      expect(screensOpened, 1);
      expect(
        find.text('opened:gamesHub:', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('the button and a row in the same frame open one game '
        'screen', (tester) async {
      await pumpOpeningAtOnce(tester);

      await tester.tap(find.byType(GamePrimaryButton));
      await tester.tap(find.text('1. Gentle'));
      await _settleRoute(tester);

      expect(controller.primaryCalls + rowCalls, 1);
      expect(screensOpened, 1);
      expect(
        find.text('opened:gamesHub:', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a tap one frame later lands on the game screen, not the '
        'page', (tester) async {
      // The control for the two above: once the push has landed, the
      // pushed screen takes the tap.
      await pumpOpeningAtOnce(tester);

      await tester.tap(find.byType(GamePrimaryButton));
      await tester.pump();
      await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
      await _settleRoute(tester);

      expect(controller.primaryCalls, 1);
      expect(find.text('opened:gamesHub:'), findsOneWidget);
    });
  });

  testWidgets('a start that ends without opening anything frees the button '
      'a frame later', (tester) async {
    // Holding busy to the end of the frame must not strand the button when
    // nothing was pushed: a start that failed, or one that had nowhere to go.
    final controller = _FakeController(
      const GameLandingState(status: GameLandingStatus.fresh),
    )..primaryError = StateError('no connection');
    await _pumpPage(
      tester,
      gameType: 'demo',
      games: [demoGame(controller: controller)],
    );

    await tester.tap(find.byType(GamePrimaryButton));
    // The frame the start ended in, then the one that redraws the button.
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(_button(tester).busy, isFalse);

    controller.primaryError = null;
    controller.primaryBody = (context) async => controller.finishPrimary();
    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    await tester.pump();
    expect(controller.primaryCalls, 2);
    expect(_button(tester).busy, isFalse);

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pump();
    await tester.pump();
    expect(controller.primaryCalls, 3);
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

  group('coming back to the page', () {
    testWidgets('coming back after the game replaced its own screen leaves '
        'the button free', (tester) async {
      // A start completes once navigation has begun; it never waits for the
      // player to come back. So a game screen that replaces itself (Play
      // again) leaves nothing on the page waiting.
      var rowCalls = 0;
      final controller = _FakeController(
        const GameLandingState(status: GameLandingStatus.fresh),
        rows: [GameEntry(title: 'Gentle', onTap: (_) => rowCalls++)],
      );
      controller.primaryBody = (context) async {
        unawaited(context.pushNamed('testGame'));
        controller.finishPrimary();
      };
      await _pumpPage(
        tester,
        gameType: 'demo',
        games: [demoGame(controller: controller)],
        routes: [
          GoRoute(
            path: '/test/game',
            name: 'testGame',
            builder:
                (context, state) => Scaffold(
                  appBar: AppBar(),
                  body: TextButton(
                    onPressed: () => context.pushReplacementNamed('testNext'),
                    child: const Text('Play again'),
                  ),
                ),
          ),
          GoRoute(
            path: '/test/next',
            name: 'testNext',
            builder:
                (context, state) => Scaffold(
                  appBar: AppBar(),
                  body: const Text('the next game'),
                ),
          ),
        ],
      );

      await tester.tap(find.byType(GamePrimaryButton));
      await _settleRoute(tester);
      await tester.tap(find.text('Play again'));
      await _settleRoute(tester);
      expect(find.text('the next game'), findsOneWidget);
      expect(controller.resumeCalls, 0, reason: 'covered, not back yet');
      await tester.tap(find.byType(BackButton));
      await _settleRoute(tester);

      expect(find.text('Tile Tutorial'), findsOneWidget);
      expect(_button(tester).busy, isFalse);
      expect(controller.resumeCalls, 1);
      await tester.tap(find.text('1. Gentle'));
      await tester.pump();
      expect(rowCalls, 1);
    });

    testWidgets('closing a sheet during a start does not free the button', (
      tester,
    ) async {
      // A start can show a dialog of its own and then go on working (a
      // network call that creates the game): the page uncovering is not
      // the start ending.
      var rowCalls = 0;
      final controller = _FakeController(
        const GameLandingState(status: GameLandingStatus.fresh),
        rows: [GameEntry(title: 'Gentle', onTap: (_) => rowCalls++)],
      );
      await _pumpPage(
        tester,
        gameType: 'demo',
        games: [demoGame(controller: controller)],
      );

      await tester.tap(find.byType(GamePrimaryButton));
      await tester.pump();
      expect(_button(tester).busy, isTrue);

      await tester.tap(find.bySemanticsLabel('How to play'));
      await _settleRoute(tester);
      expect(find.text('1. Tap a tile to pick it.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await _settleRoute(tester);
      expect(find.text('1. Tap a tile to pick it.'), findsNothing);

      await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
      await tester.tap(find.text('1. Gentle'), warnIfMissed: false);
      await tester.pump();
      expect(controller.primaryCalls, 1);
      expect(rowCalls, 0);
      expect(_button(tester).busy, isTrue);

      // The control: the start's own end frees it, and the row that was
      // ignored above now answers.
      controller.finishPrimary();
      await tester.pump();
      await tester.pump();
      expect(_button(tester).busy, isFalse);
      await tester.tap(find.text('1. Gentle'));
      await tester.pump();
      expect(rowCalls, 1);
    });

    testWidgets('coming back tells the game to re-read', (tester) async {
      final controller = _FakeController(
        const GameLandingState(status: GameLandingStatus.fresh),
      );
      controller.primaryBody = (context) async {
        unawaited(context.pushNamed('gamesHub'));
        controller.finishPrimary();
      };
      await _pumpPage(
        tester,
        gameType: 'demo',
        games: [demoGame(controller: controller)],
      );
      // The control: nothing has covered the page yet.
      expect(controller.resumeCalls, 0);

      await tester.tap(find.byType(GamePrimaryButton));
      await _settleRoute(tester);
      expect(find.text('opened:gamesHub:'), findsOneWidget);
      expect(controller.resumeCalls, 0, reason: 'covered, not back yet');
      await tester.tap(find.byType(BackButton));
      await _settleRoute(tester);
      expect(controller.resumeCalls, 1);

      // A sheet over the page counts as covering it too.
      await tester.tap(find.bySemanticsLabel('How to play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(controller.resumeCalls, 2);
    });

    testWidgets('re-reading happens after the frame, not while building', (
      tester,
    ) async {
      // A real re-read writes to or invalidates a provider, which throws
      // if done while the tree is building.
      final controller = _FakeController(
        const GameLandingState(status: GameLandingStatus.fresh),
      );
      controller.primaryBody = (context) async {
        unawaited(context.pushNamed('gamesHub'));
        controller.finishPrimary();
      };
      controller.resumeBody = (ref) => ref.read(_reReads.notifier).state++;
      await _pumpPage(
        tester,
        gameType: 'demo',
        games: [demoGame(controller: controller)],
      );

      await tester.tap(find.byType(GamePrimaryButton));
      await _settleRoute(tester);
      await tester.tap(find.byType(BackButton));
      await _settleRoute(tester);

      expect(tester.takeException(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GameLandingPage)),
      );
      expect(container.read(_reReads), 1);
    });
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
