// Spec 2 W4b (§3.3.4, S-7, C-6): the Dating client's requests carry the
// install's id as x-attune-device; without an id (or one that can't be
// read) they go as they are, and the server answers reverify_device.
// Fix round 1: the built client's RPC, edge-function and storage requests
// each carry the header, the project key and the session token (I-2); an
// expired session is refreshed before its token is sent (I-1); whether
// this phone has an id at all (I-4).
import 'dart:convert';

import 'package:attune/core/device/install_id.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _id = '0123456789abcdef0123456789abcdef';

/// A JWT whose payload says it expires at [exp] (seconds).
String _jwt(int exp) {
  String part(String json) =>
      base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  return '${part('{"alg":"HS256"}')}.${part('{"exp":$exp,"sub":"u"}')}.sig';
}

Session _session(String token) => Session(
  accessToken: token,
  tokenType: 'bearer',
  user: const User(
    id: 'u',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class _Auth extends Fake implements GoTrueClient {
  _Auth(this.session, {this.refreshed, this.fails = false});
  Session? session;
  final Session? refreshed;
  final bool fails;
  var refreshes = 0;

  @override
  Session? get currentSession => session;

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async {
    refreshes++;
    await Future<void>.delayed(Duration.zero);
    if (fails) throw const AuthException('refresh failed');
    session = refreshed;
    return AuthResponse(session: refreshed);
  }
}

class _Broken extends FlutterSecureStorage {
  const _Broken();
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(StateError('keystore'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, String>> sent(Future<String?> Function() id) async {
    late Map<String, String> headers;
    final client = DatingDeviceHttpClient(
      id,
      MockClient((request) async {
        headers = request.headers;
        return http.Response('{}', 200);
      }),
    );
    await client.get(Uri.parse('https://example.test/rest/v1/rpc/x'));
    return headers;
  }

  test('the id rides on every request', () async {
    expect((await sent(() async => _id))[datingDeviceHeader], _id);
    expect(datingDeviceHeader, 'x-attune-device');
  });

  test('no id: no header', () async {
    expect(
      (await sent(() async => null)).containsKey(datingDeviceHeader),
      isFalse,
    );
  });

  test(
    'an id that cannot be read: no header, the request still goes',
    () async {
      expect(
        (await sent(
          () => Future.error(StateError('keystore')),
        )).containsKey(datingDeviceHeader),
        isFalse,
      );
    },
  );

  group('fix round 1 (I-2): the built client', () {
    test('an RPC, an edge function and a storage download each carry the '
        'header, the project key and the session token', () async {
      final seen = <String, Map<String, String>>{};
      final client = datingSupabaseClient(
        url: 'https://project.example.test',
        key: 'anon-key',
        deviceId: () async => _id,
        accessToken: () async => 'session-token',
        inner: MockClient((request) async {
          seen[request.url.path] = request.headers;
          if (request.url.path.startsWith('/storage/')) {
            return http.Response.bytes([1, 2, 3], 200, request: request);
          }
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await client.rpc('get_dating_home');
      await client.functions.invoke('dating-verification', body: {'a': 1});
      await client.storage.from('b').download('k.jpg');
      expect(seen.keys, [
        '/rest/v1/rpc/get_dating_home',
        '/functions/v1/dating-verification',
        '/storage/v1/object/b/k.jpg',
      ]);
      for (final entry in seen.entries) {
        expect(entry.value[datingDeviceHeader], _id, reason: entry.key);
        expect(entry.value['apikey'], 'anon-key', reason: entry.key);
        expect(
          entry.value['Authorization'],
          'Bearer session-token',
          reason: entry.key,
        );
      }
    });
  });

  group('fix round 1 (I-1): the session token', () {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('a fresh session: its token, no refresh', () async {
      final auth = _Auth(_session(_jwt(now + 3600)));
      expect(await datingAccessToken(auth), auth.session!.accessToken);
      expect(auth.refreshes, 0);
    });

    test('an expired session is refreshed before its token is sent', () async {
      final fresh = _session(_jwt(now + 3600));
      final auth = _Auth(_session(_jwt(now - 60)), refreshed: fresh);
      expect(await datingAccessToken(auth), fresh.accessToken);
      expect(auth.refreshes, 1);
    });

    test('a refresh that fails: the current token, so the server answers '
        '401 as it would the app\'s own client', () async {
      final stale = _session(_jwt(now - 60));
      final auth = _Auth(stale, fails: true);
      expect(await datingAccessToken(auth), stale.accessToken);
      expect(auth.refreshes, 1);
    });

    test('signed out: no token, no refresh', () async {
      final auth = _Auth(null);
      expect(await datingAccessToken(auth), isNull);
      expect(auth.refreshes, 0);
    });
  });

  group('fix round 1 (I-4): whether this phone has an id', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('an id: ready', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(datingDeviceReadyProvider, (_, _) {});
      expect(await c.read(datingDeviceReadyProvider.future), isTrue);
    });

    test('a keystore that fails: not ready', () async {
      final c = ProviderContainer(
        overrides: [
          installIdStoreProvider.overrideWithValue(
            InstallIdStore(storage: const _Broken()),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(datingDeviceReadyProvider, (_, _) {});
      expect(await c.read(datingDeviceReadyProvider.future), isFalse);
    });
  });
}
