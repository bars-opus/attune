import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/linkified_message_text.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// 05 M-6: every drag delta rebuilt the whole bubble subtree of every
/// visible row. The offset now reaches the bubble as a ValueListenable and
/// only the shell (UniversalBubble + reveal column) rebuilds.
void main() {
  Message partner(String content) => Message(
    id: 'm-$content',
    clientMessageId: 'c-$content',
    relationshipId: 'r1',
    senderId: 'partner',
    content: content,
    createdAt: DateTime(2026, 7, 1, 15, 5),
    status: MessageStatus.delivered,
    isMine: false,
  );

  testWidgets('reveal ticks move the shell but do not rebuild content', (
    tester,
  ) async {
    final reveal = ValueNotifier<double>(0);
    addTearDown(reveal.dispose);
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(
                  message: partner('hello'),
                  timestampRevealListenable: reveal,
                ),
                MessageBubble(
                  message: partner('there'),
                  timestampRevealListenable: reveal,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    reveal.value = 30;
    await tester.pump();
    reveal.value = 45;
    await tester.pump();

    // Task 4 turned the body text into LinkifiedMessageText (a Text.rich,
    // so `Text.data` is null) — assert on the body widget itself.
    expect(
      rebuilt.whereType<LinkifiedMessageText>(),
      isEmpty,
      reason: 'message content must not rebuild per drag delta',
    );
    expect(
      rebuilt.whereType<Text>().where(
        (t) =>
            (t.data ?? t.textSpan?.toPlainText()) == 'hello' ||
            (t.data ?? t.textSpan?.toPlainText()) == 'there',
      ),
      isEmpty,
    );
    expect(rebuilt.whereType<MessageBubble>(), isEmpty);
    expect(rebuilt.whereType<UniversalBubble>(), isNotEmpty);
    for (final bubble in tester.widgetList<UniversalBubble>(
      find.byType(UniversalBubble),
    )) {
      expect(bubble.dragOffsetOverride, -45);
    }
  });

  testWidgets('the listenable still uncovers and positions the timestamp', (
    tester,
  ) async {
    final reveal = ValueNotifier<double>(0);
    addTearDown(reveal.dispose);
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: partner('hello'),
              timestampRevealListenable: reveal,
              // Wired like the chat list: the bubble's own drag drives the
              // shared notifier.
              onTimestampRevealChanged: (offset) => reveal.value = offset,
            ),
          ),
        ),
      ),
    );

    final clock = find.textContaining('3:05');
    expect(clock, findsNothing, reason: 'no reveal column at rest');

    // Same arithmetic as the plain-offset path: progress = (offset-12)/60.
    reveal.value = 42;
    await tester.pump();
    expect(clock, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: clock, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, closeTo(0.5, 1e-9));
    final slide = tester.widget<Transform>(
      find.ancestor(of: clock, matching: find.byType(Transform)).first,
    );
    expect(slide.transform.getTranslation().x, closeTo(5, 1e-9));
    expect(
      tester.widget<UniversalBubble>(find.byType(UniversalBubble))
          .dragOffsetOverride,
      -42,
    );

    reveal.value = 0;
    await tester.pump();
    expect(clock, findsNothing);
    expect(
      tester.widget<UniversalBubble>(find.byType(UniversalBubble))
          .dragOffsetOverride,
      isNull,
    );

    // A real left drag on the bubble feeds the notifier and the shell
    // follows it.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(UniversalBubble)),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-15, 0));
      await tester.pump();
    }
    expect(reveal.value, greaterThan(0));
    expect(
      tester.widget<UniversalBubble>(find.byType(UniversalBubble))
          .dragOffsetOverride,
      -reveal.value,
    );
    expect(clock, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
