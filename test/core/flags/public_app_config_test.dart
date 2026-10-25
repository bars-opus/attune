// Spec 1 W1c (§2.5, §5.3, D15): the public config client. Effective flags
// come from the server; the first frame uses the cached copy, else the
// build default; an unreadable config is everything off.
import 'dart:async';

import 'package:attune/app/feature_flag_refresher.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements PublicAppConfigGateway {
  _Gateway(this._answer);

  final Future<Map<String, dynamic>> Function() _answer;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> fetch() {
    calls++;
    return _answer();
  }
}

const _server = <String, dynamic>{
  'flags': {
    'flow_signin_v2': true,
    'platform_age_signals': false,
    'support_resources_v2': true,
    'text_scale_v2': false,
  },
  'config': {
    'age_signal_storefronts': ['USA', 'BRA'],
    'dating_open_countries': ['GB', 'GH'],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer container(PublicAppConfigGateway gateway) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        publicAppConfigGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'reads the server shape and caches it for the next first frame',
    () async {
      final c = container(_Gateway(() async => _server));
      final config = await c.read(publicAppConfigProvider.future);

      expect(config.flowSignInV2, isTrue);
      expect(config.supportResourcesV2, isTrue);
      expect(config.platformAgeSignals, isFalse);
      expect(config.textScaleV2, isFalse);
      expect(config.ageSignalStorefronts, ['USA', 'BRA']);
      expect(c.read(flowSignInV2Provider), isTrue);
      expect(c.read(datingOpenCountriesProvider), ['GB', 'GH']);
      expect(PublicAppConfigCache(prefs).read()?.datingOpenCountries, [
        'GB',
        'GH',
      ]);
    },
  );

  test(
    'before the first answer: the cached copy, else the build default',
    () async {
      final first = container(
        _Gateway(() => Completer<Map<String, dynamic>>().future),
      );
      expect(first.read(flowSignInV2Provider), Environment.flowV2Default);
      expect(first.read(datingOpenCountriesProvider), isEmpty);

      await PublicAppConfigCache(
        prefs,
      ).write(PublicAppConfig.fromJson(_server));
      final second = container(
        _Gateway(() => Completer<Map<String, dynamic>>().future),
      );
      expect(second.read(flowSignInV2Provider), isTrue);
      expect(second.read(datingOpenCountriesProvider), ['GB', 'GH']);
    },
  );

  // Final review I-1: everything but flow_signin_v2, which keeps the build
  // default (a weak network never flips the router mid-session).
  test('a failed read keeps the cached copy, else everything is off', () async {
    final none = container(_Gateway(() async => throw Exception('offline')));
    final off = await none.read(publicAppConfigProvider.future);
    expect(off.flowSignInV2, Environment.flowV2Default);
    expect(off.datingOpenCountries, isEmpty);
    expect(none.read(flowSignInV2Provider), Environment.flowV2Default);

    await PublicAppConfigCache(prefs).write(PublicAppConfig.fromJson(_server));
    final cached = container(_Gateway(() async => throw Exception('offline')));
    expect(
      (await cached.read(publicAppConfigProvider.future)).flowSignInV2,
      isTrue,
    );
  });

  test('only a literal true is on, and only strings are kept', () {
    final config = PublicAppConfig.fromJson({
      'flags': {'flow_signin_v2': 'yes', 'text_scale_v2': 1},
      'config': {
        'dating_open_countries': [1, 'GH', null],
      },
    });
    expect(config.flowSignInV2, isFalse);
    expect(config.textScaleV2, isFalse);
    expect(config.datingOpenCountries, ['GH']);
    expect(PublicAppConfig.fromJson(const {}).ageSignalStorefronts, isEmpty);
  });

  test('a corrupt cache reads as no cache', () async {
    await prefs.setString(PublicAppConfigCache.key, '{not json');
    expect(PublicAppConfigCache(prefs).read(), isNull);
  });

  // Batch 6 extras (each closes a mutant the brief's tests let through).
  test('an unreadable config is every flag off and every list empty', () async {
    const allOff = {
      'flags': {
        'flow_signin_v2': false,
        'platform_age_signals': false,
        'support_resources_v2': false,
        'text_scale_v2': false,
      },
      'config': {'age_signal_storefronts': [], 'dating_open_countries': []},
    };
    expect(PublicAppConfig.off.toJson(), allOff);
    final none = container(_Gateway(() async => throw Exception('offline')));
    expect((await none.read(publicAppConfigProvider.future)).toJson(), {
      ...allOff,
      'flags': {
        ...allOff['flags']!,
        'flow_signin_v2': Environment.flowV2Default,
      },
    });
  });

  test('final review I-1: a failed read with nothing cached keeps the build '
      'default for flow_signin_v2 only', () async {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        publicAppConfigGatewayProvider.overrideWithValue(
          _Gateway(() async => throw Exception('offline')),
        ),
        flowV2BuildDefaultProvider.overrideWithValue(true),
      ],
    );
    addTearDown(c.dispose);
    final config = await c.read(publicAppConfigProvider.future);
    expect(config.toJson(), {
      'flags': {
        'flow_signin_v2': true,
        'platform_age_signals': false,
        'support_resources_v2': false,
        'text_scale_v2': false,
      },
      'config': {'age_signal_storefronts': [], 'dating_open_countries': []},
    });
    expect(c.read(flowSignInV2Provider), isTrue);
    expect(c.read(datingOpenCountriesProvider), isEmpty);
    expect(
      PublicAppConfigCache(prefs).read(),
      isNull,
      reason: 'an unread config is never cached',
    );
  });

  test('the public config is re-read on resume and on a change of user', () {
    expect(refreshedFlagProviders, contains(publicAppConfigProvider));
  });

  // Batch 6 fix round 1.
  test(
    'review #1 (D20): the cached copy names nothing Dating and reads back',
    () async {
      final c = container(_Gateway(() async => _server));
      await c.read(publicAppConfigProvider.future);

      final raw = prefs.getString(PublicAppConfigCache.key)!;
      expect(raw.toLowerCase(), isNot(contains('dating')));
      expect(PublicAppConfigCache(prefs).read()!.datingOpenCountries, [
        'GB',
        'GH',
      ]);
      expect(PublicAppConfigCache(prefs).read()!.ageSignalStorefronts, [
        'USA',
        'BRA',
      ]);
      expect(PublicAppConfigCache(prefs).read()!.flowSignInV2, isTrue);
    },
  );

  test(
    'review #2: a cache that cannot be written still returns the fresh answer',
    () async {
      for (final failsAtOnce in [true, false]) {
        final c = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              _UnwritablePrefs(failsAtOnce: failsAtOnce),
            ),
            publicAppConfigGatewayProvider.overrideWithValue(
              _Gateway(() async => _server),
            ),
          ],
        );
        addTearDown(c.dispose);
        final config = await c.read(publicAppConfigProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(config.flowSignInV2, isTrue, reason: 'failsAtOnce $failsAtOnce');
        expect(config.datingOpenCountries, ['GB', 'GH']);
      }
    },
  );

  test('review #3: equal configs are equal, with equal hash codes', () {
    final a = PublicAppConfig.fromJson(_server);
    final b = PublicAppConfig.fromJson(_server);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);

    Map<String, dynamic> changed(String section, String key, Object value) => {
      'flags': {...(_server['flags'] as Map)},
      'config': {...(_server['config'] as Map)},
    }..[section][key] = value;
    for (final other in [
      changed('flags', 'flow_signin_v2', false),
      changed('flags', 'platform_age_signals', true),
      changed('flags', 'support_resources_v2', false),
      changed('flags', 'text_scale_v2', true),
      changed('config', 'age_signal_storefronts', ['USA']),
      changed('config', 'dating_open_countries', ['GB']),
    ]) {
      expect(a == PublicAppConfig.fromJson(other), isFalse, reason: '$other');
    }
  });

  test(
    'review #3: a re-read with the same answer does not rebuild the country list',
    () async {
      final c = container(_Gateway(() async => _server));
      var rebuilt = 0;
      c.listen(datingOpenCountriesProvider, (_, __) => rebuilt++);
      await c.read(publicAppConfigProvider.future);
      final first = c.read(datingOpenCountriesProvider);
      expect(first, ['GB', 'GH']);

      rebuilt = 0;
      c.invalidate(publicAppConfigProvider);
      await c.read(publicAppConfigProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(rebuilt, 0);
      expect(identical(c.read(datingOpenCountriesProvider), first), isTrue);
    },
  );
}

/// SharedPreferences whose writes fail: at once (a synchronous throw) or
/// later (a failed future). Reads find nothing.
class _UnwritablePrefs extends Fake implements SharedPreferences {
  _UnwritablePrefs({required this.failsAtOnce});

  final bool failsAtOnce;

  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) {
    if (failsAtOnce) throw StateError('disk full');
    return Future<bool>.error(StateError('disk full'));
  }
}
