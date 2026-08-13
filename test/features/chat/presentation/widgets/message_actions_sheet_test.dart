import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message _ownMessage({bool starred = false, bool canEditOrDelete = true}) {
  return Message.optimistic(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt: canEditOrDelete
        ? DateTime.now()
        : DateTime.now().subtract(const Duration(minutes: 10)),
  );
}

void main() {
  testWidgets('shows Reply, Copy, Star, Pin, Edit, Delete for an own recent message', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(2400, 3600);
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(),
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('omits Edit and Delete when the 5-minute window has passed', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(2400, 3600);
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(canEditOrDelete: false),
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('omits Edit and Delete for a message from the other partner', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(2400, 3600);
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

    final theirMessage = Message.optimistic(
      id: 'm2',
      clientMessageId: 'c2',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: theirMessage,
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('shows Unstar instead of Star when isStarred is true', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(2400, 3600);
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(),
                currentUserId: 'u1',
                isStarred: true,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () {},
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Unstar'), findsOneWidget);
    expect(find.text('Star'), findsNothing);
  });

  testWidgets('tapping Delete calls onDelete and closes the sheet', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(2400, 3600);
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showMessageActionsSheet(
                context: context,
                message: _ownMessage(),
                currentUserId: 'u1',
                isStarred: false,
                onReply: () {},
                onCopy: () {},
                onStar: () {},
                onUnstar: () {},
                onPin: () {},
                onUnpin: () {},
                onEdit: () {},
                onDelete: () => deleted = true,
                isPinned: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Delete'), findsNothing); // sheet closed
  });
}
