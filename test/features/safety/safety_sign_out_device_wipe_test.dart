// Spec 1 W3a (§5.8): the safety sign-out's fallback runs the device wipes
// too (AuthOperations may have refused it).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _BusyAuthOps extends AuthOperations {
  _BusyAuthOps(super.ref);

  @override
  Future<void> signOut() async =>
      throw StateError('Another auth operation is already in progress.');
}

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the fallback runs the sign-out wipes', () async {
    final ran = <String>[];
    final registry =
        DeviceWipeRegistry()..register(
          DeviceWipeEntry(
            id: 'probe',
            moments: const {WipeMoment.signOut},
            run: () async => ran.add('wiped'),
          ),
        );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: RouteNames.intro, builder: (_, __) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        authOperationsProvider.overrideWith((ref) => _BusyAuthOps(ref)),
        currentUserProvider.overrideWith((ref) => null),
        deviceWipeRegistryProvider.overrideWithValue(registry),
        routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
        appRouterProvider.overrideWithValue(router),
      ],
    );
    addTearDown(container.dispose);
    await safetySignOut(container.read(_refProvider));
    expect(ran, ['wiped']);
  });

  test('a registry that fails to load never stops it (review #6)', () async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: RouteNames.intro, builder: (_, __) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    final routing = RoutingNotifier();
    final container = ProviderContainer(
      overrides: [
        authOperationsProvider.overrideWith((ref) => _BusyAuthOps(ref)),
        currentUserProvider.overrideWith((ref) => null),
        deviceWipeRegistryProvider.overrideWith(
          (ref) => throw StateError('broken'),
        ),
        routingNotifierProvider.overrideWith((ref) => routing),
        appRouterProvider.overrideWithValue(router),
      ],
    );
    addTearDown(container.dispose);
    await safetySignOut(container.read(_refProvider));
    expect(
      router.routeInformationProvider.value.uri.path,
      RouteNames.intro,
      reason: 'the steps after the wipe still ran',
    );
  });
}
