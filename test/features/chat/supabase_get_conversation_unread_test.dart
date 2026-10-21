// I-1 (#32b): a chat opened through ChatChannelLoader (a push tap, the
// notification inbox) builds its Conversation from getConversation(). It
// used to hard-code unreadCount: 0, so the "N unread messages" divider never
// showed on the most common way into a chat with unread messages.

import 'dart:async';
import 'dart:convert';

import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = '00000000-0000-0000-0000-00000000000a';
const _partner = '00000000-0000-0000-0000-00000000000b';

String _fakeJwt() {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _me, 'exp': exp, 'role': 'authenticated'})}.sig';
}

Future<SupabaseClient> _client(
  FutureOr<http.Response> Function(http.Request request) rpc,
) async {
  final client = SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/rest/v1/relationships')) {
        return http.Response(
          jsonEncode({
            'id': 'rel-1',
            'user_a': _me,
            'user_b': _partner,
            'status': 'active',
            'chat_archived_at': null,
            'created_at': '2026-07-01T00:00:00Z',
            'ended_at': null,
            'chat_name': null,
            'chat_avatar_url': null,
            'chat_avatar_thumbnail_url': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (path.endsWith('/rest/v1/users')) {
        return http.Response(
          jsonEncode([
            {'id': _partner, 'display_name': 'Sam', 'avatar_url': null},
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      if (path.endsWith('/rest/v1/rpc/count_unread_messages')) {
        return rpc(request);
      }
      return http.Response('not found: $path', 404, request: request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final exp = DateTime.now().add(const Duration(days: 1));
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _me,
        'aud': 'authenticated',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-07-01T00:00:00Z',
      },
    }),
  );
  return client;
}

void main() {
  test('getConversation carries the real unread count', () async {
    final client = await _client(
      (request) => http.Response(
        '6',
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
    addTearDown(client.dispose);
    final conversation = await SupabaseChatRepository(
      client,
    ).getConversation('rel-1');
    expect(conversation, isNotNull);
    expect(conversation!.partnerName, 'Sam');
    expect(conversation.unreadCount, 6);
  });

  test('a failing unread count still opens the chat, with 0', () async {
    final client = await _client(
      (request) => http.Response(
        jsonEncode({'message': 'boom', 'code': 'XX000'}),
        // 400, not 5xx: postgrest retries a 5xx with backoff.
        400,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
    addTearDown(client.dispose);
    final conversation = await SupabaseChatRepository(
      client,
    ).getConversation('rel-1');
    expect(conversation, isNotNull);
    expect(conversation!.unreadCount, 0);
  });

  test('a hung unread count gives up rather than holding the open', () async {
    final never = Completer<http.Response>();
    final client = await _client((_) => never.future);
    addTearDown(client.dispose);
    final conversation = await SupabaseChatRepository(
      client,
      unreadCountTimeout: const Duration(milliseconds: 50),
    ).getConversation('rel-1');
    expect(conversation, isNotNull);
    expect(conversation!.unreadCount, 0);
  });
}
