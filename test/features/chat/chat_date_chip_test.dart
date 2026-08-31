import 'package:attune/features/chat/presentation/widgets/chat_date_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('the label', () {
    final now = DateTime(2026, 10, 12, 14, 30);

    test('today and yesterday are named, not dated', () {
      expect(chatDateLabel(DateTime(2026, 10, 12, 9), now: now), 'Today');
      expect(chatDateLabel(DateTime(2026, 10, 11, 23), now: now), 'Yesterday');
    });

    test('inside the last week it reads as a weekday', () {
      // Telegram shows the weekday for recent days — more useful than a
      // date for something you probably remember.
      expect(chatDateLabel(DateTime(2026, 10, 8), now: now), 'Thursday');
    });

    test('older than a week reads as a date, and gains a year once past it', () {
      expect(chatDateLabel(DateTime(2026, 9, 3), now: now), '3 September');
      expect(chatDateLabel(DateTime(2025, 9, 3), now: now), '3 September 2025');
    });

    test('a date is judged by its local day, not by elapsed hours', () {
      // 23:59 yesterday is 31 minutes before `now`, but it is still
      // Yesterday — an elapsed-hours comparison would call it Today.
      expect(
        chatDateLabel(DateTime(2026, 10, 11, 23, 59), now: now),
        'Yesterday',
      );
    });
  });

  testWidgets('renders its label in a pill', (tester) async {
    await tester.pumpWidget(_wrap(const ChatDateChip(label: '12 October')));
    expect(find.text('12 October'), findsOneWidget);
  });

  testWidgets('opacity 0 keeps it laid out but invisible', (tester) async {
    // The floating chip fades rather than unmounting, so its position does
    // not jump when it comes back.
    await tester.pumpWidget(
      _wrap(const ChatDateChip(label: '12 October', opacity: 0)),
    );
    expect(find.text('12 October'), findsOneWidget);

    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text('12 October'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 0);
  });
}
