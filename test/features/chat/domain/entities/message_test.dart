import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message deleted/edited state', () {
    test('fromRow parses deleted_at and edited_at when present', () {
      final row = {
        'id': 'm1',
        'client_message_id': 'c1',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': '2026-08-13T10:00:00Z',
        'deleted_at': '2026-08-13T10:02:00Z',
        'edited_at': null,
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(
        message.deletedAt,
        DateTime.parse('2026-08-13T10:02:00Z').toLocal(),
      );
      expect(message.editedAt, isNull);
      expect(message.isDeleted, isTrue);
    });

    test('fromRow parses edited_at when present, isDeleted false', () {
      final row = {
        'id': 'm2',
        'client_message_id': 'c2',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'updated text',
        'created_at': '2026-08-13T10:00:00Z',
        'deleted_at': null,
        'edited_at': '2026-08-13T10:01:00Z',
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(
        message.editedAt,
        DateTime.parse('2026-08-13T10:01:00Z').toLocal(),
      );
      expect(message.isDeleted, isFalse);
    });

    test('fromRow defaults both to null when absent from the row', () {
      final row = {
        'id': 'm3',
        'client_message_id': 'c3',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hi',
        'created_at': '2026-08-13T10:00:00Z',
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(message.deletedAt, isNull);
      expect(message.editedAt, isNull);
      expect(message.isDeleted, isFalse);
    });

    test('canEditOrDelete is true for own message within 5 minutes', () {
      final message = Message.optimistic(
        id: 'm4',
        clientMessageId: 'c4',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      expect(
        message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()),
        isTrue,
      );
    });

    test('canEditOrDelete is false past the 5-minute window', () {
      final message = Message.optimistic(
        id: 'm5',
        clientMessageId: 'c5',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );
      expect(
        message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()),
        isFalse,
      );
    });

    test('canEditOrDelete is false for a message from the other sender', () {
      final message = Message.optimistic(
        id: 'm6',
        clientMessageId: 'c6',
        relationshipId: 'r1',
        senderId: 'partner',
        content: 'hi',
        createdAt: DateTime.now(),
      );
      expect(
        message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()),
        isFalse,
      );
    });

    test('canEditOrDelete is false for an already-deleted message', () {
      final row = {
        'id': 'm7',
        'client_message_id': 'c7',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': null,
        'created_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      };
      final message = Message.fromRow(row, currentUserId: 'u1');
      expect(
        message.canEditOrDelete(currentUserId: 'u1', now: DateTime.now()),
        isFalse,
      );
    });
  });
}
