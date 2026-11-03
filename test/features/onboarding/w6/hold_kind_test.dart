// Spec 1 W6a (W3 batch 5 carry): the home state names the hold's kind; the
// phone keeps it beside the hold; only an age hold, or a hold that names no
// kind (every hold before W6a was an age hold), blocks the phone (I#1).
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';

void main() {
  test(
    'the kind is read from the wire; a name this build lacks is unknown, and '
    'a value that is not a name is no kind at all',
    () {
      expect(HoldKind.fromWire(null), isNull);
      expect(HoldKind.fromWire('age_review'), HoldKind.ageReview);
      expect(HoldKind.fromWire('safety_review'), HoldKind.safetyReview);
      expect(HoldKind.fromWire('recovery_hold'), HoldKind.recoveryHold);
      expect(HoldKind.fromWire('from_a_later_spec'), HoldKind.unknown);
      expect(HoldKind.fromWire(7), isNull);
      expect(HoldKind.fromWire(true), isNull);
      expect(HoldKind.fromWire(const {'kind': 'safety_review'}), isNull);
    },
  );

  test('only an age hold, or a hold that names no kind, blocks the phone', () {
    expect(holdBlocksDevice(HoldKind.ageReview), isTrue);
    expect(holdBlocksDevice(null), isTrue, reason: 'as before W6a');
    expect(
      holdBlocksDevice(HoldKind.unknown),
      isFalse,
      reason:
          'the server sorts age_review first: a kind it names that this '
          'build lacks is never an age hold (I#1)',
    );
    expect(holdBlocksDevice(HoldKind.safetyReview), isFalse);
    expect(holdBlocksDevice(HoldKind.recoveryHold), isFalse);
  });

  test(
    'get_my_home_state: hold_kind read; a server from before W6a reads null',
    () {
      final held = HomeState.fromJson(
        homeJson(hold: true, holdKind: 'safety_review'),
      );
      expect(held.hold, isTrue);
      expect(held.holdKind, HoldKind.safetyReview);
      final old = homeJson(hold: true)..remove('hold_kind');
      expect(HomeState.fromJson(old).holdKind, isNull);
      expect(HomeState.fromJson(homeJson()).holdKind, isNull);
    },
  );

  test('a missing or malformed kind still blocks the phone (I#1)', () {
    final missing = HomeState.fromJson(
      homeJson(hold: true)..remove('hold_kind'),
    );
    expect(missing.holdKind, isNull);
    expect(holdBlocksDevice(missing.holdKind), isTrue);
    final malformed = HomeState.fromJson(
      homeJson(hold: true)..['hold_kind'] = 7,
    );
    expect(malformed.holdKind, isNull);
    expect(holdBlocksDevice(malformed.holdKind), isTrue);
    final later = HomeState.fromJson(
      homeJson(hold: true, holdKind: 'from_a_later_spec'),
    );
    expect(later.holdKind, HoldKind.unknown);
    expect(holdBlocksDevice(later.holdKind), isFalse);
  });

  test(
    'the cache keeps the kind beside the hold, and nothing about Dating',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = HomeStateStore(prefs, userId: 'u1');
      await store.write(
        HomeState.fromJson(homeJson(hold: true, holdKind: 'recovery_hold')),
      );
      expect(store.read()!.holdKind, HoldKind.recoveryHold);
      expect(
        prefs.getString(HomeStateStore.keyFor('u1')),
        isNot(contains('dating')),
      );
      await store.write(HomeState.fromJson(homeJson()));
      expect(store.read()!.holdKind, isNull);
      expect(
        prefs.getString(HomeStateStore.keyFor('u1')),
        isNot(contains('hold_kind')),
      );
      // A cache written before W6a.
      await prefs.setString(
        HomeStateStore.keyFor('u1'),
        '{"tab":"me","link":"none","needs":[],"hold":true,"at":"2026-11-01T00:00:00.000Z"}',
      );
      expect(store.read()!.hold, isTrue);
      expect(store.read()!.holdKind, isNull);
    },
  );

  test(
    'the snapshot carries the kind from the server, the cache and a queued write',
    () {
      final server = HomeSnapshot.fromServer(
        HomeState.fromJson(homeJson(hold: true, holdKind: 'age_review')),
      );
      expect(server.holdKind, HoldKind.ageReview);
      expect(server.withQueued(signUp: true).holdKind, HoldKind.ageReview);
      final cached = HomeSnapshot.fromCache(
        CachedHomeState(
          tab: AppTab.me,
          link: LinkState.none,
          needs: const [],
          hold: true,
          holdKind: HoldKind.safetyReview,
          at: DateTime.utc(2026, 11, 3),
        ),
      );
      expect(cached.holdKind, HoldKind.safetyReview);
      expect(cached.isComplete, isFalse);
    },
  );
}
