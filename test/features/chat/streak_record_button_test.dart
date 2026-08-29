import 'dart:io';

import 'package:attune/app/theme/design_tokens.dart';
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

    testWidgets('the arc sits clear of the disc, not on its edge',
        (tester) async {
      await tester.pumpWidget(_wrap(StreakRecordButton(
        progress: 0.4,
        isRecording: true,
        onPressStart: () {},
        onPressEnd: () {},
      )));

      final disc = tester.getSize(
        find.byKey(const ValueKey('streak-record-fill')),
      );
      final arc = tester.getSize(
        find.byKey(const ValueKey('streak-record-arc')),
      );

      // A visible gap on every side, so the arc reads as a ring AROUND
      // the disc rather than a stroke drawn on top of its edge.
      expect(
        (arc.width - disc.width) / 2,
        greaterThanOrEqualTo(Spacing.md),
        reason: 'the padding between disc and arc should be at least md',
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
        greaterThanOrEqualTo(4),
        reason: 'readable at a glance, not a hairline — thinner than the '
            'earlier design because the arc now rings the disc with a gap '
            'rather than sitting on its edge',
      );
    });

    testWidgets('the recording control is larger overall than idle',
        (tester) async {
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
      // The DISC is smaller than the idle ring now that the arc rings it
      // with a gap; what grows is the control as a whole.
      final active = tester.getSize(
        find.byKey(const ValueKey('streak-record-arc')),
      );

      expect(
        active.width,
        greaterThan(idle.width),
        reason: 'recording reads as a larger control than the idle ring',
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

  testWidgets('sending turns the ring into the loading indicator',
      (tester) async {
    await tester.pumpWidget(_wrap(StreakRecordButton(
      progress: 0,
      isRecording: false,
      isSending: true,
      onPressStart: () {},
      onPressEnd: () {},
    )));
    await tester.pump(const Duration(milliseconds: 100));

    // An indeterminate sweep on the button itself — the screen should not
    // also stack a separate spinner somewhere else.
    final arc = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(arc.value, isNull, reason: 'an upload has no known progress');

    expect(find.byType(StreakRecordButton), findsOneWidget);
  });

  testWidgets('a sending button ignores presses', (tester) async {
    var started = false;
    await tester.pumpWidget(_wrap(StreakRecordButton(
      progress: 0,
      isRecording: false,
      isSending: true,
      onPressStart: () => started = true,
      onPressEnd: () {},
    )));

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();

    expect(
      started,
      isFalse,
      reason: 'recording again mid-upload would queue a second send',
    );
  });

  test('pressing fires a light haptic', () {
    // Not observable in a widget test — HapticFeedback goes out over a
    // platform channel with no recorded effect on the tree.
    final src = File(
      'lib/features/chat/presentation/widgets/streak_record_button.dart',
    ).readAsStringSync();
    expect(src, contains('HapticFeedback.lightImpact()'));
  });

  testWidgets('the camera warming up shows in the ring, not a centre spinner',
      (tester) async {
    await tester.pumpWidget(_wrap(StreakRecordButton(
      progress: 0,
      isRecording: false,
      isPreparing: true,
      onPressStart: () {},
      onPressEnd: () {},
    )));
    await tester.pump(const Duration(milliseconds: 100));

    final arc = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(
      arc.value,
      isNull,
      reason: 'camera init has no measurable progress',
    );
    expect(
      arc.valueColor?.value,
      Colors.white,
      reason: 'warming up is neutral; primary is reserved for the send, so '
          'the two waits are told apart at a glance',
    );
  });

  testWidgets('the sending sweep uses the app primary', (tester) async {
    await tester.pumpWidget(_wrap(StreakRecordButton(
      progress: 0,
      isRecording: false,
      isSending: true,
      onPressStart: () {},
      onPressEnd: () {},
    )));
    await tester.pump(const Duration(milliseconds: 100));

    final arc = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(arc.valueColor?.value, _primary);
  });

  testWidgets('a preparing button ignores presses', (tester) async {
    var started = false;
    await tester.pumpWidget(_wrap(StreakRecordButton(
      progress: 0,
      isRecording: false,
      isPreparing: true,
      onPressStart: () => started = true,
      onPressEnd: () {},
    )));

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();

    expect(
      started,
      isFalse,
      reason: 'there is no camera to record from yet',
    );
  });

  test('the camera screen has no centre spinner of its own', () {
    // The ring is the only loading affordance: a spinner in the middle of
    // a black screen says nothing the ring cannot, and reads as a broken
    // launch rather than a camera warming up.
    final src = File(
      'lib/features/chat/presentation/screens/streak_camera_screen.dart',
    ).readAsStringSync();
    expect(
      src,
      isNot(contains('Center(child: CircularProgressIndicator())')),
      reason: 'loading belongs on the button, not the screen',
    );
  });
}
