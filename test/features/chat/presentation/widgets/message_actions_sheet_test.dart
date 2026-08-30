import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message _ownMessage({bool canEditOrDelete = true}) {
  return Message.optimistic(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt:
        canEditOrDelete
            ? DateTime.now()
            : DateTime.now().subtract(const Duration(minutes: 10)),
  );
}

Widget _wrap(List<Widget> Function(BuildContext) build) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) => Column(children: build(context))),
    ),
  );
}

void main() {
  testWidgets(
    'shows Reply, Copy, Star, Pin, Edit, Delete for an own recent message',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (context) => buildMessageActionItems(
            context: context,
            message: _ownMessage(),
            currentUserId: 'u1',
            isStarred: false,
            isPinned: false,
            onReply: () {},
            onCopy: () {},
            onStar: () {},
            onUnstar: () {},
            onPin: () {},
            onUnpin: () {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets('omits Edit and Delete when the 5-minute window has passed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(canEditOrDelete: false),
          currentUserId: 'u1',
          isStarred: false,
          isPinned: false,
          onReply: () {},
          onCopy: () {},
          onStar: () {},
          onUnstar: () {},
          onPin: () {},
          onUnpin: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('omits Edit and Delete for a message from the other partner', (
    tester,
  ) async {
    final theirMessage = Message.optimistic(
      id: 'm2',
      clientMessageId: 'c2',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: theirMessage,
          currentUserId: 'u1',
          isStarred: false,
          isPinned: false,
          onReply: () {},
          onCopy: () {},
          onStar: () {},
          onUnstar: () {},
          onPin: () {},
          onUnpin: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('shows Unstar instead of Star when isStarred is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(),
          currentUserId: 'u1',
          isStarred: true,
          isPinned: false,
          onReply: () {},
          onCopy: () {},
          onStar: () {},
          onUnstar: () {},
          onPin: () {},
          onUnpin: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('Unstar'), findsOneWidget);
    expect(find.text('Star'), findsNothing);
  });

  testWidgets('tapping Delete calls onDelete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(),
          currentUserId: 'u1',
          isStarred: false,
          isPinned: false,
          onReply: () {},
          onCopy: () {},
          onStar: () {},
          onUnstar: () {},
          onPin: () {},
          onUnpin: () {},
          onEdit: () {},
          onDelete: () => deleted = true,
        ),
      ),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });
}
