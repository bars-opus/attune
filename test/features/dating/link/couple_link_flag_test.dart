// Spec 2 W9 fix round 1 (the controller's addition to R-W9-16; review
// M-7): the couple link learns dating_couple_link from ONE get_dating_home
// read per account on Dating's own client, kept for the process. It never
// builds the manual's documentationFlagsProvider (about ten flag reads, re-
// read on every resume), a resume reads nothing, a failed read is off and
// is asked again later, and with the flag off nothing else is asked. Final
// client fix: the couple side's calls go on the app's client too, with no
// install id (I-1), and a flag read that hangs fails (M-2).
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/feature_flag_refresher.dart';
import 'package:attune/core/flags/couple_link_couple_side.dart';
import 'package:attune/core/flags/couple_link_flag.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show supabaseClientProvider;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every provider built, by name or type (documentationFlagsProvider has no
/// name: matched by identity).
class _Built extends ProviderObserver {
  final built = <ProviderBase<Object?>>[];

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) => built.add(provider);
}

/// Final client fix (M-2): a get_dating_home that never answers.
const _hang = #hang;

class _Server {
  _Server(this.home);

  /// get_dating_home's answer; a [Exception] is thrown instead.
  Object? home;
  final calls = <String>[];

  /// Final client fix (I-1): the calls that went on Dating's client.
  final datingCalls = <String>[];

  Future<dynamic> dating(String fn, Map<String, dynamic>? params) {
    datingCalls.add(fn);
    return call(fn, params);
  }

  Future<dynamic> call(String fn, Map<String, dynamic>? params) async {
    calls.add(fn);
    if (fn == 'get_dating_home') {
      final h = home;
      if (h is Exception) throw h;
      if (identical(h, _hang)) return Completer<Object?>().future;
      return h;
    }
    return switch (fn) {
      'get_dating_post_link_offer' => {'ok': true, 'offer': null},
      'get_dating_link_origin' => {'ok': false},
      'get_how_we_met' => {'ok': false},
      _ => {'ok': false, 'reason': 'invalid'},
    };
  }

  int count(String fn) => calls.where((c) => c == fn).length;
}

final _account = StateProvider<String?>((ref) => 'ama');

/// The phone's connection, as the test sets it.
late StreamController<bool> _online;

(ProviderContainer, _Built) _container(_Server server) {
  final built = _Built();
  _online = StreamController<bool>.broadcast();
  addTearDown(_online.close);
  final container = ProviderContainer(
    observers: [built],
    overrides: [
      datingAccountProvider.overrideWith((ref) => ref.watch(_account)),
      datingRpcProvider.overrideWithValue(DatingRpc.withCall(server.dating)),
      // Fix round 2 (M-7): the flag read is the app client's, not Dating's.
      coupleLinkFlagReadProvider.overrideWithValue(
        () => server.call('get_dating_home', null),
      ),
      // Final client fix (I-1): so are the couple side's calls.
      coupleLinkCoupleCallProvider.overrideWithValue(server.call),
      datingOnlineProvider.overrideWith((ref) => _online.stream),
    ],
  );
  addTearDown(container.dispose);
  return (container, built);
}

