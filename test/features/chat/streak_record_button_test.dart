import 'dart:io';

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

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(started, isTrue);

    await gesture.up();
    await tester.pump();
    expect(ended, isTrue, reason: 'a tap with no drag must still release');
  });

  test('the button is driven by pointer events, not pan callbacks', () {
    // A behavioural test cannot pin this: flutter_test's synthetic
    // gestures DO deliver onPanEnd for a movement-free tap, where a real
    // device's arena does not. Swapping to pan therefore passes every
    // widget test and fails in the user's hand -- which is precisely how
    // 511f4665 shipped, leaving the recorder running after a quick tap.
    //
    // So this asserts the mechanism directly.
    final src = File(
      'lib/features/chat/presentation/widgets/streak_record_button.dart',
    ).readAsStringSync();

    expect(src, contains('onPointerDown'));
    expect(src, contains('onPointerUp'));
    expect(
      src,
      isNot(contains('onPanEnd')),
      reason: 'pan does not report an end for a press with no movement',
    );
  });
}
