// T13 carry: searchMessages' trail exclusion, pinned on the request it
// actually sends (replacing a source-slice test). `.neq` alone would drop
// plain text rows (NULL media_type) through SQL three-valued logic, so the
// filter must be the `or` with an explicit `is.null`.

import 'dart:convert';

import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = '00000000-0000-0000-0000-00000000000a';

String _fakeJwt() {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _me, 'exp': exp, 'role': 'authenticated'})}.sig';
}

Future<(SupabaseClient, List<http.Request>)> _client() async {
  final requests = <http.Request>[];
  final client = SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/rest/v1/messages')) {
        requests.add(request);
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      return http.Response('not found', 404, request: request);
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
  return (client, requests);
}

void main() {
  test('search excludes game trails and keeps plain text rows', () async {
    final (client, requests) = await _client();
    addTearDown(client.dispose);

    await SupabaseChatRepository(
      client,
    ).searchMessages('rel-1', query: '  50% off_now ');

    expect(requests, hasLength(1));
    final params = requests.single.url.queryParameters;
    expect(params['or'], '(media_type.is.null,media_type.neq.game_trail)');
    // ...alongside the other filters, unchanged.
    expect(params['relationship_id'], 'eq.rel-1');
    expect(params['content'], r'ilike.%50\% off\_now%');
    expect(params['deleted_at'], 'is.null');
    expect(params['order'], 'sort_at.desc.nullslast,id.desc.nullslast');
    expect(
      params.containsKey('media_type'),
      isFalse,
      reason: 'a bare media_type filter would drop NULL (plain text) rows',
    );
  });

  test('a blank query never reaches the server', () async {
    final (client, requests) = await _client();
    addTearDown(client.dispose);
    final rows = await SupabaseChatRepository(
      client,
    ).searchMessages('rel-1', query: '   ');
    expect(rows, isEmpty);
    expect(requests, isEmpty);
  });
}
