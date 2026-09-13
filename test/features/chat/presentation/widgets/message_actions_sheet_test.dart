import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Message _ownMessage({bool canEditOrDelete = true, DateTime? createdAt}) {
  return Message.optimistic(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt:
        createdAt ??
        (canEditOrDelete
            ? DateTime.now()
            : DateTime.now().subtract(const Duration(minutes: 10))),
  );
}

Widget _wrap(List<Widget> Function(BuildContext) build) {
  return ScreenUtilInit(
    designSize: ScreenUtilConfig.designSize,
    minTextAdapt: ScreenUtilConfig.minTextAdapt,
    splitScreenMode: ScreenUtilConfig.splitScreenMode,
    fontSizeResolver: ScreenUtilConfig.resolveFontSize,
    builder:
        (context, child) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(children: build(context)),
            ),
          ),
        ),
  );
}

void main() {
  testWidgets(
    'shows timestamp, Reply, Copy, Star, Pin, Info, Edit, Delete for an own recent message',
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
            onInfo: () {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.textContaining('Today At'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.byIcon(Icons.reply_outlined), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    },
  );

  testWidgets('shows date and time on separate lines for older messages', (
    tester,
  ) async {
    final createdAt = DateTime.now().subtract(const Duration(days: 2));
    await tester.pumpWidget(
      _wrap(
        (context) => buildMessageActionItems(
          context: context,
          message: _ownMessage(canEditOrDelete: false, createdAt: createdAt),
          currentUserId: 'u1',
          isStarred: false,
          isPinned: false,
          onReply: () {},
          onCopy: () {},
          onStar: () {},
          onUnstar: () {},
          onPin: () {},
          onUnpin: () {},
          onInfo: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.textContaining('Today At'), findsNothing);
    expect(find.textContaining('${createdAt.year}'), findsOneWidget);
  });

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
          onInfo: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
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
          onInfo: () {},
          onEdit: () {},
          onDelete: () {},
        ),
      ),
    );

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Info'), findsOneWidget);
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
          onInfo: () {},
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
          onInfo: () {},
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
