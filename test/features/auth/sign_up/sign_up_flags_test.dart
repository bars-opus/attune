// Spec 1 W2a (§5.3): signInFlowV2Provider, the flag shared screens branch
// on. It never throws: off when nothing can be read.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_boot.dart';
import 'package:attune/app/routing/sign_in_redirect.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart'
    hide preferencesServiceProvider;
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';

/// The public config read on a weak network: every read times out until
/// [online] (then the development project's answer, flow_signin_v2 on).
class _FlakyGateway implements PublicAppConfigGateway {
  bool online = false;

  @override
  Future<Map<String, dynamic>> fetch() async {
    if (!online) throw TimeoutException('get_public_app_config');
    return FakePublicConfigGateway().fetch();
  }
}

/// What App does: the router follows the live flag ([routing] built as
/// main.dart builds it), then the config is read once.
Future<ProviderContainer> _readConfig(
  SharedPreferences prefs,
  RoutingNotifier routing,
  PublicAppConfigGateway gateway, {
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      routingNotifierProvider.overrideWith((ref) => routing),
      publicAppConfigGatewayProvider.overrideWithValue(gateway),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  container.listen<void>(routingFlowV2SyncProvider, (_, __) {});
  await container.read(publicAppConfigProvider.future);
  await Future<void>.delayed(Duration.zero);
  return container;
}

void main() {
  test('off, and no throw, in a bare host with no SharedPreferences', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(flowSignInV2Provider), throwsA(anything));
    expect(container.read(signInFlowV2Provider), isFalse);
  });

  test('follows the live public config once it has been read', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        // A production build's default, in either build (I-1's seam).
        flowV2BuildDefaultProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    final seen = <bool>[];
    container.listen<bool>(
      signInFlowV2Provider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    await container.read(publicAppConfigProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [false, true]);
  });

  test(
    'routingFlowV2SyncProvider moves the router to the live flag (M-8)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final routing = RoutingNotifier(prefs: prefs);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          routingNotifierProvider.overrideWith((ref) => routing),
          publicAppConfigGatewayProvider.overrideWithValue(
            FakePublicConfigGateway(),
          ),
          flowV2BuildDefaultProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      var notified = 0;
      routing.addListener(() => notified++);

      // What App's build does.
      container.listen<void>(routingFlowV2SyncProvider, (_, __) {});
      expect(
        notified,
        0,
        reason: 'no change while App builds: GoRouter is never told mid-build',
      );

      await container.read(publicAppConfigProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(routing.flowV2, isTrue);
      expect(notified, 1);
    },
  );

  // Final review I-1: a config read that fails never moves the router from
  // the new sign-in back to today's in the middle of a session (§5.3: "until
  // the first fetch" means a successful one).
  group('I-1: a failed config read never flips the router', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('this build (FLOW_V2_DEFAULT=${Environment.flowV2Default}), nothing '
        'cached, the read times out: the router keeps the build default; '
        'with true, Welcome stays Welcome', () async {
      // A fresh install, as main.dart boots it.
      final routing = bootRoutingNotifier(prefs);
      expect(routing.flowV2, Environment.flowV2Default);

      await _readConfig(prefs, routing, _FlakyGateway());
      expect(routing.flowV2, Environment.flowV2Default);
      expect(
        appRedirect(routing, RouteNames.welcome),
        Environment.flowV2Default ? isNull : RouteNames.intro,
      );
    });

    for (final buildDefault in [true, false]) {
      test(
        'a build default of $buildDefault, nothing cached, the read times '
        'out: ${buildDefault ? 'Welcome stays Welcome' : "today's flow"}',
        () async {
          final routing = RoutingNotifier(
            prefs: prefs,
            isFirstLaunch: true,
            flowV2: buildDefault,
            currentUserId: () => null,
          );
          final container = await _readConfig(
            prefs,
            routing,
            _FlakyGateway(),
            overrides: [
              flowV2BuildDefaultProvider.overrideWithValue(buildDefault),
            ],
          );
          expect(container.read(signInFlowV2Provider), buildDefault);
          expect(routing.flowV2, buildDefault);
          expect(
            appRedirect(routing, RouteNames.welcome),
            buildDefault ? isNull : RouteNames.intro,
          );
        },
      );
    }

    test('a good read, a sign-out, then a read that fails: the router keeps '
        'the flow it read', () async {
      final gateway = _FlakyGateway()..online = true;
      // No cache: the build default, until the config turns v2 on.
      final routing = RoutingNotifier(
        prefs: prefs,
        flowV2: Environment.flowV2Default,
      );
      final container = await _readConfig(prefs, routing, gateway);
      expect(routing.flowV2, isTrue);

      // Settings sign-out (account deletion and the safety sign-out do
      // the same), then FeatureFlagRefresher's re-read on the change of
      // user, on a network that has gone.
      await PreferencesService(prefs).clearUserData();
      gateway.online = false;
      container.invalidate(publicAppConfigProvider);
      await container.read(publicAppConfigProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(routing.flowV2, isTrue);
      expect(appRedirect(routing, RouteNames.welcome), isNull);
    });

    test(
      'signing out keeps the public config: it is app config, not user data',
      () async {
        SharedPreferences.setMockInitialValues({'some_user_thing': true});
        prefs = await SharedPreferences.getInstance();
        await PublicAppConfigCache(prefs).write(
          PublicAppConfig.fromJson({
            'flags': {'flow_signin_v2': true},
          }),
        );

        await PreferencesService(prefs).clearUserData();
        expect(PublicAppConfigCache(prefs).read()?.flowSignInV2, isTrue);
        expect(prefs.containsKey('some_user_thing'), isFalse);
      },
    );
  });
}
