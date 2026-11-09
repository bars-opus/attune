// Spec 2 W3a fix round 1 (review M-5): Dating's availability gate reads
// get_dating_home() and fails closed.
import 'dart:convert';

import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _client(
  http.Response Function(http.Request) answer,
  List<String> paths,
) => SupabaseClient(
  'http://localhost:54321',
  'test-anon-key',
  httpClient: MockClient((request) async {
    paths.add('${request.method} ${request.url.path}');
    return answer(request);
  }),
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

http.Response Function(http.Request) _json(Object? body, [int status = 200]) =>
    (request) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  test('off only when get_dating_home says feature_unavailable', () async {
    const cases = {
      'feature_unavailable': false,
      'country_closed': true,
      'not_started': true,
      'active': true,
    };
    for (final e in cases.entries) {
      final paths = <String>[];
      final client = _client(_json({'state': e.key}), paths);
      expect(
        await DatingFeatureFlags.isDatingModeAvailable(client),
        e.value,
        reason: e.key,
      );
      expect(paths, ['POST /rest/v1/rpc/get_dating_home']);
    }
  });

  test('an error, a non-object or a missing state is false', () async {
    final answers = <String, http.Response Function(http.Request)>{
      'server error': _json({'message': 'boom'}, 500),
      'a list': _json([1]),
      'no state': _json(<String, Object?>{}),
      'a number state': _json({'state': 3}),
    };
    for (final e in answers.entries) {
      final client = _client(e.value, <String>[]);
      expect(
        await DatingFeatureFlags.isDatingModeAvailable(client),
        isFalse,
        reason: e.key,
      );
    }
  });
}
