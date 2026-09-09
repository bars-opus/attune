import 'package:attune/features/games/constellation/prototype/constellation_prototype_screen.dart';
import 'package:attune/features/games/constellation/prototype/constellation_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// SCENE RENDERER — a tool, not a test in the suite.
///
/// Lives under tool/ deliberately: `flutter test` does not pick it up,
/// because these must be run ONE AT A TIME. The completion animation's
/// controller outlives its test and interferes with the next one's pump,
/// and chasing that down is not worth it in a build whose whole purpose
/// is to be looked at once and thrown away.
///
/// Run:
///   flutter test tool/constellation/render_goldens_test.dart \
///     --plain-name "both partners" --update-goldens
///
/// Then open the PNG. The point is to LOOK at the assembled picture, not
/// to diff it -- §4.4d's finding about star layout came from doing
/// exactly that.
///
/// The completion bloom keeps ticking after a test ends, and run
/// alongside other tests it made three of four fail while each
/// passed alone. Splitting the rendering tests out is cheaper than
/// fighting animation lifetimes in a throwaway build.
///
/// Rendered AND looked at. §4.4c says the art is the unmeasured budget,
/// and the only way to measure it is to assemble a finished picture and
/// see whether it reads as something two people made.
void main() {
  /// Halts the completion animation so it does not tick into the next
  /// test. Without this, three of four tests failed when run together
  /// while every one passed alone.
  void debugFinishBloom(WidgetTester tester) {
    final state = tester.state<State<ConstellationPrototypeScreen>>(
      find.byType(ConstellationPrototypeScreen),
    );
    // ignore: avoid_dynamic_calls
    (state as dynamic).debugFinishAnimations();
  }

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    // Reset BOTH, and do it in teardown rather than relying on the next
    // test to overwrite: run together, these tests leaked view state and
    // three of four failed while each passed alone.
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// Taps through a whole scene by aiming at a chosen branch index.
  ///
  /// Driven through the UI rather than the model, because the point is
  /// to check the assembled PICTURE, and that only exists once the
  /// screen has actually painted every move.
  Future<void> playOut(WidgetTester tester, int Function(int) branchFor) async {
    for (var turn = 0; turn < 40; turn++) {
      if (find.text('You made this together.').evaluate().isNotEmpty) return;

      // The board's CustomPaint is the SQUARE one. Using .last picks up
      // the AppBar's, which is why the first version of this test tapped
      // into the toolbar and never landed a move.
      final board = tester.getRect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.size.width > 100 &&
              w.size.width == w.size.height,
        ),
      );
      final state = tester.state<State<ConstellationPrototypeScreen>>(
        find.byType(ConstellationPrototypeScreen),
      );
      // ignore: avoid_dynamic_calls
      final session = (state as dynamic).debugSession as SessionState?;
      if (session == null || session.isComplete) return;

      final pick = branchFor(turn) % session.offered.length;
      final star = session.scene.stars[session.offered[pick].toStar]!;
      final at =
          board.topLeft + Offset(star.x * board.width, star.y * board.height);

      await tester.tapAt(at);
      await tester.pump();
    }
  }

  testWidgets('the empty field', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ConstellationPrototypeScreen()),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(ConstellationPrototypeScreen),
      matchesGoldenFile(
        '../../test/features/games/goldens/constellation_empty.png',
      ),
    );
  });

  testWidgets('a finished pattern, both partners contributing', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ConstellationPrototypeScreen()),
    );
    await tester.pumpAndSettle();

    await playOut(tester, (turn) => turn % 2);
    // Pump past the bloom rather than pumpAndSettle: the completion
    // animation runs for 2.6s and pumpAndSettle never returns while it
    // does. Then stop it, or it keeps ticking into the next test.
    // Jump the completion animation to its end rather than running it:
    // a ticking controller leaks across tests, and what these goldens are
    // for is the FINISHED PICTURE. The bloom's sequencing is a device
    // check, not a golden.
    debugFinishBloom(tester);
    await tester.pump();

    expect(find.text('You made this together.'), findsOneWidget);
    await expectLater(
      find.byType(ConstellationPrototypeScreen),
      matchesGoldenFile(
        '../../test/features/games/goldens/constellation_complete.png',
      ),
    );
  });

  testWidgets('the same scene played the other way looks different', (
    tester,
  ) async {
    // THE QUESTION THE WHOLE DESIGN RESTS ON (§4.2): do different routes
    // through one scene produce visibly different pictures, or is this a
    // progress bar with stars on it?
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ConstellationPrototypeScreen()),
    );
    await tester.pumpAndSettle();

    await playOut(tester, (turn) => 0);
    // Jump the completion animation to its end rather than running it:
    // a ticking controller leaks across tests, and what these goldens are
    // for is the FINISHED PICTURE. The bloom's sequencing is a device
    // check, not a golden.
    debugFinishBloom(tester);
    await tester.pump();

    expect(find.text('You made this together.'), findsOneWidget);
    await expectLater(
      find.byType(ConstellationPrototypeScreen),
      matchesGoldenFile(
        '../../test/features/games/goldens/constellation_other_route.png',
      ),
    );
  });
}
