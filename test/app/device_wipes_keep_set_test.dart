// Spec 1 W3a (§5.8; preflight F-9): no registered device wipe, at either
// moment and through each of its three call sites (sign-out, the safety
// sign-out's fallback, quick exit), removes a key sign-out keeps on
// purpose: W2's age gate (attune.age_gate.guest_ok, attune.age_block.until)
// and public config, and W3's signed-in flags. The list is read from
// clearUserData's own keep set, so a key added there is covered here.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/protective_device_keys.dart';

class _FakeCache implements ChatCacheService {
  @override
  Future<void> clearAll() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  @override
  Future<void> signOut() async {}

  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BusyAuthOps extends AuthOperations {
  _BusyAuthOps(super.ref);

  @override
  Future<void> signOut() async =>
      throw StateError('Another auth operation is already in progress.');
}

final _refProvider = Provider<Ref>((ref) => ref);

/// The keep set, each with a value (and one key per kept prefix), plus two
/// accounts' home-state caches (which sign-out's registry entry does
/// remove).
Future<SharedPreferences> _seed() async {
  SharedPreferences.setMockInitialValues({
    for (final key in PreferencesService.keptKeys) key: 'kept',
    for (final prefix in PreferencesService.keptPrefixes) '${prefix}u1': 'kept',
    HomeStateStore.keyFor('u1'): '{}',
    HomeStateStore.keyFor('u2'): '{}',
  });
  return SharedPreferences.getInstance();
}

void _expectKeepSetIntact(SharedPreferences prefs) {
  for (final key in PreferencesService.keptKeys) {
    expect(prefs.getString(key), 'kept', reason: key);
  }
  for (final prefix in PreferencesService.keptPrefixes) {
    expect(prefs.getString('${prefix}u1'), 'kept', reason: prefix);
  }
}

/// Every protective key, in prefs and in secure storage (review #4).
void _seedProtective(Map<String, Object> prefsValues) {
  SharedPreferences.setMockInitialValues({
    ...prefsValues,
    for (final key in protectiveKeys) key: 'on',
  });
  FlutterSecureStorage.setMockInitialValues({
    for (final key in protectiveKeys) key: 'on',
  });
}

Future<void> _expectProtectiveIntact() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in protectiveKeys) {
    expect(prefs.containsKey(key), isTrue, reason: 'prefs $key');
    expect(
      await const FlutterSecureStorage().read(key: key),
      isNotNull,
      reason: 'secure $key',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the keep set names W2\'s keys and the signed-in flags', () {
    expect(
      PreferencesService.keptKeys,
      containsAll([
        AgeGateStore.guestOkKey,
        AgeGateStore.blockUntilKey,
        PublicAppConfigCache.key,
        FlowFlagsCache.key,
      ]),
    );
  });

  test('every registered wipe, at every moment, leaves the keep set', () async {
    final prefs = await _seed();
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    expect(registry.entries, isNotEmpty);
    for (final moment in WipeMoment.values) {
      await registry.run(moment);
      _expectKeepSetIntact(prefs);
    }
    expect(prefs.containsKey(HomeStateStore.keyFor('u1')), isFalse);
  });

  test('the real quick-exit entries leave every protective setting', () async {
    // Proven by what the entries do, not by the keys they declare: an
    // entry that names no keys can't slip past (review #4).
    _seedProtective(const {});
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    await registry.run(WipeMoment.quickExit);
    await _expectProtectiveIntact();
  });

  test('sign-out (AuthOperations) leaves the keep set', () async {
    final prefs = await _seed();
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final container = ProviderContainer(
      overrides: [
        chatCacheServiceProvider.overrideWithValue(_FakeCache()),
        authServiceProvider.overrideWithValue(_FakeAuth()),
        routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
        deviceWipeRegistryProvider.overrideWithValue(registry),
        signOutHooksProvider.overrideWithValue(const SignOutHooks()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authOperationsProvider).signOut();
    _expectKeepSetIntact(prefs);
    expect(
      prefs.containsKey(HomeStateStore.keyFor('u2')),
      isFalse,
      reason: 'the registry ran',
    );
  });

  test('the safety sign-out\'s fallback leaves the keep set', () async {
    final prefs = await _seed();
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
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
    _expectKeepSetIntact(prefs);
    expect(
      prefs.containsKey(HomeStateStore.keyFor('u1')),
      isFalse,
      reason: 'the registry ran',
    );
  });

  testWidgets('quick exit leaves the keep set and the protective keys', (
    t,
  ) async {
    final prefs = await _seed();
    FlutterSecureStorage.setMockInitialValues({
      for (final key in protectiveKeys) key: 'on',
    });
    var left = false;
    QuickExitService.exitOverride = () async => left = true;
    final registry = DeviceWipeRegistry.instance;
    addTearDown(() {
      QuickExitService.exitOverride = null;
      registry.clear();
    });
    registry.clear();
    registerDeviceWipes();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
        GoRoute(
          path: '/neutralScreen',
          name: 'neutralScreen',
          builder: (_, __) => const Text('DECOY'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.runAsync(() async {
      await QuickExitService.executeWithRouter(router);
      // Let the unawaited wipes finish before reading.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(left, isTrue);
    _expectKeepSetIntact(prefs);
    for (final key in protectiveKeys) {
      expect(
        await const FlutterSecureStorage().read(key: key),
        isNotNull,
        reason: key,
      );
    }
    expect(
      prefs.containsKey(HomeStateStore.keyFor('u1')),
      isTrue,
      reason: 'quick exit keeps the session, so the home cache stays',
    );
  });
}
