// Spec 2 W6a Task 3 fix round 1 (I-1): the Dating client's realtime is
// signed in as the person. The client signs its requests in through its own
// accessToken callback, so supabase never hands its realtime the session
// (it would join every channel with the project key, and never refresh).
// The client the provider builds forwards the app's session token to
// realtime now and on each sign-in, refresh and sign-out; closing it stops.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session _session(String token) => Session(
  accessToken: token,
  tokenType: 'bearer',
  user: const User(
    id: 'ama',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class _Auth extends Fake implements GoTrueClient {
  _Auth(this.session);
  Session? session;
  final events = StreamController<AuthState>.broadcast();

  @override
  Session? get currentSession => session;

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  Future<void> emit(AuthChangeEvent event, Session? next) async {
    session = next;
    events.add(AuthState(event, next));
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({SupabaseClient client, void Function() close}) build(_Auth auth) =>
      datingAppClient(
        url: 'http://127.0.0.1:9',
        key: 'anon-key',
        deviceId: () async => null,
        auth: auth,
      );

  test('the bare client joins realtime with the project key (why the '
      'forwarding exists)', () async {
    final bare = datingSupabaseClient(
      url: 'http://127.0.0.1:9',
      key: 'anon-key',
      deviceId: () async => null,
      accessToken: () async => 'user-token',
    );
    addTearDown(bare.dispose);
    expect(bare.realtime.accessToken, 'anon-key');
  });

  test('the chat channel joins with the person\'s token and follows a '
      'refresh, a sign-out and the next sign-in', () async {
    final auth = _Auth(_session('token-1'));
    final built = build(auth);
    addTearDown(built.close);
    final realtime = built.client.realtime;
    expect(realtime.accessToken, 'token-1');

    final signals = DatingChatRepository(
      DatingRpc.withCall((fn, params) async => null),
      built.client,
    ).signals('ama').listen((_) {});
    addTearDown(signals.cancel);
    final channel = built.client.getChannels().single;
    // ignore: invalid_use_of_internal_member
    Object? joinToken() => channel.joinPush.payload['access_token'];
    expect(joinToken(), 'token-1');

    await auth.emit(AuthChangeEvent.tokenRefreshed, _session('token-2'));
    expect(realtime.accessToken, 'token-2');
    expect(joinToken(), 'token-2');

    await auth.emit(AuthChangeEvent.signedOut, null);
    expect(realtime.accessToken, 'anon-key');
    expect(joinToken(), 'anon-key');

    await auth.emit(AuthChangeEvent.signedIn, _session('esi-token'));
    expect(realtime.accessToken, 'esi-token');
    expect(joinToken(), 'esi-token');

    await auth.emit(AuthChangeEvent.userUpdated, _session('ignored'));
    expect(realtime.accessToken, 'esi-token');
  });

  test(
    'signed out at build: the project key; closing stops forwarding',
    () async {
      final auth = _Auth(null);
      final built = build(auth);
      expect(built.client.realtime.accessToken, 'anon-key');
      expect(auth.events.hasListener, isTrue);
      built.close();
      await Future<void>.delayed(Duration.zero);
      expect(auth.events.hasListener, isFalse);
    },
  );

  test('REST, functions and storage are unchanged: the device header and '
      'the app session\'s token ride on an RPC', () async {
    final auth = _Auth(_session('rest-token'));
    late Map<String, String> headers;
    final built = datingAppClient(
      url: 'http://127.0.0.1:9',
      key: 'anon-key',
      deviceId: () async => 'device-id',
      auth: auth,
      inner: MockClient((request) async {
        headers = request.headers;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(built.close);
    await built.client.rpc('get_dating_home');
    expect(headers[datingDeviceHeader], 'device-id');
    expect(headers['apikey'], 'anon-key');
    expect(headers['Authorization'], 'Bearer rest-token');
  });
}
