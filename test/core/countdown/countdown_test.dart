import 'package:attune/core/utils/countdown/countdown.dart';
import 'package:attune/core/widgets/app_countdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendar days', () {
    test('count whole calendar days, ignoring the time of day', () {
      expect(calendarDaysBetween(DateTime(2026, 10, 12, 23, 59), DateTime(2026, 10, 13, 0, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 12, 0, 1), DateTime(2026, 10, 12, 23, 59)), 0);
      expect(calendarDaysBetween(DateTime(2026, 10, 13), DateTime(2026, 10, 12)), -1);
    });

    test('daylight saving and leap years do not shift the count', () {
      // 23- and 25-hour days (US and EU clock changes) still count as one day each.
      expect(calendarDaysBetween(DateTime(2026, 3, 7, 12), DateTime(2026, 3, 9, 12)), 2);
      expect(calendarDaysBetween(DateTime(2026, 10, 24, 12), DateTime(2026, 10, 26, 12)), 2);
      expect(calendarDaysBetween(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2);
    });
  });

  group('a date or a range', () {
    final now = DateTime(2026, 10, 12, 15, 30);
    String label(DateTime start, [DateTime? end]) => Countdown.toDate(start: start, end: end, now: now).label;

    test('single dates', () {
      expect(label(DateTime(2026, 10, 12)), 'Today');
      expect(label(DateTime(2026, 10, 13)), 'Tomorrow');
      expect(label(DateTime(2026, 10, 24)), 'In 12 days');
      expect(label(DateTime(2026, 10, 11)), 'Yesterday');
      expect(label(DateTime(2026, 10, 9)), '3 days ago');
    });

    test('ranges: before, during, on the last day, after', () {
      expect(label(DateTime(2026, 10, 17), DateTime(2026, 10, 21)), 'In 5 days');
      expect(label(DateTime(2026, 10, 11), DateTime(2026, 10, 15)), 'Day 2 of 5');
      expect(label(DateTime(2026, 10, 8), DateTime(2026, 10, 12)), 'Day 5 of 5');
      expect(label(DateTime(2026, 10, 5), DateTime(2026, 10, 11)), 'Ended yesterday');
      expect(label(DateTime(2026, 10, 1), DateTime(2026, 10, 9)), 'Ended 3 days ago');
    });

    test('phases', () {
      expect(Countdown.toDate(start: DateTime(2026, 10, 20), now: now).phase, CountdownPhase.upcoming);
      expect(Countdown.toDate(start: DateTime(2026, 10, 12), now: now).phase, CountdownPhase.current);
      expect(Countdown.toDate(start: DateTime(2026, 10, 1), now: now).phase, CountdownPhase.past);
    });

    test('a range ending before it starts is treated as a single date', () {
      expect(label(DateTime(2026, 10, 20), DateTime(2026, 10, 18)), 'In 8 days');
    });
  });

  group('a moment', () {
    final now = DateTime(2026, 10, 12, 15, 30, 0);
    String label(Duration d) => Countdown.toMoment(target: now.add(d), now: now).label;

    test('counts down in the two largest units', () {
      expect(label(const Duration(days: 2, hours: 4, minutes: 9)), 'In 2d 4h');
      expect(label(const Duration(hours: 4, minutes: 10, seconds: 3)), 'In 4h 10m');
      expect(label(const Duration(minutes: 10, seconds: 5)), 'In 10m 5s');
      expect(label(const Duration(seconds: 5)), 'In 5s');
      expect(label(Duration.zero), 'Now');
      expect(label(const Duration(hours: -3, minutes: -2)), '3h 2m ago');
    });
  });

  group('AppCountdown', () {
    testWidgets('turns over at local midnight without a rebuild from outside', (tester) async {
      var now = DateTime(2026, 10, 12, 23, 59, 50);
      await tester.pumpWidget(MaterialApp(
        home: AppCountdown.toDate(start: DateTime(2026, 10, 13), clock: () => now),
      ));
      expect(find.text('Tomorrow'), findsOneWidget);
      now = DateTime(2026, 10, 13, 0, 0, 1);
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('catches up when the app comes back from the background', (tester) async {
      var now = DateTime(2026, 10, 12, 9);
      await tester.pumpWidget(MaterialApp(
        home: AppCountdown.toDate(start: DateTime(2026, 10, 14), clock: () => now),
      ));
      expect(find.text('In 2 days'), findsOneWidget);
      now = DateTime(2026, 10, 13, 9); // a day passed while the app was asleep
      // Background and back, through the states a real app passes through.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(find.text('Tomorrow'), findsOneWidget);
    });

    testWidgets('a moment ticks every second near the end', (tester) async {
      final start = DateTime(2026, 10, 12, 15, 30);
      var now = start;
      await tester.pumpWidget(MaterialApp(
        home: AppCountdown.toMoment(target: start.add(const Duration(seconds: 10)), clock: () => now),
      ));
      expect(find.text('In 10s'), findsOneWidget);
      now = start.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('In 7s'), findsOneWidget);
    });

    testWidgets('screen readers hear a full sentence; a builder can draw it any way', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: AppCountdown.toDate(
          start: DateTime(2026, 10, 24),
          clock: () => DateTime(2026, 10, 12),
          builder: (context, snapshot) => Text('${snapshot.days}!'),
        ),
      ));
      expect(find.text('12!'), findsOneWidget);
      expect(find.bySemanticsLabel('In 12 days'), findsOneWidget);
      handle.dispose();
    });
  });
}
