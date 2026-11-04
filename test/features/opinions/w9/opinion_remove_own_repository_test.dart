// Spec 1 W9b (OPN-DELETE-RLS, §5.2): deleting your own opinion or comment
// calls remove_my_opinion / remove_my_comment, and nothing else: no direct
// UPDATE of removed_at (refused by RLS), no opinion_id pre-select, no
// separate decrement_opinion_comment_count (the RPC lowers the count once).
import 'dart:convert';

import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<http.Request> requests;
  late OpinionRepository repo;

  setUp(() {
    requests = [];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204, request: request);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repo = OpinionRepository(client);
  });

  String describe(http.Request r) => '${r.method} ${r.url.path} ${r.body}';

  test('deleting an opinion calls remove_my_opinion only', () async {
    await repo.deleteOpinion('o-1');
    expect(requests.map(describe), [
      'POST /rest/v1/rpc/remove_my_opinion ${jsonEncode({'p_opinion_id': 'o-1'})}',
    ]);
  });

  test('deleting a comment calls remove_my_comment only', () async {
    await repo.deleteComment('c-1');
    expect(requests.map(describe), [
      'POST /rest/v1/rpc/remove_my_comment ${jsonEncode({'p_comment_id': 'c-1'})}',
    ]);
  });
}
