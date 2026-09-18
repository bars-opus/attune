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

    // --- Regression-safety net: canEdit/canDelete must match the OLD
    // combined canEditOrDelete's result exactly for every existing case,
    // for an ordinary (non-Assist) message. ---

    test('canEdit and canDelete are both true for own message within 5 minutes', () {
      final message = Message.optimistic(
        id: 'm4',
        clientMessageId: 'c4',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final now = DateTime.now();
      expect(message.canEdit(currentUserId: 'u1', now: now), isTrue);
      expect(message.canDelete(currentUserId: 'u1', now: now), isTrue);
    });

    test('canEdit and canDelete are both false past the 5-minute window', () {
      final message = Message.optimistic(
        id: 'm5',
        clientMessageId: 'c5',
        relationshipId: 'r1',
        senderId: 'u1',
        content: 'hi',
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      );
      final now = DateTime.now();
      expect(message.canEdit(currentUserId: 'u1', now: now), isFalse);
      expect(message.canDelete(currentUserId: 'u1', now: now), isFalse);
    });

    test('canEdit and canDelete are both false for a message from the other sender', () {
      final message = Message.optimistic(
        id: 'm6',
        clientMessageId: 'c6',
        relationshipId: 'r1',
        senderId: 'partner',
        content: 'hi',
        createdAt: DateTime.now(),
      );
      final now = DateTime.now();
      expect(message.canEdit(currentUserId: 'u1', now: now), isFalse);
      expect(message.canDelete(currentUserId: 'u1', now: now), isFalse);
    });

    test('canEdit and canDelete are both false for an already-deleted message', () {
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
      final now = DateTime.now();
      expect(message.canEdit(currentUserId: 'u1', now: now), isFalse);
      expect(message.canDelete(currentUserId: 'u1', now: now), isFalse);
    });
  });

  group('Message.canEdit/canDelete — Attune Assist split (spec §5.3)', () {
    Message assistMessage({required DateTime createdAt, String senderId = 'u1'}) {
      final row = {
        'id': 'a1',
        'client_message_id': 'ca1',
        'relationship_id': 'r1',
        'sender_id': senderId,
        'content': 'Here are a few ideas...',
        'created_at': createdAt.toIso8601String(),
        'message_origin': 'attune_assist',
        'assistant_payload': {
          'schema_version': 1,
          'suggested_planning_item': null,
          'sources': <dynamic>[],
        },
      };
      return Message.fromRow(row, currentUserId: senderId);
    }

    test(
      'an Assist message within the 5-minute window: canDelete true, canEdit false',
      () {
        final message = assistMessage(
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        );
        final now = DateTime.now();
        expect(message.canEdit(currentUserId: 'u1', now: now), isFalse);
        expect(message.canDelete(currentUserId: 'u1', now: now), isTrue);
      },
    );

    test(
      'an Assist message outside the 5-minute window: both canEdit and canDelete false',
      () {
        final message = assistMessage(
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        );
        final now = DateTime.now();
        expect(message.canEdit(currentUserId: 'u1', now: now), isFalse);
        expect(message.canDelete(currentUserId: 'u1', now: now), isFalse);
      },
    );

    test('isAttuneAssistOutput is true for an Assist message', () {
      final message = assistMessage(createdAt: DateTime.now());
      expect(message.isAttuneAssistOutput, isTrue);
    });
  });
}
