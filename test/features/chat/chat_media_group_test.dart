import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/chat_media_group.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMediaRunLayout', () {
    test('groups separately sent consecutive images from the same sender', () {
      final messages = [
        _media('newest', type: 'image', minute: 20),
        _media('middle', type: 'image', minute: 8),
        _media('oldest', type: 'image', minute: 1),
      ];

      final layout = ChatMediaRunLayout.fromMessages(messages);

      expect(layout.runs[0], messages);
      expect(layout.hiddenIndices, {1, 2});
    });

    test('groups videos but keeps mixed media in separate runs', () {
      final messages = [
        _media('video-new', type: 'video', minute: 4),
        _media('video-old', type: 'video', minute: 3),
        _media('image-new', type: 'image', minute: 2),
        _media('image-old', type: 'image', minute: 1),
      ];

      final layout = ChatMediaRunLayout.fromMessages(messages);

      expect(layout.runs[0]!.map((message) => message.id), [
        'video-new',
        'video-old',
      ]);
      expect(layout.runs[2]!.map((message) => message.id), [
        'image-new',
        'image-old',
      ]);
      expect(layout.hiddenIndices, {1, 3});
    });

    test(
      'sender changes, captions, replies, and day boundaries split runs',
      () {
        final messages = [
          _media('mine', type: 'image', minute: 5),
          _media('theirs', type: 'image', minute: 4, isMine: false),
          _media('caption', type: 'image', minute: 3, content: 'Look at this'),
          _media('reply', type: 'image', minute: 2, replyToMessageId: 'parent'),
          _media('yesterday', type: 'image', minute: 1, day: 23),
        ];

        final layout = ChatMediaRunLayout.fromMessages(messages);

        expect(layout.runs, isEmpty);
        expect(layout.hiddenIndices, isEmpty);
      },
    );
  });

  testWidgets(
    'horizontal media swipe changes the front item inside a swipeable bubble',
    (tester) async {
      final messages = [
        _media('newest', type: 'image', minute: 2),
        _media('oldest', type: 'image', minute: 1),
      ];
      Message? opened;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: messages.first,
                mediaGroup: messages,
                onReply: () {},
                onTimestampRevealChanged: (_) {},
                onImageTap: (message) => opened = message,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1 / 2'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-230, 0));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);

      await tester.tap(find.byType(PageView));
      await tester.pump();

      expect(opened?.id, 'oldest');
    },
  );
}

Message _media(
  String id, {
  required String type,
  required int minute,
  int day = 24,
  bool isMine = true,
  String content = '',
  String? replyToMessageId,
}) {
  return Message(
    id: id,
    clientMessageId: 'client-$id',
    relationshipId: 'relationship',
    senderId: isMine ? 'me' : 'partner',
    content: content,
    createdAt: DateTime(2026, 8, day, 12, minute),
    status: MessageStatus.sent,
    isMine: isMine,
    mediaKey: '$id.${type == 'image' ? 'jpg' : 'mp4'}',
    mediaType: type,
    localMediaPath: '/tmp/attune-test-missing-$id',
    replyToMessageId: replyToMessageId,
  );
}
