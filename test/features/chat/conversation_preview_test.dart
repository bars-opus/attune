import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/utils/conversation_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _withLast(Message? message) => Conversation(
  id: 'c1',
  relationshipId: 'rel-1',
  partnerId: 'user-b',
  name: 'Ama',
  availability: ConversationAvailability.active,
  unreadCount: 0,
  updatedAt: DateTime.utc(2026, 1, 1),
  relationshipStatus: 'active',
  lastMessage: message,
);

Message _message({
  String content = '',
  String? mediaType,
  DateTime? deletedAt,
}) => Message(
  id: 'm1',
  clientMessageId: 'cm1',
  relationshipId: 'rel-1',
  senderId: 'user-a',
  content: content,
  createdAt: DateTime.utc(2026, 1, 1),
  status: MessageStatus.sent,
  isMine: true,
  mediaType: mediaType,
  deletedAt: deletedAt,
);

void main() {
  test('a voice note reads as a voice message, not a blank row', () {
    expect(
      conversationPreviewText(_withLast(_message(mediaType: 'audio'))),
      'Voice message',
    );
  });

  test('photo and video keep their existing labels', () {
    expect(
      conversationPreviewText(_withLast(_message(mediaType: 'image'))),
      'Photo',
    );
    expect(
      conversationPreviewText(_withLast(_message(mediaType: 'video'))),
      'Video',
    );
  });

  test('a caption is appended after the label', () {
    expect(
      conversationPreviewText(
        _withLast(_message(mediaType: 'image', content: 'at the beach')),
      ),
      'Photo: at the beach',
    );
  });

  test('plain text passes through', () {
    expect(
      conversationPreviewText(_withLast(_message(content: 'hello'))),
      'hello',
    );
  });

  test('deleted and empty states', () {
    expect(conversationPreviewText(_withLast(null)), 'No messages yet');
    expect(
      conversationPreviewText(
        _withLast(_message(deletedAt: DateTime.utc(2026, 1, 2))),
      ),
      'This message was deleted',
    );
  });
}
