import 'dart:io';

import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The channel callbacks used to throw the payload away and emit null, so
  // the handler could only refetch everything. The event now says what moved
  // and, where the frame carries one, which message — including a DELETE,
  // whose id lives only in the old record.
  group('ChatRealtimeEvent.fromPostgresChange', () {
    test('a messages INSERT names the new row', () {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: 'messages',
        eventType: 'insert',
        newRecord: const {'id': 'm1', 'relationship_id': 'rel'},
        oldRecord: const {},
      );
      expect(event?.kind, ChatRealtimeKind.messageInsert);
      expect(event?.messageId, 'm1');
    });

    test('a messages UPDATE names the row', () {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: 'messages',
        eventType: 'update',
        newRecord: const {'id': 'm2'},
        oldRecord: const {'id': 'm2'},
      );
      expect(event?.kind, ChatRealtimeKind.messageUpdate);
      expect(event?.messageId, 'm2');
    });

    test('a messages DELETE takes the id from the old record', () {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: 'messages',
        eventType: 'delete',
        newRecord: const {},
        oldRecord: const {'id': 'm3'},
      );
      expect(event?.kind, ChatRealtimeKind.messageDelete);
      expect(event?.messageId, 'm3');
    });

    test('a reaction frame names the message it belongs to, add or remove', () {
      final added = ChatRealtimeEvent.fromPostgresChange(
        table: 'message_reactions',
        eventType: 'insert',
        newRecord: const {'message_id': 'm4', 'user_id': 'u', 'emoji': 'x'},
        oldRecord: const {},
      );
      final removed = ChatRealtimeEvent.fromPostgresChange(
        table: 'message_reactions',
        eventType: 'delete',
        newRecord: const {},
        oldRecord: const {'message_id': 'm4', 'user_id': 'u'},
      );
      expect(added?.kind, ChatRealtimeKind.reaction);
      expect(added?.messageId, 'm4');
      expect(removed?.kind, ChatRealtimeKind.reaction);
      expect(removed?.messageId, 'm4');
    });

    test(
      'pins and relationships map to their kinds; unknown tables to null',
      () {
        expect(
          ChatRealtimeEvent.fromPostgresChange(
            table: 'message_pins',
            eventType: 'delete',
            newRecord: const {},
            oldRecord: const {'message_id': 'm5', 'relationship_id': 'rel'},
          )?.kind,
          ChatRealtimeKind.pin,
        );
        expect(
          ChatRealtimeEvent.fromPostgresChange(
            table: 'relationships',
            eventType: 'update',
            newRecord: const {'id': 'rel', 'status': 'paused'},
            oldRecord: const {'id': 'rel'},
          )?.kind,
          ChatRealtimeKind.relationship,
        );
        expect(
          ChatRealtimeEvent.fromPostgresChange(
            table: 'something_else',
            eventType: 'update',
            newRecord: const {},
            oldRecord: const {},
          ),
          isNull,
        );
      },
    );

    test('the resync event has no message and is const', () {
      const event = ChatRealtimeEvent.resync();
      expect(event.kind, ChatRealtimeKind.resync);
      expect(event.messageId, isNull);
    });
  });

  test(
    'the Supabase repository builds getConversation from one relationship read, '
    'not from the whole list',
    () {
      // Source-level: the real repository cannot run without a server. What
      // must hold is that the chat header refresh no longer costs the
      // relationships + users + last message + unread RPC + avatar chain
      // for every conversation the person has.
      final source =
          File(
            'lib/features/chat/data/repositories/supabase_chat_repository.dart',
          ).readAsStringSync();
      final start = source.indexOf('Future<Conversation?> getConversation(');
      final end = source.indexOf('@override', start + 1);
      final body = source.substring(start, end);
      expect(body, isNot(contains('getConversations()')));
      expect(body, contains(".eq('id', relationshipId)"));
      expect(body, isNot(contains('_fetchUnreadCount')));
      expect(body, isNot(contains('_fetchLastMessage')));
      // Defense in depth: membership is filtered in the query too, not
      // left to RLS alone, so a misconfigured policy never hands a
      // non-member a Conversation.
      expect(
        body,
        contains(r".or('user_a.eq.${user.id},user_b.eq.${user.id}')"),
      );
    },
  );

  group('chunkMessageIds', () {
    // PostgREST puts an `in` filter in the URL; a resume that asks for a
    // few hundred ids at once must not build one request too long for the
    // gateway, so getMessagesByIds asks in chunks.
    test('no ids makes no chunk (and so no request)', () {
      expect(chunkMessageIds(const []), isEmpty);
    });

    test('duplicates are asked for once', () {
      expect(chunkMessageIds(const ['a', 'b', 'a', 'b', 'c']), [
        ['a', 'b', 'c'],
      ]);
    });

    test('more than 100 ids are all asked for, at most 100 per request', () {
      final ids = [for (var i = 0; i < 250; i++) 'm$i'];
      final chunks = chunkMessageIds([...ids, ...ids.take(30)]);
      expect(chunks.map((c) => c.length), [100, 100, 50]);
      expect(chunks.expand((c) => c).toList(), ids);
    });
  });
}
