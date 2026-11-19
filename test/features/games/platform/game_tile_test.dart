import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A tap that lands on nothing fails, rather than only printing a warning.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);

  const face = ValueKey('game-tile-face');

  // What sits ON the face. A press is measured here, not on the face's own
  // box: the face moves its contents with a transform, so its box stays
  // put and would report "no movement" whether the tile pressed or not.
  const content = ValueKey('content');
  const piece = SizedBox.square(key: content, dimension: 60);

  Widget host(Widget tile, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: tile)),
    ),
  );

  testWidgets('a press moves the face down onto its shadow', (tester) async {
    // The whole point of the tile: a tap reads as pushing a real key.
    await tester.pumpWidget(
      host(GameTile(depth: 10, onTap: () {}, child: piece)),
    );

    final rest = tester.getTopLeft(find.byKey(content));
    final sizeAtRest = tester.getSize(find.byType(GameTile));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(content)),
    );
    await tester.pump();
    await tester.pump(GameMotion.press);

    final pressed = tester.getTopLeft(find.byKey(content));
    expect(pressed.dy - rest.dy, closeTo(10, 0.01));
    expect(pressed.dx - rest.dx, closeTo(10 * GameTile.lean, 0.01));

    // The tile's own box must not change, or everything beside it would
    // jump each time it is pressed.
    expect(tester.getSize(find.byType(GameTile)), sizeAtRest);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(content)), rest);
  });

  testWidgets('a tap is reported', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        GameTile(
          onTap: () => taps++,
          child: const SizedBox.square(dimension: 60),
        ),
      ),
    );

    await tester.tap(find.byType(GameTile));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('a still tile does not press and is not a button', (
    tester,
  ) async {
    // Hero art and board cells that cannot be chosen are tiles too. They
    // must not answer a finger or be announced as something to press.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const GameTile(child: piece)));

    final rest = tester.getTopLeft(find.byKey(content));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(content)),
    );
    await tester.pump();
    await tester.pump(GameMotion.press);

    // The control is the test above, where the same measurement moves.
    expect(tester.getTopLeft(find.byKey(content)), rest);
    expect(
      tester
          .getSemantics(find.byType(GameTile))
          .hasFlag(SemanticsFlag.isButton),
      isFalse,
    );

    await gesture.up();
    handle.dispose();
  });

  testWidgets('a pressable tile is announced as a button, with its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        GameTile(
          onTap: () {},
          semanticLabel: 'Night in',
          selected: true,
          child: const Text('🛋️'),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(GameTile));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(node.label, 'Night in');

    handle.dispose();
  });

  testWidgets('reduce motion makes the press immediate', (tester) async {
    Duration durationOf() =>
        tester.widget<AnimatedContainer>(find.byKey(face)).duration;

    await tester.pumpWidget(
      host(GameTile(onTap: () {}, child: const SizedBox.square(dimension: 60))),
    );
    // The control: it does animate when motion is allowed.
    expect(durationOf(), GameMotion.press);

    await tester.pumpWidget(
      host(
        GameTile(onTap: () {}, child: const SizedBox.square(dimension: 60)),
        reduceMotion: true,
      ),
    );
    expect(durationOf(), Duration.zero);
  });
}
