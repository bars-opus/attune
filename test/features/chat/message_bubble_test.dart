import 'package:attune/core/ui/motion/icon_crossfade.dart';

import 'support/chat_test_harness.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message _mine({
  required MessageStatus status,
  String content = 'hello',
  String source = 'native',
}) {
  return Message(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'me',
    content: content,
    createdAt: DateTime(2026, 7, 1, 15, 4),
    status: status,
    isMine: true,
    source: source,
  );
}

Message _partner({String content = 'hello'}) {
  return Message(
    id: 'm2',
    clientMessageId: 'c2',
    relationshipId: 'r1',
    senderId: 'partner',
    content: content,
    createdAt: DateTime(2026, 7, 1, 15, 5),
    status: MessageStatus.delivered,
    isMine: false,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    withScreenUtil(MaterialApp(home: Scaffold(body: child))),
  );
}

BorderRadius _messageBubbleRadius(WidgetTester tester) {
  for (final decorated in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(MessageBubble),
      matching: find.byType(DecoratedBox),
    ),
  )) {
    final decoration = decorated.decoration;
    if (decoration is BoxDecoration &&
        (decoration.gradient != null || decoration.color != null) &&
        decoration.borderRadius is BorderRadius) {
      return decoration.borderRadius! as BorderRadius;
    }
  }
  throw StateError('No message bubble decoration found.');
}

Rect _messageBubbleFillRect(WidgetTester tester, Key scopeKey) {
  final elements =
      find
          .descendant(
            of: find.byKey(scopeKey),
            matching: find.byType(DecoratedBox),
          )
          .evaluate();
  for (final element in elements) {
    final decorated = element.widget as DecoratedBox;
    final decoration = decorated.decoration;
    if (decoration is BoxDecoration &&
        (decoration.gradient != null || decoration.color != null) &&
        decoration.borderRadius is BorderRadius) {
      final renderBox = element.renderObject! as RenderBox;
      return renderBox.localToGlobal(Offset.zero) & renderBox.size;
    }
  }
  throw StateError('No message bubble fill found.');
}

class _TimestampRevealHarness extends StatefulWidget {
  const _TimestampRevealHarness();

  @override
  State<_TimestampRevealHarness> createState() =>
      _TimestampRevealHarnessState();
}

class _TimestampRevealHarnessState extends State<_TimestampRevealHarness> {
  double revealOffset = 0;

  @override
  Widget build(BuildContext context) {
    return MessageBubble(
      message: _mine(status: MessageStatus.sent, content: 'outgoing message'),
      timestampRevealOffset: revealOffset,
      onTimestampRevealChanged: (offset) {
        setState(() => revealOffset = offset);
      },
    );
  }
}

class _SharedTimestampRevealHarness extends StatefulWidget {
  const _SharedTimestampRevealHarness();

  @override
  State<_SharedTimestampRevealHarness> createState() =>
      _SharedTimestampRevealHarnessState();
}

class _SharedTimestampRevealHarnessState
    extends State<_SharedTimestampRevealHarness> {
  double revealOffset = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MessageBubble(
          message: _mine(
            status: MessageStatus.sent,
            content: 'outgoing message',
          ),
          timestampRevealOffset: revealOffset,
          onTimestampRevealChanged: _updateReveal,
        ),
        MessageBubble(
          message: _partner(content: 'partner message'),
          timestampRevealOffset: revealOffset,
          onTimestampRevealChanged: _updateReveal,
        ),
      ],
    );
  }

  void _updateReveal(double offset) {
    setState(() => revealOffset = offset);
  }
}

