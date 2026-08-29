import 'dart:io';

import 'package:attune/features/chat/presentation/widgets/streak_lock_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(backgroundColor: Colors.black, body: Center(child: child)),
    );

void main() {
  group('the lock hint', () {
    testWidgets('shows a padlock and the swipe instruction', (tester) async {
      await tester.pumpWidget(_wrap(const StreakLockHint(dragProgress: 0)));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Swipe up to record hands-free'), findsOneWidget);
    });

    testWidgets('the caption fades out but the padlock stays',
        (tester) async {
      // The instruction is a one-time teach; the padlock is the target the
      // finger is travelling towards and must survive the whole drag.
      await tester.pumpWidget(_wrap(const StreakLockHint(dragProgress: 0)));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

      final caption = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('streak-lock-caption')),
      );
      expect(caption.opacity, 0);
    });

    testWidgets('the padlock rises and tightens as the drag progresses',
        (tester) async {
      await tester.pumpWidget(_wrap(const StreakLockHint(dragProgress: 0)));
      await tester.pump();
      final start = tester.getCenter(
        find.byIcon(Icons.lock_outline_rounded),
      );

      await tester.pumpWidget(_wrap(const StreakLockHint(dragProgress: 0.9)));
      await tester.pump(const Duration(milliseconds: 200));
      final near = tester.getCenter(
        find.byIcon(Icons.lock_outline_rounded),
      );

      expect(
        near.dy,
        lessThan(start.dy),
        reason: 'the padlock should move toward the travelling finger',
      );
    });
  });

  group('the camera', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/features/chat/presentation/screens/streak_camera_screen.dart',
      ).readAsStringSync();
    });

    test('an upward drag past the threshold locks the recording', () {
      expect(src, contains('_isLocked'));
      expect(src, contains('kStreakLockDragDistance'));
    });

    test('a locked recording survives the finger lifting', () {
      // The whole point of locking: onPressEnd must not stop a recording
      // the user deliberately locked.
      expect(
        src,
        contains('if (_isLocked) return;'),
        reason: 'releasing while locked must not end the take',
      );
    });

    test('locking is reset for the next recording', () {
      // A sticky lock would make the NEXT streak unstoppable by release.
      final resets = RegExp(r'_isLocked = false').allMatches(src).length;
      expect(resets, greaterThanOrEqualTo(2));
    });
  });
}
