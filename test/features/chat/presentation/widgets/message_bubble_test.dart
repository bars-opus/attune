import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders tombstone text when message is deleted', (tester) async {
    final deleted = Message.fromRow(
      {
        'id': 'm1',
        'client_message_id': 'c1',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MessageBubble(message: deleted))),
    );

    expect(find.text('This message was deleted'), findsOneWidget);
  });

  testWidgets('shows a star icon in the footer when the message is starred', (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-star',
        'client_message_id': 'c-star',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message, isStarred: true),
        ),
      ),
    );

    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('does not show a star icon when the message is not starred', (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-unstarred',
        'client_message_id': 'c-unstarred',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: message, isStarred: false),
        ),
      ),
    );

    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('renders edited label when message has been edited', (tester) async {
    final edited = Message.fromRow(
      {
        'id': 'm2',
        'client_message_id': 'c2',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'updated text',
        'created_at': DateTime.now().toIso8601String(),
        'edited_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MessageBubble(message: edited))),
    );

    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets('tapping the edited label calls onShowEditHistory with the message', (tester) async {
    Message? tapped;
    final edited = Message.fromRow(
      {
        'id': 'm2b',
        'client_message_id': 'c2b',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'updated text',
        'created_at': DateTime.now().toIso8601String(),
        'edited_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: edited,
            onShowEditHistory: (message) => tapped = message,
          ),
        ),
      ),
    );

    await tester.tap(find.text('edited'));
    await tester.pumpAndSettle();

    expect(tapped?.id, 'm2b');
  });

  testWidgets('long-press opens the actions sheet for a non-deleted message', (tester) async {
    final message = Message.optimistic(
      id: 'm3',
      clientMessageId: 'c3',
      relationshipId: 'r1',
      senderId: 'u1',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            currentUserId: 'u1',
            onDelete: () {},
          ),
        ),
      ),
    );

    await tester.longPress(find.text('hi'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('tapping the "+" opens the full emoji picker with no exception', (tester) async {
    // Regression guard: the focused menu's "+" button popped its own
    // dialog route and then called onOpenFullPicker synchronously in the
    // same tap handler — showModalBottomSheet raced the route removal and
    // threw "Null check operator used on a null value" from inside
    // Overlay's internals. Fixed by deferring to the next frame
    // (addPostFrameCallback) and guarding with context.mounted in
    // _openFullEmojiPicker. This test exercises the real long-press ->
    // "+" tap path end to end, not a fake onOpenFullPicker callback.
    final message = Message.optimistic(
      id: 'm-emoji',
      clientMessageId: 'c-emoji',
      relationshipId: 'r1',
      senderId: 'u1',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            currentUserId: 'u1',
            onReact: (_) {},
          ),
        ),
      ),
    );

    await tester.longPress(find.text('hi'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    // Flush the deferred addPostFrameCallback that opens the sheet, then
    // let the bottom sheet's own entrance animation settle.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(EmojiPicker), findsOneWidget);
  });

  testWidgets('long-press does nothing for a deleted message (no menu, nothing to act on)', (tester) async {
    final deleted = Message.fromRow(
      {
        'id': 'm4',
        'client_message_id': 'c4',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: deleted, currentUserId: 'u1', onDelete: () {}),
        ),
      ),
    );

    await tester.longPress(find.text('This message was deleted'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('long-press renders the bubble snapshot at the real bubble\'s size, no overflow',
      (tester) async {
    final message = Message.optimistic(
      id: 'm5',
      clientMessageId: 'c5',
      relationshipId: 'r1',
      senderId: 'u1',
      content: 'hi',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: message,
            currentUserId: 'u1',
            onDelete: () {},
          ),
        ),
      ),
    );

    // Size of the real bubble's text before the overlay opens.
    final realSize = tester.getSize(find.text('hi'));

    await tester.longPress(find.text('hi'));
    await tester.pumpAndSettle();

    // No layout overflow from the snapshot being re-rendered under the
    // dialog route (regression: without a Material ancestor the snapshot's
    // text fell back to Flutter's 48px debug style and overflowed).
    expect(tester.takeException(), isNull);

    // Two 'hi' Texts now exist: the real bubble and the overlay snapshot.
    // The snapshot must lay out at exactly the real bubble's size.
    final hiTexts = find.text('hi');
    expect(hiTexts, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(hiTexts.at(i)), realSize);
    }
  });

  // NOTE: the "pop via the tile's own live context, not MessageBubble's"
  // behavior in buildMessageActionItems is covered by
  // test/features/chat/chat_screen_message_actions_test.dart, which drives
  // the real ChatScreen/ListView where the bubble's element actually does
  // get deactivated while the menu is open (6 of its tests fail if that
  // fix is reverted). A synthetic single-bubble rebuild here does not
  // reproduce the deactivation, so no local test is added for it.

  testWidgets('shows a reaction pill with the emoji and count when the message has reactions',
      (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-react',
        'client_message_id': 'c-react',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    ).copyWith(
      reactions: {
        '❤️': {'u1', 'u2'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, currentUserId: 'u1')),
      ),
    );

    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows one pill per distinct emoji, no count badge when only one reactor',
      (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-react2',
        'client_message_id': 'c-react2',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    ).copyWith(
      reactions: {
        '❤️': {'u1'},
        '👍': {'u2'},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, currentUserId: 'u1')),
      ),
    );

    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('no reaction pill renders when the message has no reactions',
      (tester) async {
    final message = Message.fromRow(
      {
        'id': 'm-noreact',
        'client_message_id': 'c-noreact',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello',
        'created_at': DateTime.now().toIso8601String(),
      },
      currentUserId: 'u1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: message, currentUserId: 'u1')),
      ),
    );

    expect(find.textContaining('❤'), findsNothing);
  });
}
