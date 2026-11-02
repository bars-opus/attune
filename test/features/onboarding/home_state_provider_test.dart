// Spec 1 W3a (§5.3, §5.5, D20, §3.14): the home state as the app holds it:
// the cache on the first frame, the server's answer once it comes, the
// queued A5 and A6 counted as done, and nothing about the path or Dating
// ever written to the phone.
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_home_state.dart';

const _uid = 'u-w3a';

Future<(ProviderContainer, FakeHomeStateGateway, SharedPreferences)> _build({
  Map<String, Object> prefsValues = const {},
  Map<String, dynamic>? server,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final gateway = FakeHomeStateGateway(state: server);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
    ],
  );
  addTearDown(container.dispose);
  return (container, gateway, prefs);
}

String _cache({
  String tab = 'me',
  String link = 'none',
  List<String> needs = const [],
  bool hold = false,
}) =>
    '{"tab":"$tab","link":"$link","needs":[${needs.map((n) => '"$n"').join(',')}],'
    '"hold":$hold,"at":"2026-10-26T08:00:00.000Z"}';

void main() {
  test('nothing known: not complete, no layout', () async {
    final (c, _, _) = await _build();
    final snap = c.read(homeStateProvider(_uid));
    expect(snap.known, isFalse);
    expect(snap.isComplete, isFalse);
  });

  test(
    'the first frame reads the cache; path and Dating stay unknown',
    () async {
      final (c, _, _) = await _build(
        prefsValues: {
          HomeStateStore.keyFor(_uid): _cache(tab: 'chat', link: 'linked'),
        },
      );
      final snap = c.read(homeStateProvider(_uid));
      expect(snap.tab, AppTab.chat);
      expect(snap.link, LinkState.linked);
      expect(snap.isComplete, isTrue);
      expect(snap.path, isNull);
      expect(snap.dating, isNull);
    },
  );

  test(
    'a cached unknown need keeps the home closed (final review M-5)',
    () async {
      final (c, _, _) = await _build(
        prefsValues: {
          HomeStateStore.keyFor(_uid): _cache(needs: ['shoe_size']),
        },
      );
      final snap = c.read(homeStateProvider(_uid));
      expect(snap.needs, [HomeNeed.unknown]);
      expect(snap.isComplete, isFalse);
    },
  );

  test('a hold keeps the home closed', () async {
    final (c, _, _) = await _build(
      prefsValues: {HomeStateStore.keyFor(_uid): _cache(hold: true)},
    );
    expect(c.read(homeStateProvider(_uid)).isComplete, isFalse);
  });

  test(
    'refresh applies the answer and caches only layout, link, needs, hold',
    () async {
      final (c, gateway, prefs) = await _build(
        server: homeJson(
          path: 'dating',
          pathPrevious: 'just_me',
          datingEnabled: true,
          datingEnrolled: true,
          link: 'ended_window',
          windowEndsAt: '2026-11-20T10:00:00Z',
        ),
      );
      final answer = await c.read(homeStateProvider(_uid).notifier).refresh();
      expect(answer, isNotNull);
      final snap = c.read(homeStateProvider(_uid));
      expect(snap.path, AppPath.dating);
      expect(snap.pathPrevious, AppPath.justMe);
      expect(snap.dating?.enrolled, isTrue);
      expect(snap.linkDetail.windowEndsAt, DateTime.utc(2026, 11, 20, 10));
      final raw = prefs.getString(HomeStateStore.keyFor(_uid))!;
      expect(raw, contains('"tab":"me"'));
      expect(raw, contains('"link":"ended_window"'));
      // D20: no path, no Dating, on the phone.
      for (final key in prefs.getKeys()) {
        expect(key.toLowerCase(), isNot(contains('dating')));
        expect('${prefs.get(key)}'.toLowerCase(), isNot(contains('dating')));
        expect('${prefs.get(key)}', isNot(contains('just_me')));
      }
      expect(gateway.count('get_my_home_state'), 1);
    },
  );

  test('two refreshes at once make one call', () async {
    final (c, gateway, _) = await _build();
    gateway.hold = Completer<void>();
    final notifier = c.read(homeStateProvider(_uid).notifier);
    final a = notifier.refresh();
    final b = notifier.refresh();
    gateway.hold!.complete();
    await Future.wait([a, b]);
    expect(gateway.count('get_my_home_state'), 1);
  });

  test('a failed refresh keeps the snapshot', () async {
    final (c, gateway, _) = await _build(
      prefsValues: {
        HomeStateStore.keyFor(_uid): _cache(tab: 'chat', link: 'pending'),
      },
    );
    gateway.failAlways = TimeoutException('offline');
    expect(await c.read(homeStateProvider(_uid).notifier).refresh(), isNull);
    expect(c.read(homeStateProvider(_uid)).tab, AppTab.chat);
  });

  test('a queued A5 counts as consent, birth date and name', () async {
    final pending = PendingSignUp(
      displayName: 'Ama',
      birthDate: DateTime.utc(1990, 1, 1),
    );
    final (c, _, prefs) = await _build();
    final store = OnboardingStore(prefs, scope: 'user.$_uid');
    await store.savePendingSignUp(pending);
    c.invalidate(homeStateProvider(_uid));
    final offline = c.read(homeStateProvider(_uid));
    expect(offline.needs, [
      HomeNeed.path,
    ], reason: 'a new account: only A6 left');
    expect(offline.isComplete, isFalse);

    await c
        .read(homeStateProvider(_uid).notifier)
        .apply(
          HomeState.fromJson(
            homeJson(
              hasAccount: false,
              path: null,
              needs: ['consent', 'birth_date', 'name', 'path'],
            ),
          ),
        );
    expect(c.read(homeStateProvider(_uid)).needs, [HomeNeed.path]);
  });

  test('a queued A6 counts as the path and sets the layout', () async {
    final (c, _, prefs) = await _build(
      prefsValues: {
        HomeStateStore.keyFor(_uid): _cache(needs: ['path']),
      },
    );
    await OnboardingStore(
      prefs,
      scope: 'user.$_uid',
    ).savePendingPath(AppPath.relationship);
    c.read(homeStateProvider(_uid).notifier).reloadLocal();
    final snap = c.read(homeStateProvider(_uid));
    expect(snap.needs, isEmpty);
    expect(snap.tab, AppTab.chat);
    expect(snap.isComplete, isTrue);
  });

  test('a Dating choice is never queued (D20)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: 'user.$_uid');
    expect(() => store.savePendingPath(AppPath.dating), throwsArgumentError);
    expect(prefs.getKeys(), isEmpty);
  });

  test("the first v2 answer drops this account's legacy mode once", () async {
    final (c, _, prefs) = await _build(
      prefsValues: {
        'attune.onboarding.user.$_uid.mode': 'couples',
        'attune.onboarding.user.other.mode': 'couples',
      },
    );
    await c.read(homeStateProvider(_uid).notifier).refresh();
    expect(prefs.containsKey('attune.onboarding.user.$_uid.mode'), isFalse);
    expect(prefs.getString('attune.onboarding.user.other.mode'), 'couples');
  });

  test('invalidating forgets the live answer (sign-out)', () async {
    final (c, _, _) = await _build(server: homeJson(path: 'dating'));
    await c.read(homeStateProvider(_uid).notifier).refresh();
    expect(c.read(homeStateProvider(_uid)).path, AppPath.dating);
    c.invalidate(homeStateProvider(_uid));
    expect(c.read(homeStateProvider(_uid)).path, isNull);
    expect(
      c.read(homeStateProvider(_uid)).tab,
      AppTab.me,
      reason: 'cache stays',
    );
  });

  test('a refresh still running at sign-out is dropped (review #2)', () async {
    final (c, gateway, prefs) = await _build(
      server: homeJson(path: 'dating', datingEnabled: true),
    );
    gateway.hold = Completer<void>();
    final pending = c.read(homeStateProvider(_uid).notifier).refresh();
    // Sign-out: the account's provider is invalidated and the registry
    // wipes its cache, while the old read is still out.
    c.invalidate(homeStateProvider(_uid));
    await prefs.remove(HomeStateStore.keyFor(_uid));
    gateway.hold!.complete();
    expect(await pending, isNull);
    expect(c.read(homeStateProvider(_uid)).path, isNull);
    expect(c.read(homeStateProvider(_uid)).dating, isNull);
    expect(prefs.containsKey(HomeStateStore.keyFor(_uid)), isFalse);

    // The next refresh is a fresh one, not the dropped read.
    gateway.hold = null;
    expect(await c.read(homeStateProvider(_uid).notifier).refresh(), isNotNull);
    expect(gateway.count('get_my_home_state'), 2);
  });
}
