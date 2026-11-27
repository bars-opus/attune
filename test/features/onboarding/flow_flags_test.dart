// Spec 1 W3a (§2.5 A-6, §5.3): flow_paths_v2 and flow_couples_v2 as the app
// reads them: effective (each needs the one before it), the cached copy on
// the first frame, off when nothing can be read.
import 'dart:async';

import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_home_state.dart';

Future<ProviderContainer> _container({
  bool signIn = true,
  FakeFlowFlagsGateway? gateway,
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      signInFlowV2Provider.overrideWithValue(signIn),
      flowFlagsGatewayProvider.overrideWithValue(
        gateway ?? FakeFlowFlagsGateway(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('effective values follow the dependencies', () async {
    for (final (signIn, paths, couples, wantPaths, wantCouples) in [
      (true, true, true, true, true),
      (true, true, false, true, false),
      (true, false, true, false, false),
      (false, true, true, false, false),
    ]) {
      final c = await _container(
        signIn: signIn,
        gateway: FakeFlowFlagsGateway(pathsV2: paths, couplesV2: couples),
      );
      await c.read(flowFlagsProvider.future);
      expect(c.read(flowPathsV2Provider), wantPaths, reason: '$signIn $paths');
      expect(c.read(flowCouplesV2Provider), wantCouples, reason: '$couples');
    }
  });

  test(
    'the first frame uses the cached copy; a fresh read replaces it',
    () async {
      final gateway = FakeFlowFlagsGateway(pathsV2: false);
      final c = await _container(
        gateway: gateway,
        prefsValues: {FlowFlagsCache.key: '{"paths":true,"couples":false}'},
      );
      expect(c.read(flowPathsV2Provider), isTrue, reason: 'cached');
      await c.read(flowFlagsProvider.future);
      expect(c.read(flowPathsV2Provider), isFalse, reason: 'live');
      await Future<void>.delayed(Duration.zero);
      final prefs = c.read(sharedPreferencesProvider);
      expect(
        prefs.getString(FlowFlagsCache.key),
        '{"paths":false,"couples":false}',
      );
    },
  );

  test('an unreadable flag keeps the cache, else is off', () async {
    final failing = FakeFlowFlagsGateway()..failWith = StateError('offline');
    final cached = await _container(
      gateway: failing,
      prefsValues: {FlowFlagsCache.key: '{"paths":true,"couples":true}'},
    );
    await cached.read(flowFlagsProvider.future);
    expect(cached.read(flowPathsV2Provider), isTrue);

    final none = await _container(
      gateway: FakeFlowFlagsGateway()..failWith = StateError('offline'),
    );
    await none.read(flowFlagsProvider.future);
    expect(none.read(flowPathsV2Provider), isFalse);
    expect(none.read(flowCouplesV2Provider), isFalse);
  });

  test('no SharedPreferences in a bare host: off, never a throw', () {
    final c = ProviderContainer(
      overrides: [
        signInFlowV2Provider.overrideWithValue(true),
        flowFlagsGatewayProvider.overrideWithValue(
          FakeFlowFlagsGateway()..failWith = StateError('no backend'),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(flowPathsV2Provider), isFalse);
  });

  test('the cached copy survives sign-out, like the public config', () async {
    // Preflight F-2: clearUserData keeps it (app config, no Dating value),
    // so the next sign-in's first frame is not today's home for a moment.
    SharedPreferences.setMockInitialValues({
      FlowFlagsCache.key: '{"paths":true,"couples":true}',
      'attune.home.u1.state': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    await PreferencesService(prefs).clearUserData();
    expect(
      prefs.getString(FlowFlagsCache.key),
      '{"paths":true,"couples":true}',
    );
    expect(prefs.containsKey('attune.home.u1.state'), isFalse);
    expect(PreferencesService.keptKeys, contains(FlowFlagsCache.key));
  });

  test('the cache key and its values never name Dating (D20)', () async {
    final c = await _container();
    await c.read(flowFlagsProvider.future);
    await Future<void>.delayed(Duration.zero);
    final prefs = c.read(sharedPreferencesProvider);
    for (final key in prefs.getKeys()) {
      expect(key.toLowerCase(), isNot(contains('dating')));
      expect('${prefs.get(key)}'.toLowerCase(), isNot(contains('dating')));
    }
  });

  // Entry gates fix 4 (owner 2026-11-27): an unread public config is
  // unknown, never "flags off". flowFlagsKnownProvider used to be true at
  // once whenever flow_signin_v2 read off, which a prod build with no
  // cached config does before its first read; the stored invite was then
  // accepted before the gate's consent and date-of-birth checks.
  group('flowFlagsKnownProvider (entry gates fix 4)', () {
    Future<ProviderContainer> known({
      required PublicAppConfigGateway config,
      FakeFlowFlagsGateway? flags,
      bool buildDefault = false,
      Map<String, Object> prefsValues = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          publicAppConfigGatewayProvider.overrideWithValue(config),
          flowV2BuildDefaultProvider.overrideWithValue(buildDefault),
          flowFlagsGatewayProvider.overrideWithValue(
            flags ?? FakeFlowFlagsGateway(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('before the public config is read: unknown, though the build '
        'default says flow_signin_v2 is off', () async {
      final pending = _PendingConfig();
      final c = await known(config: pending);
      expect(c.read(signInFlowV2Provider), isFalse);
      expect(c.read(flowFlagsKnownProvider), isFalse);
      pending.answer.complete(_config(signIn: false));
      await c.read(publicAppConfigProvider.future);
      expect(c.read(flowFlagsKnownProvider), isTrue);
    });

    test('a failed read with nothing cached stays unknown', () async {
      final c = await known(config: _PendingConfig()..fail());
      await c.read(publicAppConfigProvider.future);
      expect(c.read(signInFlowV2Provider), isFalse);
      expect(c.read(flowFlagsKnownProvider), isFalse);
    });

    test('a failed read with a cached config: known (an answer this phone '
        'has had)', () async {
      final c = await known(
        config: _PendingConfig()..fail(),
        prefsValues: {
          PublicAppConfigCache.key: '{"flags":{"flow_signin_v2":false}}',
        },
      );
      expect(c.read(flowFlagsKnownProvider), isTrue);
    });

    test('flow_signin_v2 on: known once the signed-in flags are read too',
        () async {
      final flags = FakeFlowFlagsGateway(pathsV2: false);
      final c = await known(
        config: _PendingConfig()..answer.complete(_config(signIn: true)),
        flags: flags,
      );
      await c.read(publicAppConfigProvider.future);
      expect(c.read(signInFlowV2Provider), isTrue);
      expect(c.read(flowFlagsKnownProvider), isFalse);
      await c.read(flowFlagsProvider.future);
      expect(c.read(flowFlagsKnownProvider), isTrue);
    });
  });
}

Map<String, dynamic> _config({required bool signIn}) => {
  'flags': {'flow_signin_v2': signIn},
  'config': <String, dynamic>{},
};

/// The public config, answered when the test says (or failing).
class _PendingConfig implements PublicAppConfigGateway {
  final answer = Completer<Map<String, dynamic>>();
  bool _fails = false;

  void fail() => _fails = true;

  @override
  Future<Map<String, dynamic>> fetch() =>
      _fails ? Future.error(StateError('offline')) : answer.future;
}
