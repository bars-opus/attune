import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, StorageException, SupabaseClient;

/// Accepts the request body (so progress fires) but never answers until
/// closed, which is what cancelling does to it.
class _HangingClient extends http.BaseClient {
  final _completer = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    unawaited(request.finalize().drain<void>());
    return _completer.future;
  }

  @override
  void close() {
    closed = true;
    if (!_completer.isCompleted) {
      _completer.completeError(http.ClientException('Connection closed'));
    }
  }
}

/// A socket that takes no bytes at all: the body is never read and no
/// answer ever comes (until the client is closed).
class _DeafClient extends http.BaseClient {
  final _completer = Completer<http.StreamedResponse>();
  bool closed = false;
  int closeCalls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.finalize();
    return _completer.future;
  }

  @override
  void close() {
    closeCalls++;
    closed = true;
    if (!_completer.isCompleted) {
      _completer.completeError(http.ClientException('Connection closed'));
    }
  }
}

/// An unsigned JWT whose `exp` is [exp] (seconds since epoch).
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
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uploader');
    file = File('${dir.path}/clip.mp4')
      ..writeAsBytesSync(List<int>.generate(300 * 1024, (i) => i % 251));
  });
  tearDown(() => dir.delete(recursive: true));

  ChatMediaUploader uploader(http.Client client) => ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () async => {'Authorization': 'Bearer jwt', 'apikey': 'anon'},
        clientFactory: () => client,
      );

  test('POSTs the raw bytes to the object endpoint with storage headers',
      () async {
    http.BaseRequest? seen;
    var received = 0;
    final client = MockClient.streaming((request, body) async {
      seen = request;
      received = (await body.toBytes()).length;
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"Key":"message-media/k"}')), 200);
    });

    await uploader(client).upload(
      bucket: 'message-media',
      objectKey: 'chat-media/abc.mp4',
      localPath: file.path,
      mimeType: 'video/mp4',
    );

    expect(seen!.method, 'POST');
    expect(seen!.url.toString(),
        'https://x.supabase.co/storage/v1/object/message-media/chat-media/abc.mp4');
    expect(seen!.headers['Authorization'], 'Bearer jwt');
    expect(seen!.headers['apikey'], 'anon');
    expect(seen!.headers['content-type'], 'video/mp4');
    expect(seen!.headers['x-upsert'], 'false');
    expect(seen!.contentLength, 300 * 1024);
    expect(received, 300 * 1024);
  });

  test('reports monotonic progress up to the full length', () async {
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    final seen = <int>[];
    await uploader(client).upload(
      bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'audio/mp4',
      onProgress: (sent, total) {
        expect(total, 300 * 1024);
        seen.add(sent);
      },
    );
    expect(seen, isNotEmpty);
    expect(seen.last, 300 * 1024);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('a non-2xx reply becomes a StorageException with that status', () async {
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"Payload too large"}')), 413);
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'image/jpeg'),
      throwsA(isA<StorageException>().having((e) => e.statusCode, 'status', '413')),
    );
  });

  test('a 503 keeps its status too (retryable upstream)', () async {
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('down')), 503);
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'image/jpeg'),
      throwsA(isA<StorageException>().having((e) => e.statusCode, 'status', '503')),
    );
  });

  test('cancel aborts the request and surfaces ChatUploadCancelled', () async {
    final client = _HangingClient();
    final token = ChatUploadCancelToken();
    var progressed = Completer<void>();
    final future = uploader(client).upload(
      bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
      cancelToken: token,
      onProgress: (sent, total) {
        if (!progressed.isCompleted) progressed.complete();
      },
    );
    await progressed.future;
    token.cancel();
    await expectLater(future, throwsA(isA<ChatUploadCancelled>()));
    expect(client.closed, isTrue);
  });

  test('a token cancelled before the upload starts short-circuits', () async {
    final token = ChatUploadCancelToken()..cancel();
    var sent = false;
    final client = MockClient.streaming((request, body) async {
      sent = true;
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
          cancelToken: token),
      throwsA(isA<ChatUploadCancelled>()),
    );
    expect(sent, isFalse);
  });

  test('a prepared file that is gone fails at once as a media rejection (M8)',
      () async {
    var requests = 0;
    final client = MockClient.streaming((request, body) async {
      requests++;
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    Object? caught;
    try {
      await uploader(client).upload(
          bucket: 'b',
          objectKey: 'k',
          localPath: '${dir.path}/swept.mp4',
          mimeType: 'video/mp4');
    } catch (error) {
      caught = error;
    }
    expect(caught, isA<ChatImageRejectedSignal>());
    expect(requests, 0, reason: 'nothing is sent for a file that is gone');
    final error = ChatError.from(caught, mediaType: 'video');
    expect(error.category, ChatErrorCategory.mediaRejected,
        reason: 'not unknown: retrying a missing file can never succeed');
    expect(error.isPermanent, isTrue);
    expect(error.toUserMessage(),
        'That video could not be sent. Try a different one.');
  });

  test('a dropped socket is a ClientException (classified offline upstream)',
      () async {
    final client = MockClient.streaming((request, body) async {
      throw http.ClientException('Connection reset');
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4'),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('the repository signs the streamed upload with the session JWT, not the anon key',
      () {
    // storage.headers holds only the apikey; the SDK's AuthHttpClient adds
    // the person's bearer per request. Bypassing that client without doing
    // the same makes every media upload an anonymous one (Storage RLS 403,
    // which Task 5 rightly calls permanent).
    final src = File(
      'lib/features/chat/data/repositories/supabase_chat_repository.dart',
    ).readAsStringSync();
    final headers = src.substring(src.indexOf('_uploadHeaders() async {'));
    final beforeReturn = headers.substring(0, headers.indexOf('return {'));
    expect(beforeReturn, contains('currentSession?.isExpired'));
    expect(beforeReturn, contains('refreshSession()'));
    expect(beforeReturn, contains('currentSession?.accessToken'));
    expect(headers, contains("'Authorization': 'Bearer \$token'"));
  });

  group('stall bounds (a hung upload never sits in "sending")', () {
    ChatMediaUploader bounded(
      http.Client client, {
      Duration idle = const Duration(milliseconds: 120),
      Duration response = const Duration(milliseconds: 120),
    }) => ChatMediaUploader(
      storageUrl: () => 'https://x.supabase.co/storage/v1',
      headers: () async => {'Authorization': 'Bearer jwt', 'apikey': 'anon'},
      clientFactory: () => client,
      idleTimeout: idle,
      responseTimeout: response,
    );

    test('a socket that accepts no bytes fails within the bound, retryably',
        () async {
      final client = _DeafClient();
      final watch = Stopwatch()..start();
      await expectLater(
        bounded(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4'),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(client.closed, isTrue, reason: 'the stalled socket is torn down');
    });

    test('a server that takes the body but never answers fails within the bound',
        () async {
      final client = _HangingClient();
      final watch = Stopwatch()..start();
      // A long idle bound, so only the response bound can end this.
      await expectLater(
        bounded(client, idle: const Duration(seconds: 30)).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4'),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(client.closed, isTrue);
    });

    test('a slow body that keeps moving is not a stall', () async {
      // Each chunk lands well inside the idle bound, the whole body takes
      // far longer than it: inactivity, not total time, is what is bounded.
      // M6: ~6x margin per chunk (60 ms vs 400 ms), and ~20 chunks (64 KB
      // reads of 1.25 MB) so the body still outlasts the bound threefold.
      final big = File('${dir.path}/long.mp4')
        ..writeAsBytesSync(List<int>.generate(1280 * 1024, (i) => i % 251));
      var chunks = 0;
      final client = MockClient.streaming((request, body) async {
        await body
            .asyncMap((chunk) async {
              chunks++;
              await Future<void>.delayed(const Duration(milliseconds: 60));
              return chunk;
            })
            .drain<void>();
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      });
      const idle = Duration(milliseconds: 400);
      final watch = Stopwatch()..start();
      await bounded(client, idle: idle).upload(
        bucket: 'b', objectKey: 'k', localPath: big.path, mimeType: 'video/mp4');
      expect(chunks, greaterThanOrEqualTo(15));
      expect(watch.elapsed, greaterThan(idle),
          reason: 'the whole body took longer than the idle bound');
    });

    test('a cancel after a stall timed out changes nothing', () async {
      final client = _DeafClient();
      final token = ChatUploadCancelToken();
      await expectLater(
        bounded(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
          cancelToken: token),
        throwsA(isA<TimeoutException>()),
      );
      expect(token.debugListenerCount, 0,
          reason: 'the settled upload no longer listens to the token');
      final closes = client.closeCalls;
      token.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.closeCalls, closes, reason: 'nothing left to abort');
      expect(token.isCancelled, isTrue);
    });

    test('the default bounds: 20 s without a byte, 60 s for the answer', () {
      final defaults = ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () async => const {},
      );
      expect(chatUploadStallTimeout, const Duration(seconds: 20));
      expect(chatUploadResponseTimeout, const Duration(seconds: 60));
      expect(defaults.idleTimeout, chatUploadStallTimeout);
      expect(defaults.responseTimeout, chatUploadResponseTimeout);
    });

    test('headers that never come (a hung session refresh) time out', () async {
      var clients = 0;
      final uploader = ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () => Completer<Map<String, String>>().future,
        clientFactory: () {
          clients++;
          return _DeafClient();
        },
        idleTimeout: const Duration(milliseconds: 120),
      );
      final watch = Stopwatch()..start();
      await expectLater(
        uploader.upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4'),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(clients, 0);
    });

    test('a cancel while the headers are pending settles at once', () async {
      var clients = 0;
      final token = ChatUploadCancelToken();
      final uploader = ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () => Completer<Map<String, String>>().future,
        clientFactory: () {
          clients++;
          return _DeafClient();
        },
      );
      final future = uploader.upload(
        bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
        cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final watch = Stopwatch()..start();
      token.cancel();
      await expectLater(future, throwsA(isA<ChatUploadCancelled>()));
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(clients, 0);
      expect(token.debugListenerCount, 0);
    });

    test('a malformed storage URL leaks no client and no listener', () async {
      var clients = 0;
      final token = ChatUploadCancelToken();
      final uploader = ChatMediaUploader(
        storageUrl: () => 'http://[::1',
        headers: () async => const {},
        clientFactory: () {
          clients++;
          return _DeafClient();
        },
      );
      await expectLater(
        uploader.upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
          cancelToken: token),
        throwsA(isA<FormatException>()),
      );
      expect(clients, 0);
      expect(token.debugListenerCount, 0);
    });
  });

  group('storage error bodies decode like storage_client 2.5.5', () {
    // Storage answers many refusals as HTTP 400 with the real code only in
    // the JSON body; the SDK's StorageException.fromJson prefers it.
    Future<StorageException> failure(int status, String body) async {
      final client = MockClient.streaming((request, stream) async {
        await stream.drain<void>();
        return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
      });
      try {
        await uploader(client).upload(
            bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4');
      } on StorageException catch (error) {
        return error;
      }
      fail('expected a StorageException');
    }

    String body(String code, String message) =>
        jsonEncode({'statusCode': code, 'error': 'x', 'message': message});

    test('HTTP 400 carrying "403" counts toward the cap and is retried',
        () async {
      final error = await failure(
          400, body('403', 'new row violates row-level security policy'));
      expect(error.statusCode, '403');
      expect(error.message, 'new row violates row-level security policy');
      final classified = ChatError.from(error, mediaType: 'video');
      expect(classified.category, ChatErrorCategory.unknown,
          reason: 'unknown is the category that counts toward the cap');
      expect(classified.isPermanent, isFalse);
      expect(classified.isTransient, isTrue);
    });

    test('HTTP 400 carrying "413" shows the size copy', () async {
      final error = await failure(400, body('413', 'The object exceeded the maximum allowed size'));
      expect(error.statusCode, '413');
      expect(
        ChatError.from(error, mediaType: 'video').toUserMessage(),
        'That video is too large to send — try a shorter clip.',
      );
    });

    test('HTTP 400 carrying "409" or "401" is retryable', () async {
      for (final code in ['409', '401']) {
        final error = await failure(400, body(code, 'nope'));
        expect(error.statusCode, code);
        final classified = ChatError.from(error);
        expect(classified.category, ChatErrorCategory.unavailable);
        expect(classified.isPermanent, isFalse);
      }
    });

    test('a non-JSON 502 keeps its HTTP status and is retryable', () async {
      final error = await failure(502, '<html>Bad Gateway</html>');
      expect(error.statusCode, '502');
      expect(error.message, '<html>Bad Gateway</html>');
      expect(ChatError.from(error).category, ChatErrorCategory.unavailable);
    });

    test('a JSON body that is not an object falls back to the HTTP status',
        () async {
      final error = await failure(400, '["odd"]');
      expect(error.statusCode, '400');
      expect(error.message, '["odd"]');
    });
  });

  group('repository bearer', () {
    late List<http.BaseRequest> authCalls;

    SupabaseChatRepository repositoryWith(String accessToken) {
      authCalls = [];
      final supabase = SupabaseClient(
        'https://x.supabase.co',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          authCalls.add(request);
          return http.Response(jsonEncode(_sessionJson('fresh-jwt')), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(supabase.dispose);
      unawaited(
        supabase.auth.setInitialSession(jsonEncode(_sessionJson(accessToken))),
      );
      return SupabaseChatRepository(supabase);
    }

    test('the upload carries the session JWT and the anon apikey', () async {
      final live =
          _jwt(DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000);
      final repo = repositoryWith(live);
      await Future<void>.delayed(Duration.zero);
      final headers = await repo.debugUploadHeaders();
      expect(headers['Authorization'], 'Bearer $live');
      expect(headers['apikey'], 'anon-key');
      expect(authCalls, isEmpty, reason: 'a live session is not refreshed');
    });

    test('an expired session is refreshed first and the fresh JWT is sent',
        () async {
      final dead = _jwt(
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000);
      final repo = repositoryWith(dead);
      await Future<void>.delayed(Duration.zero);
      final headers = await repo.debugUploadHeaders();
      expect(authCalls, hasLength(1));
      expect(authCalls.single.url.path, endsWith('/token'));
      expect(headers['Authorization'], 'Bearer fresh-jwt');
    });
  });
}
