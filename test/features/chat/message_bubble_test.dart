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

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('status chip exposes a semantic label (not color-only)',
      (tester) async {
    await _pump(
      tester,
      MessageBubble(message: _mine(status: MessageStatus.read)),
    );

    expect(find.text('Read'), findsOneWidget);
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

  testWidgets('time has an accessible absolute-time label', (tester) async {
    await _pump(
      tester,
      MessageBubble(message: _mine(status: MessageStatus.sent)),
    );
    // The absolute label includes the year; the visible short label does not.
    final semantics = tester.getSemantics(
      find.descendant(
        of: find.byType(MessageBubble),
        matching: find.byType(Semantics),
      ).first,
    );
    // At least one semantics node in the bubble references the full date.
    expect(
      find.bySemanticsLabel(RegExp(r'2026')),
      findsOneWidget,
    );
    expect(semantics, isNotNull);
  });
}
