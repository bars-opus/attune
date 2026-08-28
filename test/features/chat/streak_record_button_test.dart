import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the ring shows segment progress while recording',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakRecordButton(
          progress: 0.5,
          isRecording: true,
          onPressStart: () {},
          onPressEnd: () {},
        ),
      ),
    ));

    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, 0.5);
  });

  testWidgets('no ring when idle', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakRecordButton(
          progress: 0,
          isRecording: false,
          onPressStart: () {},
          onPressEnd: () {},
        ),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('press and release both fire on a tap with no movement',
      (tester) async {
    var started = false;
    var ended = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakRecordButton(
          progress: 0,
          isRecording: false,
          onPressStart: () => started = true,
          onPressEnd: () => ended = true,
        ),
      ),
    ));

    // Pointer events, not pan callbacks: onPanEnd never fires for a press
    // with no movement, which is the bug fixed in 511f4665 — a quick tap
    // started a recording that never stopped.
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(started, isTrue);

    await gesture.up();
    await tester.pump();
    expect(ended, isTrue, reason: 'a tap with no drag must still release');
  });
}