/// What a couple's Relationship home and About us watch, kept read.
Future<void> _home(ProviderContainer c) async {
  final account = c.read(datingAccountProvider);
  c.listen(datingPostLinkOfferProvider(account), (_, _) {});
  c.listen(datingLinkOriginProvider((account, 'rel-1')), (_, _) {});
  c.listen(datingHowWeMetProvider((account, 'rel-1')), (_, _) {});
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await c.read(datingPostLinkOfferProvider(account).future);
  await c.read(datingLinkOriginProvider((account, 'rel-1')).future);
  await c.read(datingHowWeMetProvider((account, 'rel-1')).future);
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The app goes to the background and comes back.
Future<void> _resume() async {
  final binding = TestWidgetsFlutterBinding.instance;
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(state);
  }
  await _settle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (what, home, on) in [
    ('on', <String, Object?>{'state': 'active', 'couple_link': true}, true),
    ('off', <String, Object?>{'state': 'active'}, false),
    ('a non-object', 'odd', false),
    ('an error', Exception('down'), false),
  ]) {
    test('a couple home + About us cold load: one get_dating_home, the '
        'manual\'s flags never read ($what)', () async {
      final server = _Server(home);
      final (c, built) = _container(server);
      await _home(c);
      expect(c.read(datingCoupleLinkOnProvider), on);
      expect(server.count('get_dating_home'), 1);
      expect(
        built.built.where((p) => identical(p, documentationFlagsProvider)),
        isEmpty,
        reason: 'no feature_flags reads',
      );
      final asked = on ? 1 : 0;
      expect(server.count('get_dating_post_link_offer'), asked);
      expect(server.count('get_dating_link_origin'), asked);
      expect(server.count('get_how_we_met'), asked);
      expect(server.datingCalls, isEmpty, reason: "nothing on Dating's client");
    });
  }

  test('a resume reads nothing more; another account reads once', () async {
    final server = _Server({'state': 'active', 'couple_link': true});
    final (c, _) = _container(server);
    await _home(c);
    for (final p in refreshedFlagProviders) {
      c.invalidate(p);
    }
    await _home(c);
    expect(server.count('get_dating_home'), 1);
    expect(c.read(datingCoupleLinkOnProvider), isTrue);
    c.read(_account.notifier).state = 'kofi';
    await _home(c);
    expect(server.count('get_dating_home'), 2);
    c.read(_account.notifier).state = null;
    await Future<void>.delayed(Duration.zero);
    expect(c.read(datingCoupleLinkOnProvider), isFalse);
    expect(server.count('get_dating_home'), 2);
  });

  test('kept for the process once it answers; a failed read is asked '
      'again by the next screen', () async {
    final server = _Server(Exception('down'));
    final (c, _) = _container(server);
    var sub = c.listen(datingCoupleLinkOnProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sub.read(), isFalse);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    server.home = {'state': 'active', 'couple_link': true};
    sub = c.listen(datingCoupleLinkOnProvider, (_, _) {});
    await c.read(datingCoupleLinkReadProvider('ama').future);
    expect(sub.read(), isTrue);
    expect(server.count('get_dating_home'), 2);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    server.home = {'state': 'active'};
    sub = c.listen(datingCoupleLinkOnProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(sub.read(), isTrue, reason: 'an answer is kept');
    expect(server.count('get_dating_home'), 2);
    sub.close();
  });

  // Fix round 2 (I-1): the home's tabs stay mounted, so a failed read would
  // hold for the whole session. It is asked again on the next resume or
  // reconnect, only while it has failed.
  test('a failed read is asked again on resume: the card appears', () async {
    final server = _Server(Exception('down'));
    final (c, _) = _container(server);
    await _home(c);
    expect(c.read(datingCoupleLinkOnProvider), isFalse);
    expect(server.count('get_dating_post_link_offer'), 0);
    server.home = {'state': 'active', 'couple_link': true};
    await _resume();
    await _home(c);
    expect(server.count('get_dating_home'), 2);
    expect(c.read(datingCoupleLinkOnProvider), isTrue);
    expect(server.count('get_dating_post_link_offer'), 1);
    await _resume();
    await _resume();
    expect(server.count('get_dating_home'), 2, reason: 'answered: kept');
  });

  test('a failed read is asked again on reconnect', () async {
    final server = _Server(Exception('offline'));
    final (c, _) = _container(server);
    await _home(c);
    _online.add(false);
    await _settle();
    expect(server.count('get_dating_home'), 1);
    server.home = {'state': 'active', 'couple_link': true};
    _online.add(true);
    await _settle();
    await _home(c);
    expect(server.count('get_dating_home'), 2);
    expect(c.read(datingCoupleLinkOnProvider), isTrue);
    _online.add(false);
    _online.add(true);
    await _settle();
    expect(server.count('get_dating_home'), 2, reason: 'answered: kept');
  });

  test('after an answer, a resume makes no call', () async {
    final server = _Server({'state': 'active'});
    final (c, _) = _container(server);
    await _home(c);
    await _resume();
    await _resume();
    await _home(c);
    expect(server.count('get_dating_home'), 1);
  });

  // Fix round 2 (M-7; S-7, R15): the flag read is the app client's and
  // sends no install id; Dating's own reads keep theirs.
  test('the flag read sends no device header', () async {
    final requests = <http.BaseRequest>[];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'state': 'not_started', 'couple_link': true}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final container = ProviderContainer(
      overrides: [
        datingAccountProvider.overrideWithValue('ama'),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    container.listen(datingCoupleLinkOnProvider, (_, _) {});
    expect(
      await container.read(datingCoupleLinkReadProvider('ama').future),
      isTrue,
    );
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/get_dating_home');
    expect(
      requests.single.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('x-attune-device')),
    );
  });

  // Final client fix (M-2): a flag read that never answers (a captive
  // portal, a stalled connection) fails after kCoupleLinkReadTimeout, so it
  // is asked again on the next resume, as any failed read.
  testWidgets('a flag read that hangs fails at the timeout and is asked '
      'again on resume', (t) async {
    final server = _Server(_hang);
    final (c, _) = _container(server);
    final sub = c.listen(datingCoupleLinkOnProvider, (_, _) {});
    addTearDown(sub.close);
    await t.pump();
    expect(server.count('get_dating_home'), 1);
    await t.pump(kCoupleLinkReadTimeout - const Duration(seconds: 1));
    expect(c.read(datingCoupleLinkReadProvider('ama')).isLoading, isTrue);
    await t.pump(const Duration(seconds: 2));
    expect(c.read(datingCoupleLinkReadProvider('ama')).valueOrNull, isFalse);
    server.home = {'state': 'active', 'couple_link': true};
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
    }
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));
    expect(server.count('get_dating_home'), 2);
    expect(sub.read(), isTrue);
  });

  // Final client fix (I-1; S-7, R15): the couple side's four requests (the
  // Relationship home's card, its dismiss, the match date and How we met)
  // go on the app's client with no install id; the chat side's link page
  // read, on Dating's client, carries it (so this harness would see it).
  test('the couple side sends no device header; the chat side does', () async {
    final requests = <http.BaseRequest>[];
    Object? answer(String fn) => switch (fn) {
      'get_dating_home' => {'state': 'not_started', 'couple_link': true},
      'get_dating_post_link_offer' => {'ok': true, 'offer': 'linked'},
      'dismiss_dating_post_link_offer' => {'ok': true},
      'get_dating_link_origin' => {
        'ok': true,
        'matched_at': '2026-05-01T10:00:00Z',
      },
      'get_how_we_met' => {
        'ok': true,
        'items': [
          {'mine': true, 'text': 'Hi', 'at': '2026-05-01T10:00:00Z'},
        ],
      },
      _ => {'ok': false, 'reason': 'invalid'},
    };
    final mock = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(answer(request.url.pathSegments.last)),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    const url = 'http://localhost:54321';
    const key = 'test-anon-key';
    final app = SupabaseClient(
      url,
      key,
      httpClient: mock,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final dating = datingSupabaseClient(
      url: url,
      key: key,
      deviceId: () async => 'phone-1',
      accessToken: () async => null,
      inner: mock,
    );
    final container = ProviderContainer(
      overrides: [
        datingAccountProvider.overrideWithValue('ama'),
        supabaseClientProvider.overrideWithValue(app),
        datingSupabaseClientProvider.overrideWithValue(dating),
      ],
    );
    addTearDown(container.dispose);
    container.listen(datingCoupleLinkOnProvider, (_, _) {});
    expect(
      await container.read(datingCoupleLinkReadProvider('ama').future),
      isTrue,
    );
    final key2 = ('ama', 'rel-1');
    container.listen(datingPostLinkOfferProvider('ama'), (_, _) {});
    container.listen(datingLinkOriginProvider(key2), (_, _) {});
    container.listen(datingHowWeMetProvider(key2), (_, _) {});
    expect(
      await container.read(datingPostLinkOfferProvider('ama').future),
      DatingPostLinkOffer.linked,
    );
    expect(
      await container.read(datingLinkOriginProvider(key2).future),
      DateTime.utc(2026, 5, 1, 10),
    );
    expect(
      await container.read(datingHowWeMetProvider(key2).future),
      hasLength(1),
    );
    final gateway = container.read(datingLinkGatewayProvider);
    expect(await gateway.dismiss(DatingPostLinkOffer.linked), isTrue);
    await gateway.page('m1');

    String? device(String fn) {
      final r = requests.singleWhere((r) => r.url.pathSegments.last == fn);
      return {
        for (final e in r.headers.entries) e.key.toLowerCase(): e.value,
      }['x-attune-device'];
    }

    expect(requests.map((r) => r.url.pathSegments.last), [
      'get_dating_home',
      'get_dating_post_link_offer',
      'get_dating_link_origin',
      'get_how_we_met',
      'dismiss_dating_post_link_offer',
      'get_dating_couple_link',
    ]);
    for (final fn in coupleLinkCoupleSideFunctions) {
      expect(device(fn), isNull, reason: fn);
    }
    expect(device('get_dating_home'), isNull);
    expect(device('get_dating_couple_link'), 'phone-1');
  });

  test('the couple side refuses any other function', () async {
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(
          SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            httpClient: MockClient((_) async => http.Response('{}', 200)),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(coupleLinkCoupleCallProvider)('get_dating_home', {}),
      throwsArgumentError,
    );
  });
}
