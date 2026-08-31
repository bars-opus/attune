import 'package:attune/features/chat/presentation/widgets/chat_date_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme, home: Scaffold(body: Center(child: child)));

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

    test(
      'older than a week reads as a date, and gains a year once past it',
      () {
        expect(chatDateLabel(DateTime(2026, 9, 3), now: now), '3 September');
        expect(
          chatDateLabel(DateTime(2025, 9, 3), now: now),
          '3 September 2025',
        );
      },
    );

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

  testWidgets('uses the inverse background pair in light and dark themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final theme = ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: brightness,
        ),
      );
      await tester.pumpWidget(
        _wrap(const ChatDateChip(label: '12 October'), theme: theme),
      );

      final context = tester.element(find.byType(ChatDateChip));
      final colorScheme = Theme.of(context).colorScheme;
      final chip = tester.widget<Container>(
        find.byKey(const ValueKey('chat-date-chip')),
      );
      final decoration = chip.decoration! as BoxDecoration;
      final label = tester.widget<Text>(find.text('12 October'));

      // ignore: deprecated_member_use
      final expectedChipFill = colorScheme.onBackground.withValues(alpha: 0.28);
      // ignore: deprecated_member_use
      final expectedChipText = colorScheme.background;

      expect(decoration.color, expectedChipFill);
      expect(label.style?.color, expectedChipText);
    }
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

  group('the inline separator', () {
    testWidgets('runs a rule to both edges with the date on it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const ChatDateSeparator(label: '12 October')),
      );

      expect(find.text('12 October'), findsOneWidget);

      final rules = find.byKey(const ValueKey('chat-date-rule'));
      expect(
        rules,
        findsNWidgets(2),
        reason: 'one rule each side, so the date sits ON the line',
      );

      final context = tester.element(find.byType(ChatDateSeparator));
      final colorScheme = Theme.of(context).colorScheme;
      // ignore: deprecated_member_use
      final expectedRuleColor = colorScheme.onBackground.withValues(
        alpha: 0.16,
      );
      for (final rule in tester.widgetList<Container>(rules)) {
        expect(rule.constraints?.minHeight, 0.6);
        expect(rule.color, expectedRuleColor);
      }

      // The date sits in the same pill the floating chip uses, so the two
      // read as one component that has simply stuck to the top.
      expect(
        find.descendant(
          of: find.byType(ChatDateSeparator),
          matching: find.byType(ChatDateChip),
        ),
        findsOneWidget,
        reason: 'the rounded container is shared with the pinned chip',
      );

      final labelRect = tester.getRect(find.text('12 October'));
      final left = tester.getRect(rules.first);
      final right = tester.getRect(rules.last);

      expect(left.right, lessThanOrEqualTo(labelRect.left));
      expect(right.left, greaterThanOrEqualTo(labelRect.right));
      expect(
        left.center.dy,
        moreOrLessEquals(labelRect.center.dy, epsilon: 1.5),
        reason: 'the rule cuts through the middle of the date',
      );
    });

    testWidgets('the pinned chip carries no rule', (tester) async {
      // It floats over the messages: a line running to both edges would
      // read as dividing them rather than labelling a scroll position.
      await tester.pumpWidget(_wrap(const ChatDateChip(label: '12 October')));
      expect(find.byKey(const ValueKey('chat-date-rule')), findsNothing);
    });
  });
}
