import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets(
      'tapping the "+" opens the full emoji picker on a populated category, no exception',
      (tester) async {
    // Regression guard, two bugs found on real devices (neither reachable
    // via this widget-test harness on its own, so both are guarded here as
    // precisely as flutter test allows):
    // (1) emoji_picker_flutter's checkPlatformCompatibility (default true)
    //     force-unwraps a platform-channel call with no null check, which
    //     crashed on a real Android device with no native handler
    //     registered. checkPlatformCompatibility is now false. This path is
    //     gated behind Platform.isAndroid inside the package itself, so it
    //     never runs under flutter test's VM target — not exercised here,
    //     just guarded by keeping the config flag in place.
    // (2) The package's default initCategory is Category.RECENT, which is
    //     EMPTY on first use (nothing has ever been picked before) —
    //     confirmed on a real iOS Simulator: the sheet opened with no
    //     crash but showed no emoji at all. THIS bug IS reachable here:
    //     asserting EmojiCell actually renders is what would have caught
    //     it — the pre-fix version opens the sheet and finds zero cells.
    //
    // emoji_picker_flutter reads SharedPreferences on init regardless of
    // initCategory (recentTabBehavior still defaults to reading recents),
    // so this needs the same mock every other SharedPreferences-touching
    // test file in this suite uses.
    SharedPreferences.setMockInitialValues({});

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
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(EmojiPicker), findsOneWidget);
    // The real content check: at least one emoji is actually rendered,
    // proving the sheet did not land on the empty first-use Recent tab.
    expect(find.byType(EmojiCell), findsWidgets);
  });

  testWidgets(
      'the "+" still opens the picker when the list recycles the bubble while the menu is open',
      (tester) async {
    // THE regression guard for "tapping + does nothing", which the test above
    // could never catch: it renders a bare MessageBubble whose element is
    // never recycled, so the captured context stays mounted and the bug is
    // invisible.
    //
    // In production MessageBubble is built lazily inside ChatScreen's
    // ListView.builder. Its element is therefore recyclable, and the focused
    // menu route covers the list while it is open — so a list rebuild
    // underneath (realtime merge, reaction patch, scrolling past the cache
    // extent) can deactivate the bubble's element before "+" is tapped.
    // _openFullEmojiPicker used to receive that element's context and bail on
    // `!context.mounted`, silently doing nothing with no exception raised.
    // Capturing the NavigatorState at long-press time fixes it; against the
    // old context-based version this test fails with zero EmojiPicker found.
    SharedPreferences.setMockInitialValues({});

    var itemCount = 3;
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return ListView.builder(
                itemCount: itemCount,
                itemBuilder: (context, index) => MessageBubble(
                  message: Message.optimistic(
                    id: 'm$index',
                    clientMessageId: 'c$index',
                    relationshipId: 'r1',
                    senderId: 'u1',
                    content: 'msg $index',
                    createdAt: DateTime.now(),
                  ),
                  currentUserId: 'u1',
                  onReact: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.longPress(find.text('msg 0'));
    await tester.pumpAndSettle();

    // The list rebuilds without the long-pressed message, unmounting that
    // bubble's element while the focused menu route is still up.
    setOuter(() => itemCount = 0);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(EmojiPicker), findsOneWidget);
    expect(find.byType(EmojiCell), findsWidgets);
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