void main() {
  testWidgets('status chip exposes a semantic label (not color-only)', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(message: _mine(status: MessageStatus.read)),
    );

    // WhatsApp-style: icon + color only, no visible "Read" text — the
    // accessible label below is what keeps this non-color-only for screen
    // readers.
    expect(find.text('Read'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Message status: Read')),
      findsOneWidget,
    );
  });

  testWidgets('failed message shows Retry and Remove actions', (tester) async {
    var retried = false;
    var removed = false;
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.failed),
        onRetry: () => retried = true,
        onRemove: () => removed = true,
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Remove'));
    expect(retried, isTrue);
    expect(removed, isTrue);
  });

  testWidgets('non-failed message hides Retry/Remove', (tester) async {
    await _pump(
      tester,
      MessageBubble(message: _mine(status: MessageStatus.sent)),
    );
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('imported message renders its provenance label', (tester) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.read, source: 'import:whatsapp'),
      ),
    );
    expect(find.text('Imported from WhatsApp'), findsOneWidget);
  });

  testWidgets('revealed time has an accessible absolute-time label', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.sent),
        timestampRevealOffset: 80,
      ),
    );
    // The absolute label includes the year; the visible short label does not.
    final semantics = tester.getSemantics(
      find
          .descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Semantics),
          )
          .first,
    );
    // At least one semantics node in the bubble references the full date.
    expect(find.bySemanticsLabel(RegExp(r'2026')), findsOneWidget);
    expect(semantics, isNotNull);
  });

  testWidgets('latest outgoing footer shows timestamp with status at rest', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.read),
        showStatus: true,
        showLatestTimestamp: true,
        timestampRevealOffset: 0,
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp('Message status: Read')),
      findsOneWidget,
    );
    expect(find.textContaining('3:04'), findsOneWidget);
  });

  testWidgets('latest partner footer shows timestamp without status at rest', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _partner(),
        showStatus: false,
        showLatestTimestamp: true,
      ),
    );

    expect(find.textContaining('3:05'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Message status:')), findsNothing);
  });

  testWidgets('revealed latest outgoing timestamp stays above status footer', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.read),
        showStatus: true,
        showLatestTimestamp: false,
        timestampRevealOffset: 80,
      ),
    );

    final timestampRect = tester.getRect(find.textContaining('3:04').first);
    final statusRect = tester.getRect(
      find.bySemanticsLabel(RegExp('Message status: Read')),
    );
    expect(timestampRect.center.dy, lessThan(statusRect.center.dy));
  });

  testWidgets('revealed timestamp sits directly over the chat background', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.read),
        showStatus: true,
        showLatestTimestamp: false,
        timestampRevealOffset: 80,
      ),
    );

    final context = tester.element(find.byType(MessageBubble));
    final colorScheme = Theme.of(context).colorScheme;
    final timestamp = find.textContaining('3:04').first;
    final timestampText = tester.widget<Text>(timestamp);
    expect(timestampText.style?.color, colorScheme.primary);
    expect(timestampText.style?.fontWeight, FontWeight.w600);

    final surfaceBackings = tester.widgetList<ColoredBox>(
      find.ancestor(of: timestamp, matching: find.byType(ColoredBox)),
    );
    expect(
      surfaceBackings.any((box) => box.color == colorScheme.surface),
      isFalse,
    );
  });

  testWidgets('timestamp is progressively revealed as the bubbles move', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.sent),
        timestampRevealOffset: 32,
      ),
    );

    final timestamp = find.textContaining('3:04');
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: timestamp, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, greaterThan(0));
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('outgoing timestamp is fully revealed only while drag is held', (
    tester,
  ) async {
    await _pump(tester, const _TimestampRevealHarness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('outgoing message')),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();

    final harness = tester.state<_TimestampRevealHarnessState>(
      find.byType(_TimestampRevealHarness),
    );
    // 120px of drag, clamped to UniversalBubble._timestampRevealLimit (112).
    // This previously asserted the raw 120: the drag genuinely exceeds the
    // limit, and the old value only went unnoticed because the missing
    // ScreenUtil init aborted the build before the clamp ever ran.
    expect(harness.revealOffset, 112);

    final timestamp = find.textContaining('3:04');
    expect(timestamp, findsOneWidget);
    expect(
      find.ancestor(of: timestamp, matching: find.byType(Opacity)),
      findsOneWidget,
    );
    final timestampText = tester.widget<Text>(timestamp);
    expect(timestampText.maxLines, 1);
    expect(timestampText.softWrap, isFalse);

    await gesture.up();
    await tester.pump();

    expect(find.textContaining('3:04'), findsNothing);
  });

  testWidgets('timestamp drag gives outgoing bubbles enough reveal clearance', (
    tester,
  ) async {
    await _pump(tester, const _TimestampRevealHarness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('outgoing message')),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pump();

    final harness = tester.state<_TimestampRevealHarnessState>(
      find.byType(_TimestampRevealHarness),
    );
    expect(harness.revealOffset, 112);

    final bubbleRect = tester.getRect(find.byKey(const ValueKey('c1')));
    final timestampRect = tester.getRect(find.textContaining('3:04'));
    expect(bubbleRect.right, lessThan(timestampRect.left));

    await gesture.up();
  });

  testWidgets('dragging one message shifts every visible bubble together', (
    tester,
  ) async {
    await _pump(tester, const _SharedTimestampRevealHarness());

    final outgoingBefore = tester.getRect(find.byKey(const ValueKey('c1')));
    final partnerBefore = tester.getRect(find.byKey(const ValueKey('c2')));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('outgoing message')),
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();

    final outgoingAfter = tester.getRect(find.byKey(const ValueKey('c1')));
    final partnerAfter = tester.getRect(find.byKey(const ValueKey('c2')));
    expect(outgoingAfter.left - outgoingBefore.left, -80);
    expect(partnerAfter.left - partnerBefore.left, -80);

    await gesture.up();
  });

  testWidgets('cancelled timestamp drag always snaps the bubbles closed', (
    tester,
  ) async {
    await _pump(tester, const _TimestampRevealHarness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('outgoing message')),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    expect(find.textContaining('3:04'), findsOneWidget);

    final horizontalDragFinder = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector && widget.onHorizontalDragUpdate != null,
    );
    expect(horizontalDragFinder, findsOneWidget);
    final horizontalDragDetector = tester.widget<GestureDetector>(
      horizontalDragFinder,
    );
    expect(horizontalDragDetector.onHorizontalDragCancel, isNotNull);
    horizontalDragDetector.onHorizontalDragCancel!();
    await tester.pump();

    expect(find.textContaining('3:04'), findsNothing);
    await gesture.cancel();
  });

  testWidgets('grouped bubbles square only the touching sender-side corners', (
    tester,
  ) async {
    const outer = Radius.circular(24);
    const inner = Radius.circular(6);

    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.sent),
        isGrouped: false,
        isGroupedWithPrevious: true,
      ),
    );
    expect(
      _messageBubbleRadius(tester),
      const BorderRadius.only(
        topLeft: outer,
        bottomLeft: outer,
        topRight: outer,
        bottomRight: inner,
      ),
    );

    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.sent),
        isGrouped: true,
        isGroupedWithPrevious: true,
      ),
    );
    expect(
      _messageBubbleRadius(tester),
      const BorderRadius.only(
        topLeft: outer,
        bottomLeft: outer,
        topRight: inner,
        bottomRight: inner,
      ),
    );

    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.sent),
        isGrouped: true,
        isGroupedWithPrevious: false,
      ),
    );
    expect(
      _messageBubbleRadius(tester),
      const BorderRadius.only(
        topLeft: outer,
        bottomLeft: outer,
        topRight: inner,
        bottomRight: outer,
      ),
    );

    await _pump(
      tester,
      MessageBubble(
        message: _partner(),
        isGrouped: true,
        isGroupedWithPrevious: true,
      ),
    );
    expect(
      _messageBubbleRadius(tester),
      const BorderRadius.only(
        topLeft: inner,
        bottomLeft: inner,
        topRight: outer,
        bottomRight: outer,
      ),
    );
  });

  testWidgets('consecutive same-sender bubble fills keep a small grouped gap', (
    tester,
  ) async {
    const olderKey = ValueKey('older-message');
    const newerKey = ValueKey('newer-message');

    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: olderKey,
            child: MessageBubble(
              message: _mine(
                status: MessageStatus.sent,
                content: 'older in the run',
              ),
              showStatus: false,
              isGroupedWithPrevious: true,
            ),
          ),
          KeyedSubtree(
            key: newerKey,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: MessageBubble(
                message: _mine(
                  status: MessageStatus.sent,
                  content: 'newer in the run',
                ),
                showStatus: false,
                isGrouped: true,
              ),
            ),
          ),
        ],
      ),
    );

    final olderRect = _messageBubbleFillRect(tester, olderKey);
    final newerRect = _messageBubbleFillRect(tester, newerKey);
    expect(newerRect.top - olderRect.bottom, 3);
  });

  testWidgets('status icon is wrapped in an IconCrossfade for morphing', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(message: _mine(status: MessageStatus.delivered)),
    );
    expect(find.byType(IconCrossfade), findsWidgets);
  });
}
