import 'package:attune/features/games/constellation/prototype/constellation_prototype_screen.dart';
import 'package:attune/features/games/constellation/prototype/constellation_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendered AND looked at. §4.4c says the art is the unmeasured budget,
/// and the only way to measure it is to assemble a finished picture and
/// see whether it reads as something two people made.
void main() {
  /// Halts the completion animation so it does not tick into the next
  /// test. Without this, three of four tests failed when run together
  /// while every one passed alone.
  void debugStopBloom(WidgetTester tester) {
    final state = tester.state<State<ConstellationPrototypeScreen>>(
      find.byType(ConstellationPrototypeScreen),
    );
    // ignore: avoid_dynamic_calls
    (state as dynamic).debugStopAnimations();
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

  testWidgets('the scene matches what the validator checked', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ConstellationPrototypeScreen()),
    );
    await tester.pumpAndSettle();

    final state = tester.state<State<ConstellationPrototypeScreen>>(
      find.byType(ConstellationPrototypeScreen),
    );
    // ignore: avoid_dynamic_calls
    final session = (state as dynamic).debugSession as SessionState;

    expect(session.scene.stars, hasLength(25));
    expect(session.scene.states, hasLength(25));
    expect(session.scene.depth, 12);
    for (final s in session.scene.states.values) {
      expect(s.choices.length, anyOf(0, 2, 3), reason: 'state ${s.id}');
    }
  });
}
