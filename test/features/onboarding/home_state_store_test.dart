// Spec 1 W1b (§5.5, D20, controller ruling C-5): the home-state cache keeps
// the tab layout, link state, needs and hold only. Never the path, never
// anything about Dating, so Spec 2's S19 "no Dating data on disk" holds.
import 'dart:convert';

import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HomeState _datingAnswer() => HomeState.fromJson({
  'has_account': true,
  'path': 'dating',
  'tab': 'me',
  'path_previous': 'just_me',
  'needs': ['birth_date'],
  'hold': true,
  'eula_version': '2',
  'dating': {'enabled': true, 'enrolled': true},
  'link': {'state': 'none'},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a Dating account caches me, and nothing that says dating', () async {
    final store = HomeStateStore(
      prefs,
      userId: 'u1',
      now: () => DateTime.utc(2026, 10, 25, 9),
    );
    await store.write(_datingAnswer());

    final raw = prefs.getString('attune.home.u1.state')!;
    expect(raw.toLowerCase(), isNot(contains('dating')));
    expect(raw, isNot(contains('just_me')));
    expect((jsonDecode(raw) as Map).keys.toSet(), {
      'tab',
      'link',
      'needs',
      'hold',
      'at',
    });

    final cached = store.read()!;
    expect(cached.tab, AppTab.me);
    expect(cached.link, LinkState.none);
    expect(cached.needs, [HomeNeed.birthDate]);
    expect(cached.hold, isTrue);
    expect(cached.isComplete, isFalse);
    expect(cached.at, DateTime.utc(2026, 10, 25, 9));
  });

  test(
    'scoped per account, cleared on demand, corrupt values dropped',
    () async {
      await HomeStateStore(prefs, userId: 'u1').write(_datingAnswer());
      expect(HomeStateStore(prefs, userId: 'u2').read(), isNull);

      await HomeStateStore(prefs, userId: 'u1').clear();
      expect(prefs.containsKey(HomeStateStore.keyFor('u1')), isFalse);

      await prefs.setString(HomeStateStore.keyFor('u3'), '{not json');
      expect(HomeStateStore(prefs, userId: 'u3').read(), isNull);
    },
  );

  // Final review M-5: an unknown need survives the cache as "not complete",
  // and its wire name never reaches disk.
  test('an unknown need stays incomplete through the cache', () async {
    final store = HomeStateStore(prefs, userId: 'u4');
    await store.write(
      HomeState.fromJson({
        'has_account': true,
        'path': 'just_me',
        'tab': 'me',
        'needs': ['some_future_need'],
      }),
    );

    expect(
      prefs.getString(HomeStateStore.keyFor('u4')),
      isNot(contains('some_future_need')),
    );
    final cached = store.read()!;
    expect(cached.isComplete, isFalse);
    expect(cached.needs, [HomeNeed.unknown]);
  });
}
