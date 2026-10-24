// Tests for the story repository (Plan B, Task 4): the three server calls
// that post a story — intent, upload, finalize (spec §4.2).
//
// story_repository.dart wraps SupabaseClient directly, the same shape as
// snakes_service.dart, and the house pattern (snakes_test.dart,
// paint_ball_provider_test.dart) never mocks SupabaseClient's RPC/storage
// builders — those are final, heavily-generic classes with no seam for it.
// So these tests exercise the parts that do not require a live client:
//
//   - StoryApiError.fromJson: the jsonb-to-typed-error conversion, and its
//     retryable classification — pure functions, directly testable.
//   - the upload call site: asserted against the source, the same way
//     snakes_test.dart proves "the client cannot send a die face" by
//     reading snakes_service.dart's text rather than mocking the RPC.
//
// Fix round 1: the first version of this file asserted the taxonomy
// against codes ('rate_limited', 'not_a_member', ...) nobody checked
// against the server. The real vocabulary is five UPPERCASE codes from
// `public.story_intent_error` (supabase/migrations/2026093[89]*.sql) —
// RATE_LIMITED, UNAUTHORIZED, FORBIDDEN, INVALID_INPUT, UNAVAILABLE. The
// 'errors' group below now uses those, and 'the retryable set is drawn
// from codes the server actually emits' derives the vocabulary from the
// migrations directly so this suite cannot silently drift from the
// server again.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/utils/chat_error.dart'
    show ChatImageRejectedSignal;
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthClientOptions,
        AuthException,
        AuthRetryableFetchException,
        PostgrestException,
        SupabaseClient;

/// A JWT whose only meaningful claim is `exp` (chat_media_uploader_test's).
String _jwt(int exp) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': 'user-a', 'exp': exp})}.sig';
}

Map<String, Object> _sessionJson(String accessToken) => {
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh-1',
  'user': {
    'id': 'user-a',
    'aud': 'authenticated',
    'app_metadata': <String, Object>{},
    'user_metadata': <String, Object>{},
    'created_at': '2026-10-18T00:00:00Z',
  },
};

