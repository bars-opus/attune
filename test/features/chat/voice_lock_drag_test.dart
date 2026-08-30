import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an upward drag past the threshold is reachable from a small '
      'target', (tester) async {
    // Reproduces the composer: a 48px mic with a Listener on it, dragged
    // 120px upward — well outside its own bounds. If Flutter stops
    // routing moves to the widget the pointer went down on, the lock can
    // never be reached however far the finger travels.
    var travelled = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Listener(
              onPointerMove: (e) => travelled -= e.delta.dy,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox)),
    );
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await gesture.up();

    expect(
      travelled,
      greaterThanOrEqualTo(100),
      reason:
          'pointer moves must keep reaching the widget the gesture '
          'started on, even once the finger leaves its bounds',
    );
  });

  testWidgets('the pill reports full progress at the threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: VoiceLockPill(dragProgress: 1))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final chevron = tester.widget<Opacity>(
      find.byKey(const ValueKey('voice-lock-chevron')),
    );
    expect(chevron.opacity, 0);
  });
}
