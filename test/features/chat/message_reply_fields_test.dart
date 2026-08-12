// test/features/chat/message_reply_fields_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message reply fields', () {
    test('fromRow reads reply_to_message_id and quoted_text', () {
      final message = Message.fromRow({
        'id': 'm2',
        'relationship_id': 'r1',
        'sender_id': 'them',
        'client_message_id': 'c2',
        'content': 'sounds good',
        'created_at': '2026-08-12T10:00:00Z',
        'delivered_at': null,
        'read_at': null,
        'media_url': null,
        'media_thumbnail_url': null,
        'media_type': null,
        'source': 'native',
        'reply_to_message_id': 'm1',
        'quoted_text': 'want to grab lunch?',
      }, currentUserId: 'me');

      expect(message.replyToMessageId, 'm1');
      expect(message.quotedText, 'want to grab lunch?');
    });

    test('fromRow tolerates missing reply columns (both null)', () {
      final message = Message.fromRow({
        'id': 'm2',
        'relationship_id': 'r1',
        'sender_id': 'them',
        'client_message_id': 'c2',
        'content': 'hi',
        'created_at': '2026-08-12T10:00:00Z',
        'delivered_at': null,
        'read_at': null,
        'media_url': null,
        'media_thumbnail_url': null,
        'media_type': null,
        'source': 'native',
      }, currentUserId: 'me');

      expect(message.replyToMessageId, isNull);
      expect(message.quotedText, isNull);
    });

    test('copyWith preserves reply fields when not overridden', () {
      final message = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 'them',
        content: 'hi',
        createdAt: DateTime(2026, 8, 12, 10),
        status: MessageStatus.sent,
        isMine: false,
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );

      final copied = message.copyWith(status: MessageStatus.read);
      expect(copied.replyToMessageId, 'm1');
      expect(copied.quotedText, 'earlier text');
    });

    test('toJson/fromJson round-trips reply fields', () {
      final original = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 'them',
        content: 'hi',
        createdAt: DateTime(2026, 8, 12, 10),
        status: MessageStatus.sent,
        isMine: false,
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );

      final restored = Message.fromJson(original.toJson());
      expect(restored.replyToMessageId, 'm1');
      expect(restored.quotedText, 'earlier text');
    });

    test('Message.optimistic accepts reply fields', () {
      final message = Message.optimistic(
        id: '_local_c3',
        clientMessageId: 'c3',
        relationshipId: 'r1',
        senderId: 'me',
        content: 'replying now',
        createdAt: DateTime(2026, 8, 12, 11),
        replyToMessageId: 'm1',
        quotedText: 'earlier text',
      );

      expect(message.replyToMessageId, 'm1');
      expect(message.quotedText, 'earlier text');
    });
  });
}