void main() {
  group('errors', () {
    test('an error jsonb becomes a typed error, never a raw exception', () {
      // Checklist 2.4/5.5: {error:true, code, message} -> StoryApiError
      // carrying the server's message. The code stays internal.
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'FORBIDDEN',
        'message': "You don't have access to this story.",
      });

      expect(error, isA<StoryApiError>());
      expect(error.message, "You don't have access to this story.");
      expect(error.code, 'FORBIDDEN');
      // The public surface is the message; toString() is what a caller
      // reaches for by habit, and it must not accidentally print the code
      // or the word "Exception".
      expect(error.toString(), "You don't have access to this story.");
      expect(error.toString(), isNot(contains('FORBIDDEN')));
      expect(error.toString(), isNot(contains('Exception')));
    });

    test('a message-less refusal still reads as English', () {
      final error = StoryApiError.fromJson({'code': 'WEIRD'});
      expect(error.message, isNotEmpty);
      expect(error.message, isNot(contains('WEIRD')));
    });

    test('a RATE_LIMITED refusal is marked retryable', () {
      // The outbox must retry this rather than failing permanently. This
      // is the ONE server code the spec calls retryable (§4.2).
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'RATE_LIMITED',
        'message': 'Slow down a moment before adding more.',
      });

      expect(error.retryable, isTrue);
    });

    test('UNAVAILABLE is NOT retryable, even though an expired intent '
        'is one of the things that causes it', () {
      // The server deliberately collapses "not a member," "relationship
      // ended," "feature off," and "expired/consumed intent" into this
      // one code so a client can never use it as an existence oracle
      // (20260938050000_stories_finalize_rpc.sql:30,96). Because the
      // client cannot tell those apart from the code alone,
      // blanket-retrying UNAVAILABLE would spin forever on the permanent
      // cases. Spec §6.1's recovery for a genuinely expired intent is
      // structural (mint a fresh pair of intents and re-upload), decided
      // by the outbox one layer up — not a retry of this same call.
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'UNAVAILABLE',
        'message': "Stories aren't available right now.",
      });

      expect(error.retryable, isFalse);
    });

    test('a validation refusal is NOT retryable', () {
      // Retrying an unchanged request against a permanent refusal (bad
      // auth, malformed input) would just fail again forever.
      for (final code in ['UNAUTHORIZED', 'FORBIDDEN', 'INVALID_INPUT']) {
        final error = StoryApiError.fromJson({
          'error': true,
          'code': code,
          'message': 'refused',
        });
        expect(error.retryable, isFalse, reason: 'code=$code');
      }
    });

    test('a network failure (no server response at all) is retryable', () {
      final error = StoryApiError.network();
      expect(error.retryable, isTrue);
      expect(error.code, 'network');
    });

    test('the retryable set is drawn from codes the server actually emits', () {
      // Derives truth from the migrations rather than from anyone's
      // belief about what the server sends — the exact gap that let
      // 'rate_limited'/'intent_expired' (neither real) ship as the
      // taxonomy in fix round 0.
      final codes = <String>{};
      for (final f in Directory('supabase/migrations').listSync()) {
        if (f is! File || !f.path.contains('stories')) continue;
        codes.addAll(
          RegExp(
            r"story_intent_error\('([A-Z_]+)'\)",
          ).allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
        );
      }

      // Without this guard, a regex that stopped matching (a migration
      // rename, a formatting change) would make every assertion below
      // vacuously pass on an empty set.
      expect(codes, isNotEmpty, reason: 'the regex stopped matching');
      expect(
        codes,
        containsAll(<String>[
          'UNAUTHORIZED',
          'FORBIDDEN',
          'INVALID_INPUT',
          'RATE_LIMITED',
          'UNAVAILABLE',
        ]),
        reason: 'the known server vocabulary changed — update this test '
            'and the taxonomy doc comment together',
      );

      // Every code the client classifies as retryable must be one the
      // server actually sends.
      expect(codes.containsAll(StoryApiError.retryableCodesForTest), isTrue);
      // And RATE_LIMITED specifically must be retryable — the one code
      // the spec explicitly requires the outbox to retry.
      expect(StoryApiError.retryableCodesForTest, contains('RATE_LIMITED'));
      // Nothing else may be marked retryable: UNAVAILABLE in particular
      // must stay out, since it silently covers the permanent cases too.
      expect(StoryApiError.retryableCodesForTest, {'RATE_LIMITED'});
    });
  });

  group('upload', () {
    test('uploads stream through ChatMediaUploader, which never upserts', () {
      // Spec §4.2: an upsert would let a second capture overwrite an object
      // another intent already claimed. The streamed uploader pins
      // x-upsert: false on every request (chat_media_uploader_test.dart).
      final source =
          File('lib/features/stories/data/story_repository.dart').readAsStringSync();
      expect(source, contains('ChatMediaUploader'));
      expect(source, contains('.upload('));
      expect(source.contains('upsert: true'), isFalse);
      final uploader = File(
        'lib/features/chat/data/repositories/chat_media_uploader.dart',
      ).readAsStringSync();
      expect(uploader, contains("headers['x-upsert'] = 'false'"));
    });

    test('uploadObject targets the intent-provided bucket and key, not a hardcoded one', () {
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      // The bucket/key must flow from the method's own parameters (the
      // intent), never a literal bucket name — the intent is what
      // Storage RLS actually authorizes (spec §4.1/§4.2).
      expect(source.contains("'story-media'"), isFalse,
          reason: 'the bucket must come from the intent, not be hardcoded');
    });
  });

  group('finalize', () {
    test('finalizeStory sends all 8 RPC params to create_story_item', () {
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      expect(source.contains("'create_story_item'"), isTrue);
      for (final param in [
        'p_relationship_id',
        'p_client_story_id',
        'p_media_intent_id',
        'p_thumbnail_intent_id',
        'p_media_width',
        'p_media_height',
        'p_duration_ms',
        'p_utc_offset_minutes',
      ]) {
        expect(source.contains("'$param'"), isTrue, reason: 'missing $param');
      }
    });

    test('p_place is sent only when a place is attached (old servers keep working)', () {
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();
      expect(source.contains("if (place != null) 'p_place': place"), isTrue);
    });

    test('StoryFinalizeResult surfaces existing for idempotent retries', () {
      const result = StoryFinalizeResult(storyId: 'story-1', existing: true);
      expect(result.storyId, 'story-1');
      expect(result.existing, isTrue);
    });
  });

  group('timeout', () {
    test('every RPC/storage call in the repository is bounded', () {
      // Checklist 1.2, matching snakes_service.dart: without a bound, a
      // stalled connection leaves the poster staring at a spinner that
      // never resolves.
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      expect(source.contains('.timeout('), isTrue);
      expect(source.contains('Duration(seconds: 30)'), isTrue);
    });
  });

  group('failure kinds (Wave 2, P1)', () {
    StoryApiError storage(int status, String body) => StoryApiError.fromFailure(
      ChatMediaUploader.storageExceptionFor(status, body),
    );

    test('transport failures are offline and never a server refusal', () {
      for (final error in <Object>[
        const SocketException('no route'),
        TimeoutException('upload stalled (body)'),
        http.ClientException('Connection closed'),
        AuthRetryableFetchException(message: 'offline'),
      ]) {
        final mapped = StoryApiError.fromFailure(error);
        expect(mapped.kind, StoryFailureKind.offline, reason: '$error');
        expect(mapped.code, StoryErrorCodes.network);
        expect(mapped.retryable, isTrue);
      }
    });

    test('Storage refusals are read from the body status, as chat does', () {
      // Storage answers RLS/duplicate/size as HTTP 400 with the real code in
      // the JSON body (chat_media_uploader.dart storageExceptionFor).
      expect(
        storage(400, '{"statusCode":"403","error":"Unauthorized",'
            '"message":"new row violates row-level security policy"}').kind,
        StoryFailureKind.intentStale,
      );
      expect(
        storage(400, '{"statusCode":"409","error":"Duplicate",'
            '"message":"The resource already exists"}').kind,
        StoryFailureKind.alreadyUploaded,
      );
      final tooLarge = storage(400, '{"statusCode":"413","error":"Payload too large",'
          '"message":"The object exceeded the maximum allowed size"}');
      expect(tooLarge.kind, StoryFailureKind.mediaRejected);
      expect(tooLarge.code, StoryErrorCodes.mediaTooLarge);
      final mime = storage(400, '{"statusCode":"415","error":"invalid_mime_type",'
          '"message":"mime type video/quicktime is not supported"}');
      expect(mime.code, StoryErrorCodes.mediaTypeRejected);
      expect(storage(503, 'upstream down').kind, StoryFailureKind.offline);
      expect(storage(408, '').kind, StoryFailureKind.offline);
      expect(storage(401, '{"statusCode":"401","message":"jwt expired"}').kind,
          StoryFailureKind.offline);
      expect(storage(429, '').kind, StoryFailureKind.rateLimited);
      expect(storage(400, '{"statusCode":"400","message":"weird"}').kind,
          StoryFailureKind.unknown);
    });

    test('a missing local file is media_missing, never a network retry', () {
      for (final error in <Object>[
        const ChatImageRejectedSignal('media_missing'),
        const FileSystemException('gone', '/tmp/x.jpg'),
        const PathNotFoundException('/tmp/x.jpg', OSError('No such file', 2)),
      ]) {
        final mapped = StoryApiError.fromFailure(error);
        expect(mapped.kind, StoryFailureKind.mediaMissing, reason: '$error');
        expect(mapped.code, StoryErrorCodes.mediaMissing);
      }
    });

    test('a cancelled upload is cancelled', () {
      expect(
        StoryApiError.fromFailure(const ChatUploadCancelled()).kind,
        StoryFailureKind.cancelled,
      );
    });

    test('an unexpected server or auth error has an unknown shape', () {
      expect(
        // Fix round 1: a real server rejection carries a code (here a
        // PL/pgSQL RAISE). A code-less PostgrestException is transport-
        // shaped and offline, as chat classes it (see the PostgREST test).
        StoryApiError.fromFailure(
          const PostgrestException(message: 'boom', code: 'P0001'),
        ).kind,
        StoryFailureKind.unknown,
      );
      expect(
        StoryApiError.fromFailure(const AuthException('refresh token revoked')).kind,
        StoryFailureKind.unknown,
      );
      expect(StoryApiError.fromFailure(StateError('bug')).kind,
          StoryFailureKind.unknown);
    });

    test('server codes keep their meaning', () {
      expect(StoryApiError.kindForCode('RATE_LIMITED'), StoryFailureKind.rateLimited);
      for (final code in ['UNAUTHORIZED', 'FORBIDDEN', 'INVALID_INPUT', 'UNAVAILABLE']) {
        expect(StoryApiError.kindForCode(code), StoryFailureKind.refused, reason: code);
      }
      // A StoryApiError passes through untouched.
      const refused = StoryApiError(code: 'FORBIDDEN', message: 'm', retryable: false);
      expect(identical(StoryApiError.fromFailure(refused), refused), isTrue);
    });

    test('the copy a person sees never carries an exception', () {
      final mapped = StoryApiError.fromFailure(const SocketException('secret host'));
      expect(mapped.message, isNot(contains('secret host')));
      expect(mapped.toString(), isNot(contains('Exception')));
    });
  });

  group('streamed upload (Wave 2, P1)', () {
    late Directory dir;
    late File file;
    late SupabaseClient client;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('story_upload');
      file = File('${dir.path}/media.jpg')
        ..writeAsBytesSync(List<int>.generate(200 * 1024, (i) => i % 251));
      client = SupabaseClient('http://127.0.0.1:9', 'test-anon-key');
    });
    tearDown(() async {
      await client.dispose();
      await dir.delete(recursive: true);
    });

    StoryRepository repoWith(http.Client httpClient) => StoryRepository(
      client,
      uploader: ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () async => {'Authorization': 'Bearer jwt', 'apikey': 'anon'},
        clientFactory: () => httpClient,
      ),
    );

    test('a 409 on our key surfaces as alreadyUploaded, not network', () async {
      final repo = repoWith(MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          Stream.value(utf8.encode(
            '{"statusCode":"409","error":"Duplicate","message":"exists"}',
          )),
          400,
        );
      }));

      await expectLater(
        repo.uploadObject(
          bucket: 'story-media',
          storageKey: 'rel/k1.jpg',
          localPath: file.path,
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<StoryApiError>().having(
          (e) => e.kind, 'kind', StoryFailureKind.alreadyUploaded,
        )),
      );
    });

    test('reports byte progress and honours a cancel token', () async {
      final seen = <int>[];
      final repo = repoWith(MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      }));
      await repo.uploadObject(
        bucket: 'story-media',
        storageKey: 'rel/k2.jpg',
        localPath: file.path,
        mimeType: 'image/jpeg',
        onProgress: (sent, total) => seen.add(sent),
      );
      expect(seen.last, 200 * 1024);

      final token = ChatUploadCancelToken()..cancel();
      await expectLater(
        repo.uploadObject(
          bucket: 'story-media',
          storageKey: 'rel/k3.jpg',
          localPath: file.path,
          mimeType: 'image/jpeg',
          cancelToken: token,
        ),
        throwsA(isA<StoryApiError>().having(
          (e) => e.kind, 'kind', StoryFailureKind.cancelled,
        )),
      );
    });

    test('a missing file fails as media_missing before any request', () async {
      var requests = 0;
      final repo = repoWith(MockClient.streaming((request, body) async {
        requests++;
        return http.StreamedResponse(const Stream.empty(), 200);
      }));
      await expectLater(
        repo.uploadObject(
          bucket: 'story-media',
          storageKey: 'rel/k4.jpg',
          localPath: '${dir.path}/gone.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<StoryApiError>().having(
          (e) => e.code, 'code', StoryErrorCodes.mediaMissing,
        )),
      );
      expect(requests, 0);
    });
  });

  group('fix round 1: classified as chat classifies', () {
    StoryFailureKind pg(String? code, [String message = 'x']) =>
        StoryApiError.fromFailure(PostgrestException(message: message, code: code))
            .kind;

    test('a PostgREST transport failure is offline, never a strike', () {
      // postgrest turns a gateway 502/503/504 into code '5xx'; PGRST0xx is
      // "cannot reach the database"; PGRST301 is a JWT that expired across
      // a resume; no code at all is transport. Chat: unavailable.
      for (final code in ['502', '503', '504', 'PGRST000', 'PGRST001', 'PGRST301', null]) {
        expect(pg(code, '<html>'), StoryFailureKind.offline, reason: '$code');
      }
      final mapped = StoryApiError.fromFailure(
        const PostgrestException(message: '<html>', code: '503'),
      );
      expect(mapped.code, StoryErrorCodes.network);
      expect(mapped.retryable, isTrue);
      expect(mapped.message, isNot(contains('html')));
    });

    test('a PostgREST rate limit is rateLimited', () {
      expect(pg('429'), StoryFailureKind.rateLimited);
    });

    test('a real server rejection of the request stays unknown (a strike)', () {
      for (final code in ['42883', 'P0001', '22P02', '23503', '400', 'PGRST116', 'PGRST202']) {
        expect(pg(code), StoryFailureKind.unknown, reason: code);
      }
    });

    test('a TLS or raw HTTP failure is offline', () {
      for (final error in <Object>[
        const HandshakeException('x'),
        const TlsException('x'),
        const HttpException('Connection closed before full header was received'),
      ]) {
        final mapped = StoryApiError.fromFailure(error);
        expect(mapped.kind, StoryFailureKind.offline, reason: '$error');
        expect(mapped.code, StoryErrorCodes.network);
      }
    });
  });

  group('upload bearer (mirrors chat "repository bearer")', () {
    late List<http.BaseRequest> authCalls;

    StoryRepository repositoryWith(String accessToken) {
      authCalls = [];
      final supabase = SupabaseClient(
        'https://x.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          authCalls.add(request);
          return http.Response(
            jsonEncode(_sessionJson('fresh-jwt')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(supabase.dispose);
      unawaited(
        supabase.auth.setInitialSession(jsonEncode(_sessionJson(accessToken))),
      );
      return StoryRepository(supabase);
    }

    test('the upload carries the session JWT and the anon apikey', () async {
      final live = _jwt(
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      );
      final repo = repositoryWith(live);
      await Future<void>.delayed(Duration.zero);
      final headers = await repo.debugUploadHeaders();
      expect(headers['Authorization'], 'Bearer $live');
      expect(headers['apikey'], 'anon-key');
      expect(authCalls, isEmpty, reason: 'a live session is not refreshed');
    });

    test('an expired session is refreshed first and the fresh JWT is sent', () async {
      final dead = _jwt(
        DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      );
      final repo = repositoryWith(dead);
      await Future<void>.delayed(Duration.zero);
      final headers = await repo.debugUploadHeaders();
      expect(authCalls, hasLength(1));
      expect(authCalls.single.url.path, endsWith('/token'));
      expect(headers['Authorization'], 'Bearer fresh-jwt');
    });
  });

  group('finalize sends the capture time (Wave 5, 04 #3)', () {
    late List<Map<String, dynamic>> bodies;

    StoryRepository repoAnswering(List<http.Response> answers) {
      bodies = [];
      final queue = [...answers];
      final supabase = SupabaseClient(
        'https://x.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/rpc/create_story_item')) {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            // postgrest reads response.request, which MockClient copies from
            // the answer: re-attach it.
            final answer = queue.removeAt(0);
            return http.Response(
              answer.body,
              answer.statusCode,
              headers: answer.headers,
              request: request,
            );
          }
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(supabase.dispose);
      return StoryRepository(supabase);
    }

    http.Response ok() => http.Response(
      jsonEncode({'story_id': 's1', 'existing': false}),
      200,
      headers: {'content-type': 'application/json'},
    );

    Future<StoryFinalizeResult> finalize(StoryRepository repo) => repo.finalizeStory(
      relationshipId: 'r1',
      clientStoryId: 'c1',
      mediaIntentId: 'm1',
      thumbnailIntentId: 't1',
      mediaWidth: 1080,
      mediaHeight: 1920,
      utcOffsetMinutes: 60,
      capturedAt: DateTime.utc(2026, 10, 23, 22, 59),
    );

    test('p_captured_at is the capture instant in UTC', () async {
      final repo = repoAnswering([ok()]);
      final result = await finalize(repo);
      expect(result.storyId, 's1');
      expect(bodies.single['p_captured_at'], '2026-10-23T22:59:00.000Z');
      expect(bodies.single['p_utc_offset_minutes'], 60);
    });

    test('an older server (PGRST202) is asked again without it, once', () async {
      final repo = repoAnswering([
        http.Response(
          jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.create_story_item', 'details': null, 'hint': null}),
          404,
          headers: {'content-type': 'application/json'},
        ),
        ok(),
        ok(),
      ]);
      expect((await finalize(repo)).storyId, 's1');
      expect(bodies, hasLength(2));
      expect(bodies[0].containsKey('p_client_now'), isTrue);
      expect(bodies[1].containsKey('p_captured_at'), isFalse);
      expect(bodies[1].containsKey('p_client_now'), isFalse,
          reason: 'the two travel together');
      await finalize(repo);
      expect(bodies, hasLength(3));
      expect(bodies[2].containsKey('p_captured_at'), isFalse, reason: 'remembered (for 10 minutes)');
      expect(bodies[2].containsKey('p_client_now'), isFalse);
    });

    // Final review M4: a PGRST202 seen in a deploy's schema-reload window
    // must not stick until the app restarts. Same 10-minute re-probe as the
    // day-items fallback.
    test('after 10 minutes the capture time is sent again, and a success '
        'clears the fallback', () async {
      var now = DateTime.utc(2026, 10, 24, 0, 10);
      final repo = repoAnswering([
        http.Response(
          jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.create_story_item', 'details': null, 'hint': null}),
          404,
          headers: {'content-type': 'application/json'},
        ),
        ok(),
        ok(),
        ok(),
        ok(),
      ]);
      await withClock(Clock(() => now), () async {
        await finalize(repo);
        expect(bodies, hasLength(2));
        expect(bodies[1].containsKey('p_captured_at'), isFalse);

        now = now.add(const Duration(minutes: 9, seconds: 59));
        await finalize(repo);
        expect(bodies[2].containsKey('p_captured_at'), isFalse,
            reason: 'still inside the 10-minute window');

        now = now.add(const Duration(seconds: 1));
        await finalize(repo);
        expect(bodies, hasLength(4), reason: 'one call: the server answered');
        expect(bodies[3]['p_captured_at'], '2026-10-23T22:59:00.000Z');
        expect(bodies[3]['p_client_now'], '2026-10-24T00:20:00.000Z');

        now = now.add(const Duration(seconds: 1));
        await finalize(repo);
        expect(bodies[4].containsKey('p_captured_at'), isTrue,
            reason: 'the success cleared the fallback');
      });
    });

    // Fix round 1 (review #1): the server takes the capture's AGE on the
    // phone's own clock, so the phone's clock travels with the capture.
    test('p_client_now is the phone clock at send: a phone 3 days behind '
        'still says the capture is a minute old', () async {
      final repo = repoAnswering([ok()]);
      final phoneNow = DateTime.utc(2026, 10, 21, 12);
      await withClock(
        Clock.fixed(phoneNow),
        () => repo.finalizeStory(
          relationshipId: 'r1',
          clientStoryId: 'c1',
          mediaIntentId: 'm1',
          thumbnailIntentId: 't1',
          mediaWidth: 1080,
          mediaHeight: 1920,
          utcOffsetMinutes: 0,
          capturedAt: phoneNow.subtract(const Duration(minutes: 1)),
        ),
      );
      final body = bodies.single;
      expect(body['p_client_now'], '2026-10-21T12:00:00.000Z');
      expect(
        DateTime.parse(body['p_client_now'] as String)
            .difference(DateTime.parse(body['p_captured_at'] as String)),
        const Duration(minutes: 1),
      );
    });

    test('no capture time sends neither key', () async {
      final repo = repoAnswering([ok()]);
      await repo.finalizeStory(
        relationshipId: 'r1',
        clientStoryId: 'c1',
        mediaIntentId: 'm1',
        thumbnailIntentId: 't1',
        mediaWidth: 1080,
        mediaHeight: 1920,
        utcOffsetMinutes: 0,
      );
      expect(bodies.single.containsKey('p_captured_at'), isFalse);
      expect(bodies.single.containsKey('p_client_now'), isFalse);
    });

    for (final (status, code) in [(500, 'XX000'), (401, 'PGRST301')]) {
      test('a $status $code answer is not asked again (only PGRST202 is)',
          () async {
        final repo = repoAnswering([
          http.Response(
            jsonEncode({'code': code, 'message': 'no', 'details': null, 'hint': null}),
            status,
            headers: {'content-type': 'application/json'},
          ),
          ok(),
        ]);
        await expectLater(finalize(repo), throwsA(isA<StoryApiError>()));
        expect(bodies, hasLength(1));
      });
    }
  });
}
