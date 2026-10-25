// Spec 1 W1a (§5.2, regression note R5): the legacy onboarding submission
// no longer sends users.phone or users.mode (the client lost both grants)
// and never inserts a users row; W1b also drops onboarding_profiles.mode.
// Pinned on the requests it actually sends.
import 'dart:convert';

import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = '5f1a0000-0000-0000-0000-0000000000aa';

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
      if (request.url.path.startsWith('/rest/v1/')) {
        requests.add(request);
        return http.Response('', 204, request: request);
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
        'phone': '233241234567',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-07-01T00:00:00Z',
      },
    }),
  );
  return (client, requests);
}

http.Request _to(List<http.Request> requests, String table) =>
    requests.singleWhere((r) => r.url.path == '/rest/v1/$table');

Map<String, dynamic> _body(http.Request request) =>
    Map<String, dynamic>.from(jsonDecode(request.body) as Map);

void main() {
  test(
    'users gets an update of the name only: no insert, no phone, no mode',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.couples,
        displayName: 'Ama',
        attachmentAnswers: const [1, 2],
        anchors: const ['time'],
      );

      final users = _to(requests, 'users');
      expect(users.method, 'PATCH');
      expect(users.url.queryParameters['id'], 'eq.$_me');
      expect(_body(users), {'display_name': 'Ama'});
    },
  );

  // Review Focus 5: a legacy name longer than users' 40-character CHECK.
  test(
    'a name over 40 characters is clamped to 40 code points, emoji whole',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);
      final long = '${'A' * 39}😀😀😀';

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.personal,
        displayName: long,
        attachmentAnswers: const [],
        anchors: const [],
      );

      final sent = _body(_to(requests, 'users'))['display_name'] as String;
      expect(sent.runes.length, 40);
      expect(sent, '${'A' * 39}😀');
      expect(_body(_to(requests, 'profiles'))['display_name'], sent);
      expect(OnboardingSubmissionService.clampDisplayName('Ama'), 'Ama');
    },
  );

  test(
    'onboarding_profiles is sent without the dropped mode column (W1b)',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.couples,
        displayName: 'Ama',
        attachmentAnswers: const [3, 4],
        anchors: const ['rest'],
      );

      final body = _body(_to(requests, 'onboarding_profiles'));
      expect(body.containsKey('mode'), isFalse);
      expect(body['user_id'], _me);
      expect(body['attachment_answers'], [3, 4]);
      expect(body['anchors'], ['rest']);
      expect(body['completed_at'], isA<String>());
    },
  );

  // Final review M-1 (controller ruling, as corrected): invisible and bidi
  // controls never reach users or profiles; ZWNJ and ZWJ stay as typed, and
  // a name with nothing visible left is empty.
  test(
    'invisible and bidi controls are dropped before the clamp and the write',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.personal,
        displayName: 'Ama \u202EMensah\u200F',
        attachmentAnswers: const [],
        anchors: const [],
      );

      expect(_body(_to(requests, 'users'))['display_name'], 'Ama Mensah');
      expect(_body(_to(requests, 'profiles'))['display_name'], 'Ama Mensah');

      const stripped =
          '\u200B\u200E\u200F\u202A\u202B\u202C\u202D\u202E'
          '\u2060\u2061\u2062\u2063\u2064\u2066\u2067\u2068\u2069\uFEFF';
      for (final c in stripped.runes) {
        expect(
          OnboardingSubmissionService.clampDisplayName(
            'A${String.fromCharCode(c)}B',
          ),
          'AB',
          reason: 'U+${c.toRadixString(16).toUpperCase()}',
        );
      }
      expect(
        OnboardingSubmissionService.clampDisplayName('Kofi\u2067 Boateng'),
        'Kofi Boateng',
      );
      expect(OnboardingSubmissionService.clampDisplayName('\u200B'), '');
      expect(
        OnboardingSubmissionService.clampDisplayName(' \u200C\u200D$stripped '),
        '',
      );
      expect(
        OnboardingSubmissionService.clampDisplayName('Ama \u200B Mensah'),
        'Ama Mensah',
      );
      // Invisible padding never costs a visible character of the 40.
      expect(
        OnboardingSubmissionService.clampDisplayName(
          '${'\u200B' * 5}${'A' * 45}',
        ),
        'A' * 40,
      );
    },
  );

  // The correction: ZWNJ and ZWJ are kept exactly as typed, and a name of
  // only ZWJ, or ZWNJ and spaces, has nothing visible and is empty.
  test('ZWNJ and ZWJ are kept; a name of only them is empty', () {
    const persian = '\u0645\u0647\u0631\u200C\u0633\u0627';
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467} Ama';
    expect(OnboardingSubmissionService.clampDisplayName(persian), persian);
    expect(OnboardingSubmissionService.clampDisplayName(family), family);
    expect(OnboardingSubmissionService.clampDisplayName('\u200D'), '');
    expect(OnboardingSubmissionService.clampDisplayName('  \u200C '), '');
  });
}
