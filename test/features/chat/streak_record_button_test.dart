import 'dart:io';

import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _primary = Color(0xFF2E7D5B);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(primary: _primary),
      ),
      home: Scaffold(backgroundColor: Colors.black, body: Center(child: child)),
    );

void main() {
  group('idle — a hollow ring, ready to record', () {
    testWidgets('draws a ring outline and no fill', (tester) async {
      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0,
        isRecording: false,
        onPressStart: () {},
        onPressEnd: () {},
      )));

      final ring = tester.widget<Container>(
        find.byKey(const ValueKey('streak-record-ring')),
      );
      final decoration = ring.decoration! as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.color,
        anyOf(isNull, Colors.transparent),
        reason: 'idle is an outline, not a filled disc',
      );
      expect(decoration.border, isNotNull);
    });

    testWidgets('shows no progress arc when idle', (tester) async {
      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0,
        isRecording: false,
        onPressStart: () {},
        onPressEnd: () {},
      )));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('recording — a filled disc with a progress arc', () {
    testWidgets('fills with the app primary, never a hardcoded colour',
        (tester) async {
      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0.4,
        isRecording: true,
        onPressStart: () {},
        onPressEnd: () {},
      )));

      final fill = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('streak-record-fill')),
      );
      final decoration = fill.decoration! as BoxDecoration;

      expect(
        decoration.color,
        _primary,
        reason: 'the reference is Snapchat yellow; ours must be the app '
            'primary so it stays on-brand in both themes',
      );
    });

    testWidgets('the arc tracks segment progress', (tester) async {
      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0.4,
        isRecording: true,
        onPressStart: () {},
        onPressEnd: () {},
      )));

      final arc = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(arc.value, 0.4);
      expect(
        arc.strokeWidth,
        greaterThanOrEqualTo(8),
        reason: 'the reference arc is thick and readable at a glance, not '
            'a hairline',
      );
    });

    testWidgets('the fill grows when recording starts', (tester) async {
      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0,
        isRecording: false,
        onPressStart: () {},
        onPressEnd: () {},
      )));
      final idle = tester.getSize(
        find.byKey(const ValueKey('streak-record-ring')),
      );

      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0.1,
        isRecording: true,
        onPressStart: () {},
        onPressEnd: () {},
      )));
      await tester.pump(const Duration(milliseconds: 300));
      final active = tester.getSize(
        find.byKey(const ValueKey('streak-record-fill')),
      );

      expect(
        active.width,
        greaterThan(idle.width),
        reason: 'the recording disc reads as larger than the idle ring',
      );
    });
  });

  testWidgets('press and release both fire on a tap with no movement',
      (tester) async {
    var started = false;
    var ended = false;
    await tester.pumpWidget(_wrap(StreakRecordButton(
      progress: 0,
      isRecording: false,
      onPressStart: () => started = true,
      onPressEnd: () => ended = true,
    )));

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
    // widget test and fails in the user's hand — which is precisely how
    // 511f4665 shipped, leaving the recorder running after a quick tap.
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
