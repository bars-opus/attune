import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  final target = GlobalKey();

  List<GameCoachStep> steps() => [
    const GameCoachStep(text: 'Welcome to the game.'),
    GameCoachStep(text: 'Tap this tile.', target: target),
    const GameCoachStep(text: 'That is all there is to it.'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    List<GameCoachStep>? withSteps,
    bool force = false,
    VoidCallback? onDone,
    VoidCallback? onTargetTap,
    double textScale = 1,
    Size surface = phone,
  }) async {
    useSurface(tester, surface);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: GameCoach(
            gameType: 'demo',
            steps: withSteps ?? steps(),
            force: force,
            onDone: onDone,
            child: Align(
              alignment: const Alignment(0, 0.8),
              child: GestureDetector(
                onTap: onTargetTap,
                child: SizedBox(
                  key: target,
                  width: 64,
                  height: 64,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        prefs: await testPrefs(stored),
        textScale: textScale,
      ),
    );
    // One frame to build, one for the post-frame measurement to land.
    await tester.pump();
    await tester.pump();
  }

  bool seen(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(GameCoach)),
  ).read(gameCoachStoreProvider).seen('demo');

  testWidgets('a first-time player is shown the first step', (tester) async {
    await pump(tester);

    expect(find.text('Welcome to the game.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('Next walks through to the last step, which has no Skip', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Tap this tile.'), findsOneWidget);
    expect(find.text('Welcome to the game.'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('That is all there is to it.'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('Got it closes the tutorial and remembers it was seen', (
    tester,
  ) async {
    var done = 0;
    await pump(tester, onDone: () => done++);
    expect(seen(tester), isFalse);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Got it'));
    await tester.pump();

    expect(find.byType(GameCoachBubble), findsNothing);
    expect(done, 1);
    expect(seen(tester), isTrue);
  });

  testWidgets('Skip closes it at once, and it still counts as seen', (
    tester,
  ) async {
    var done = 0;
    await pump(tester, onDone: () => done++);

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(find.byType(GameCoachBubble), findsNothing);
    expect(done, 1);
    expect(seen(tester), isTrue);
  });

  testWidgets('a player who has seen it is not shown it again', (tester) async {
    // The control is the first test: the same pump without the stored flag
    // does show the bubble.
    await pump(tester, stored: {GameCoachStore.key('demo'): true});

    expect(find.byType(GameCoachBubble), findsNothing);
  });

  testWidgets('seeing one game\'s tutorial does not hide another\'s', (
    tester,
  ) async {
    await pump(tester, stored: {GameCoachStore.key('another_game'): true});

    expect(find.byType(GameCoachBubble), findsOneWidget);
  });

  testWidgets('asking for it replays it even when seen', (tester) async {
    await pump(tester, stored: {GameCoachStore.key('demo'): true}, force: true);

    expect(find.text('Welcome to the game.'), findsOneWidget);
  });

  testWidgets('asking again replays it from the first step', (tester) async {
    useSurface(tester, phone);
    final prefs = await testPrefs({GameCoachStore.key('demo'): true});
    Widget host(int replay) => gameHost(
      Scaffold(
        body: GameCoach(
          gameType: 'demo',
          steps: steps(),
          replay: replay,
          child: const SizedBox.expand(),
        ),
      ),
      prefs: prefs,
    );

    await tester.pumpWidget(host(0));
    await tester.pump();
    expect(find.byType(GameCoachBubble), findsNothing, reason: 'seen');

    await tester.pumpWidget(host(1));
    await tester.pump();
    expect(find.text('Welcome to the game.'), findsOneWidget);

    // Replay neither needs nor clears the flag: skipping leaves it set.
    expect(seen(tester), isTrue);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.byType(GameCoachBubble), findsNothing);
    expect(seen(tester), isTrue);
  });

  testWidgets('fewer steps on a rebuild does not throw', (tester) async {
    useSurface(tester, phone);
    final prefs = await testPrefs();
    Widget host(List<GameCoachStep> withSteps) => gameHost(
      Scaffold(
        body: GameCoach(
          gameType: 'demo',
          steps: withSteps,
          child: Align(
            alignment: const Alignment(0, 0.8),
            child: SizedBox(key: target, width: 64, height: 64),
          ),
        ),
      ),
      prefs: prefs,
    );

    await tester.pumpWidget(host(steps()));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('That is all there is to it.'), findsOneWidget);

    await tester.pumpWidget(
      host(const [GameCoachStep(text: 'Just the one step.')]),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Just the one step.'), findsOneWidget);
  });

  testWidgets('a game with no steps shows nothing', (tester) async {
    await pump(tester, withSteps: const []);

    expect(find.byType(GameCoachBubble), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a step with a target rings exactly that target', (tester) async {
    await pump(tester);
    expect(
      find.byKey(const ValueKey('game-coach-ring')),
      findsNothing,
      reason: 'the first step points at nothing',
    );

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();

    final ring = tester.getRect(find.byKey(const ValueKey('game-coach-ring')));
    final tile = tester.getRect(find.byKey(target));
    expect(ring, tile.inflate(5));
  });

  testWidgets('it can point at something outside the area it wraps', (
    tester,
  ) async {
    // A tutorial around the board pointing at a button in the bar below.
    useSurface(tester, phone);
    final outside = GlobalKey();
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Column(
            children: [
              Expanded(
                child: GameCoach(
                  gameType: 'demo',
                  steps: [
                    GameCoachStep(text: 'Stuck? Try this.', target: outside),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(key: outside, width: 48, height: 48),
              ),
            ],
          ),
        ),
        prefs: await testPrefs(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final ring = tester.getRect(find.byKey(const ValueKey('game-coach-ring')));
    expect(ring, tester.getRect(find.byKey(outside)).inflate(5));
  });

  testWidgets('the ring is placed from where the tutorial itself sits', (
    tester,
  ) async {
    // In a real game the tutorial wraps the body, under a header -- not
    // the top-left corner of the screen, where every other test here puts
    // it and where getting this wrong would not show.
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(30, 90, 0, 0),
            child: GameCoach(
              gameType: 'demo',
              steps: [GameCoachStep(text: 'Tap this tile.', target: target)],
              child: Align(
                alignment: const Alignment(0, 0.8),
                child: SizedBox(key: target, width: 64, height: 64),
              ),
            ),
          ),
        ),
        prefs: await testPrefs(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final ring = tester.getRect(find.byKey(const ValueKey('game-coach-ring')));
    expect(ring, tester.getRect(find.byKey(target)).inflate(5));
  });

  testWidgets('the ring follows its target when the game scrolls', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: GameCoach(
            gameType: 'demo',
            steps: [GameCoachStep(text: 'Tap this tile.', target: target)],
            child: ListView(
              children: [
                const SizedBox(height: 420),
                Center(child: SizedBox(key: target, width: 64, height: 64)),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
        prefs: await testPrefs(),
      ),
    );
    await tester.pump();
    await tester.pump();
    final before = tester.getRect(find.byKey(target));
    expect(
      tester.getRect(find.byKey(const ValueKey('game-coach-ring'))),
      before.inflate(5),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pump();
    await tester.pump();

    final after = tester.getRect(find.byKey(target));
    expect(after.top, lessThan(before.top), reason: 'the target did move');
    expect(
      tester.getRect(find.byKey(const ValueKey('game-coach-ring'))),
      after.inflate(5),
    );
  });

  testWidgets('on a small phone at the largest text, Next and Skip can '
      'still be reached', (tester) async {
    // A long step at twice the text size is taller than a small screen.
    // The words scroll; the two buttons stay where a finger can get them.
    // (A missed tap fails the test, so the taps below are the assertion.)
    const long =
        'Each round you both answer the same question without seeing the '
        'other answer. When you have both answered, the two answers turn '
        'over together and you can talk about where you differed.';
    await pump(
      tester,
      surface: const Size(320, 568),
      textScale: 2,
      withSteps: const [
        GameCoachStep(text: long),
        GameCoachStep(text: long),
        GameCoachStep(text: 'Done.'),
      ],
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(find.byType(GameCoachBubble), findsNothing);
  });

  testWidgets('Skip can be activated by a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    var done = 0;
    await pump(tester, onDone: () => done++);

    final node = tester.getSemantics(find.bySemanticsLabel('Skip'));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();

    expect(done, 1);
    expect(find.byType(GameCoachBubble), findsNothing);
    handle.dispose();
  });

  testWidgets('the ring goes when the step that needed it is over', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('game-coach-ring')), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('game-coach-ring')), findsNothing);
  });

  testWidgets('the game underneath still takes touches through the ring', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, onTargetTap: () => taps++);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('game-coach-ring')), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byKey(target)));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('the largest text size does not overflow the bubble', (
    tester,
  ) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('Welcome to the game.'), findsOneWidget);
  });
}
