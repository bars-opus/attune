import 'dart:io';

import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ChatErrorCategory categoryOf(String? code, String message) =>
    ChatError.from(PostgrestException(message: message, code: code)).category;

void main() {
  group('Postgrest categorizer (W1a I2, Spec 4.2)', () {
    test('a trigger RAISE (P0001) is a server rejection that counts', () {
      expect(
        categoryOf('P0001', 'Reply target message does not exist'),
        ChatErrorCategory.unknown,
      );
      expect(
        categoryOf('P0001', 'Reply target must be in the same relationship'),
        ChatErrorCategory.unknown,
      );
      expect(
        categoryOf('P0001', 'Story unavailable'),
        ChatErrorCategory.unknown,
      );
    });

    test('data (22) and other constraint (23) errors count', () {
      expect(
        categoryOf('22P02', 'invalid input syntax for type uuid'),
        ChatErrorCategory.unknown,
      );
      expect(categoryOf('22001', 'value too long'), ChatErrorCategory.unknown);
    });

    test('class 42 counts, except 42501 which stays unauthenticated', () {
      expect(
        categoryOf('42883', 'function does not exist'),
        ChatErrorCategory.unknown,
      );
      expect(
        categoryOf('42501', 'permission denied for table messages'),
        ChatErrorCategory.unauthenticated,
      );
    });

    test('23505 stays unknown (callers reconcile it)', () {
      expect(categoryOf('23505', 'duplicate key'), ChatErrorCategory.unknown);
    });

    test('known message shapes keep their permanent categories', () {
      expect(
        categoryOf('23514', 'new row violates check constraint'),
        ChatErrorCategory.payloadInvalid,
      );
      expect(
        categoryOf('P0001', 'relationship is archived'),
        ChatErrorCategory.relationshipArchived,
      );
    });

    test('HTTP / gateway failures stay unavailable (uncapped)', () {
      expect(
        categoryOf('503', 'Service Unavailable'),
        ChatErrorCategory.unavailable,
      );
      expect(categoryOf('502', 'Bad Gateway'), ChatErrorCategory.unavailable);
      expect(categoryOf(null, 'upstream reset'), ChatErrorCategory.unavailable);
      expect(
        categoryOf('PGRST000', 'could not connect to the database'),
        ChatErrorCategory.unavailable,
      );
    });

    test('socket and timeout errors stay offline', () {
      expect(
        ChatError.from(const SocketException('x')).category,
        ChatErrorCategory.offline,
      );
    });
  });

  group('load copy is never send copy', () {
    const sendCopy = 'Message not sent. Tap to retry.';

    test(
      'a database rejection on a page read says the messages did not load',
      () {
        final error = ChatError.from(
          const PostgrestException(message: 'boom', code: 'P0001'),
        );
        expect(error.category, ChatErrorCategory.unknown);
        expect(error.toLoadMessage(), isNot(sendCopy));
        expect(error.toLoadMessage(), contains('load'));
      },
    );

    test('offline on a page read does not promise a send', () {
      final copy = ChatError.from(const SocketException('x')).toLoadMessage();
      expect(copy, isNot(contains('message will send')));
    });

    test('access and lifecycle copy is shared by both contexts', () {
      for (final category in [
        ChatErrorCategory.unauthenticated,
        ChatErrorCategory.relationshipInactive,
        ChatErrorCategory.relationshipArchived,
      ]) {
        final error = ChatError(category);
        expect(error.toLoadMessage(), error.toUserMessage());
      }
    });
  });

  group('HTTP 4xx and PostgREST request codes are rejections (round 4)', () {
    test(
      '4xx counts toward the cap, except 429 (rate limit) and 408 (timeout)',
      () {
        expect(categoryOf('400', 'Bad Request'), ChatErrorCategory.unknown);
        expect(categoryOf('404', 'Not Found'), ChatErrorCategory.unknown);
        expect(categoryOf('409', 'Conflict'), ChatErrorCategory.unknown);
        expect(
          categoryOf('429', 'Too Many Requests'),
          ChatErrorCategory.rateLimited,
        );
        expect(
          categoryOf('408', 'Request Timeout'),
          ChatErrorCategory.unavailable,
        );
      },
    );

    test('PostgREST request (PGRST1xx) and schema (PGRST2xx) codes count', () {
      expect(
        categoryOf(
          'PGRST204',
          "Could not find the 'x' column in the schema cache",
        ),
        ChatErrorCategory.unknown,
      );
      expect(
        categoryOf(
          'PGRST116',
          'JSON object requested, multiple (or no) rows returned',
        ),
        ChatErrorCategory.unknown,
      );
      expect(categoryOf('PGRST100', 'parse error'), ChatErrorCategory.unknown);
    });

    test('5xx, gateway and PostgREST connection codes stay uncapped', () {
      expect(
        categoryOf('500', 'Internal Server Error'),
        ChatErrorCategory.unavailable,
      );
      expect(
        categoryOf('504', 'Gateway Timeout'),
        ChatErrorCategory.unavailable,
      );
      expect(
        categoryOf('PGRST000', 'could not connect'),
        ChatErrorCategory.unavailable,
      );
      expect(
        categoryOf('PGRST003', 'timed out acquiring connection'),
        ChatErrorCategory.unavailable,
      );
    });
  });
}
