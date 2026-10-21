// test/core/notifications/onesignal_service_test.dart
//
// Chat review #15/#18: the prompt goes to a signed-in person with the lock
// open, once; the device's push subscription is registered with the server
// and released on sign-out. Drives OneSignalService.attach() with a fake
// PushSdk -- no plugin channels.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/data/owed_push_release_store.dart';
import 'package:attune/core/notifications/data/push_subscription_registry.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_sdk.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart'
    show chatConnectivityProvider;
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

/// The same person re-emitted with a changed field, as a token refresh does
/// (User has value equality: an identical copy would not notify).
User _refreshed(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
  updatedAt: '2026-10-02T00:00:00Z',
);

class FakePushSdk implements PushSdk {
  final logins = <String>[];

  /// When set, login waits on it (a slow SDK call).
  Completer<void>? holdLogin;
  int logouts = 0;
  int prompts = 0;
  bool granted = false;
  bool canPrompt = true;
  bool canRequestThrows = false;
  bool grantOnRequest = true;
  int initializes = 0;
  String? subscription;
  bool opted = true;
  int optIns = 0;
  int optOuts = 0;
  void Function(String? id, bool optedIn)? listener;

  @override
  Future<void> initialize(String appId) async => initializes++;
  @override
  Future<void> login(String externalId) async {
    logins.add(externalId);
    if (holdLogin != null) await holdLogin!.future;
  }

  @override
  Future<void> logout() async => logouts++;
  @override
  bool get permissionGranted => granted;
  @override
  Future<bool> canRequestPermission() async {
    if (canRequestThrows) throw StateError('plugin unavailable');
    return canPrompt;
  }

  @override
  Future<bool> requestPermission() async {
    prompts++;
    granted = grantOnRequest;
    return grantOnRequest;
  }

  @override
  String? get subscriptionId => subscription;
  @override
  bool get optedIn => opted;
  @override
  Future<void> optIn() async {
    optIns++;
    opted = true;
  }

  @override
  Future<void> optOut() async {
    optOuts++;
    opted = false;
  }

  @override
  void onSubscriptionChanged(void Function(String? id, bool optedIn) l) =>
      listener = l;
}

class FakeRegistry implements PushSubscriptionRegistry {
  final registered = <(String, String)>[];
  final unregistered = <String>[];
  int registerCalls = 0;
  int unregisterCalls = 0;
  Object? failWith;

  /// Fails only unregister.
  Object? failUnregister;

  /// When set, unregister never answers (a hung network call).
  Completer<void>? hangUnregister;

  /// When set, register waits on it (a slow network call).
  Completer<void>? holdRegister;

  /// Plan 1b final review I1: the owed release (anon) after an offline
  /// sign-out. Fails with [failWith] too (offline is offline).
  final released = <String>[];
  int releaseCalls = 0;
  Object? failRelease;
  Completer<void>? holdRelease;

  /// Every server call in order: `register:<id>`, `unregister:<id>`,
  /// `release:<id>` (sent, whether or not it then failed).
  final log = <String>[];

  @override
  Future<void> release(String subscriptionId) async {
    releaseCalls++;
    log.add('release:$subscriptionId');
    if (holdRelease != null) await holdRelease!.future;
    if (failRelease != null) throw failRelease!;
    if (failWith != null) throw failWith!;
    released.add(subscriptionId);
  }

  @override
  Future<void> register({
    required String subscriptionId,
    required String platform,
  }) async {
    registerCalls++;
    log.add('register:$subscriptionId');
    if (holdRegister != null) await holdRegister!.future;
    if (failWith != null) throw failWith!;
    registered.add((subscriptionId, platform));
  }

  @override
  Future<void> unregister(String subscriptionId) async {
    unregisterCalls++;
    log.add('unregister:$subscriptionId');
    if (hangUnregister != null) await hangUnregister!.future;
    if (failUnregister != null) throw failUnregister!;
    if (failWith != null) throw failWith!;
    unregistered.add(subscriptionId);
  }
}

/// The owed release, kept in memory; shared between two builds to stand for
/// the same phone across an app restart.
class FakeOwedStore implements OwedPushReleaseStore {
  String? owed;
  int writes = 0;

  /// When set, a write lands only once it completes (a slow keystore).
  Completer<void>? holdWrite;

  @override
  Future<String?> read() async => owed;
  @override
  Future<void> write(String subscriptionId) async {
    writes++;
    if (holdWrite != null) await holdWrite!.future;
    owed = subscriptionId;
  }

  @override
  Future<void> clear() async => owed = null;
}

/// A lock whose state the test flips.
class _Lock extends SafetyLockController {
  _Lock(this._initial);
  final SafetyLockState _initial;
  @override
  SafetyLockState build() => _initial;
  void set(SafetyLockState s) => state = s;
}

final _userState = StateProvider<User?>((_) => null);

({
  ProviderContainer container,
  OneSignalService service,
  FakePushSdk sdk,
  FakeRegistry registry,
  FakeOwedStore owed,
  StreamController<bool> online,
})
_build({
  User? user,
  SafetyLockState lock = SafetyLockState.open,
  GoRouter? router,
  Stream<User?>? auth,
  FakeOwedStore? owed,
}) {
  final sdk = FakePushSdk();
  final registry = FakeRegistry();
  final store = owed ?? FakeOwedStore();
  final online = StreamController<bool>.broadcast();
  addTearDown(online.close);
  final container = ProviderContainer(
    overrides: [
      owedPushReleaseStoreProvider.overrideWithValue(store),
      chatConnectivityProvider.overrideWith((ref) => online.stream),
      if (router != null) appRouterProvider.overrideWithValue(router),
      _userState.overrideWith((_) => user),
      // Like the app: the auth stream resolves a moment after start-up.
      authStateProvider.overrideWith(
        (ref) => auth ?? Stream.value(ref.watch(_userState)),
      ),
      if (auth == null)
        currentUserProvider.overrideWith((ref) => ref.watch(_userState)),
      safetyLockProvider.overrideWith(() => _Lock(lock)),
      pushSubscriptionRegistryProvider.overrideWithValue(registry),
      oneSignalServiceProvider.overrideWith(
        (ref) => OneSignalService(ref, sdk: sdk, platform: 'ios'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    service: container.read(oneSignalServiceProvider),
    sdk: sdk,
    registry: registry,
    owed: store,
    online: online,
  );
}

/// The expected failure logs ("register failed: StateError") stay out of
/// the test output.
void _quietLogs() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  addTearDown(() => debugPrint = original);
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('signed in, lock open: logs in and asks once', () async {
    final t = _build(user: _user('u1'));
    await t.service.attach();
    await t.service.attach();
    expect(t.sdk.logins, ['u1']);
    expect(t.sdk.prompts, 1);
  });

  test('a declined prompt is not shown again this run', () async {
    final t = _build(user: _user('u1'));
    t.sdk.grantOnRequest = false; // denied: granted stays false
    await t.service.attach();
    expect(t.sdk.prompts, 1);
    final lock = t.container.read(safetyLockProvider.notifier) as _Lock;
    lock.set(SafetyLockState.checking);
    await _settle();
    lock.set(SafetyLockState.open);
    await _settle();
    expect(t.sdk.canPrompt, isTrue);
    expect(t.sdk.prompts, 1);
  });

  // Quick exit only navigates to the decoy; the lock stays open (Spec 2).
  testWidgets('never over the quick-exit decoy; asks once off it', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: RouteNames.neutralScreen,
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(
          path: RouteNames.neutralScreen,
          builder: (_, __) => const SizedBox(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final t = _build(user: _user('u1'), router: router);
    await t.service.attach();
    expect(t.sdk.logins, ['u1']);
    expect(t.sdk.prompts, 0);

    router.go('/');
    await tester.pumpAndSettle();
    final lock = t.container.read(safetyLockProvider.notifier) as _Lock;
    lock.set(SafetyLockState.checking);
    await tester.pump();
    lock.set(SafetyLockState.open);
    await tester.pump();
    expect(t.sdk.prompts, 1);
  });

  test('signed out: no prompt; asks after sign-in', () async {
    final t = _build();
    await t.service.attach();
    expect(t.sdk.prompts, 0);
    t.container.read(_userState.notifier).state = _user('u2');
    await _settle();
    expect(t.sdk.logins, ['u2']);
    expect(t.sdk.prompts, 1);
  });

  test(
    'waits for the lock: no prompt while locked, asks when it opens',
    () async {
      final t = _build(user: _user('u1'), lock: SafetyLockState.locked);
      await t.service.attach();
      expect(t.sdk.prompts, 0);
      (t.container.read(safetyLockProvider.notifier) as _Lock).set(
        SafetyLockState.open,
      );
      await _settle();
      expect(t.sdk.prompts, 1);
    },
  );

  test('already granted, or the OS will not prompt again: silent', () async {
    final granted = _build(user: _user('u1'));
    granted.sdk.granted = true;
    await granted.service.attach();
    expect(granted.sdk.prompts, 0);

    final refused = _build(user: _user('u1'));
    refused.sdk.canPrompt = false;
    await refused.service.attach();
    expect(refused.sdk.prompts, 0);
  });

  test('the SDK cannot say whether it may prompt: silent, no error', () async {
    final t = _build(user: _user('u1'));
    t.sdk.canRequestThrows = true;
    await t.service.attach();
    expect(t.sdk.prompts, 0);
  });

  test('sign-out logs the SDK out', () async {
    final t = _build(user: _user('u1'));
    await t.service.attach();
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.sdk.logouts, 1);
  });

  test('a signed-in device is registered with the server', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    await t.service.attach();
    expect(t.registry.registered, [
      ('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'ios'),
    ]);
  });

  test(
    'a subscription that appears later (after the OS prompt) is registered too',
    () async {
      final t = _build(user: _user('u1'));
      await t.service.attach();
      expect(t.registry.registered, isEmpty);
      t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      t.sdk.listener!('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', true);
      await _settle();
      expect(t.registry.registered.length, 1);
      // The same id again is not re-sent.
      t.sdk.listener!('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', true);
      await _settle();
      expect(t.registry.registered.length, 1);
    },
  );

  test('sign-out unregisters and opts the device out, then logs out', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    await t.service.attach();
    await t.service.beforeSignOut();
    expect(t.registry.unregistered, ['aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee']);
    expect(t.sdk.optOuts, 1);
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.sdk.logouts, 1);
  });

  test(
    'the device still opts out when the server call fails (offline sign-out)',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      await t.service.attach();
      t.registry.failWith = StateError('offline');
      await t.service.beforeSignOut();
      expect(t.sdk.optOuts, 1);
    },
  );

  test(
    'the next account on the same phone opts back in and registers',
    () async {
      final t = _build();
      t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      t.sdk.opted = false;
      t.sdk.granted = true;
      await t.service.attach();
      t.container.read(_userState.notifier).state = _user('u2');
      await _settle();
      expect(t.sdk.optIns, 1);
      expect(t.registry.registered, [
        ('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'ios'),
      ]);
      expect(t.sdk.prompts, 0, reason: 'permission already granted: no dialog');
    },
  );

  // ---- Carried requirements (Task 6/7 reviews) ----

  const sub = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

  test(
    'an OS opt-out then opt-in re-registers the same subscription',
    () async {
      // Task 7 deactivates ids OneSignal reports "not subscribed"; coming back
      // must send the id again or the phone stays silent.
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      expect(t.registry.registered.length, 1);
      t.sdk.opted = false;
      t.sdk.listener!(sub, false);
      await _settle();
      expect(
        t.registry.registered.length,
        1,
        reason: 'opted out: nothing sent',
      );
      t.sdk.opted = true;
      t.sdk.listener!(sub, true);
      await _settle();
      expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
    },
  );

  test(
    'a new subscription id (reinstall / token refresh) is registered',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      const next = '11111111-2222-4333-8444-555555555555';
      t.sdk.subscription = next;
      t.sdk.listener!(next, true);
      await _settle();
      expect(t.registry.registered, [(sub, 'ios'), (next, 'ios')]);
    },
  );

  test('signed out: a subscription change registers nothing', () async {
    final t = _build();
    await t.service.attach();
    t.sdk.subscription = sub;
    t.sdk.listener!(sub, true);
    await _settle();
    expect(t.registry.registered, isEmpty);
  });

  test('an opted-out device is not registered', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    t.sdk.opted =
        false; // no permission: optIn would prompt, so it is not called
    t.sdk.canPrompt = false;
    await t.service.attach();
    expect(t.sdk.optIns, 0);
    expect(t.registry.registered, isEmpty);
  });

  test('switching account registers the device for the new person', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    await t.service.attach();
    t.container.read(_userState.notifier).state = _user('u2');
    await _settle();
    expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
    expect(t.sdk.logins, ['u1', 'u2']);
  });

  test('the same person again (token refresh) is not re-sent', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    await t.service.attach();
    t.container.read(_userState.notifier).state = _refreshed('u1');
    await _settle();
    expect(t.registry.registered.length, 1);
  });

  test(
    'a failed register is retried on the next subscription change',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.registry.failWith = StateError('offline');
      await t.service.attach();
      expect(t.registry.registered, isEmpty);
      t.registry.failWith = null;
      t.sdk.listener!(sub, true);
      await _settle();
      expect(t.registry.registered, [(sub, 'ios')]);
    },
  );

  test('a register still in flight is not sent twice', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    t.registry.holdRegister = Completer<void>();
    unawaited(t.service.attach());
    await _settle();
    t.sdk.listener!(sub, true);
    await _settle();
    t.registry.holdRegister!.complete();
    await _settle();
    expect(t.registry.registered, [(sub, 'ios')]);
  });

  test(
    'after release, the same session cannot re-register before sign-out lands',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.granted = true;
      await t.service.attach();
      await t.service.beforeSignOut();
      // A token refresh or subscription event inside the sign-out window.
      t.container.read(_userState.notifier).state = _refreshed('u1');
      t.sdk.listener!(sub, true);
      await _settle();
      expect(t.sdk.optIns, 0);
      expect(t.registry.registered.length, 1);
      expect(t.sdk.logins, ['u1'], reason: 'released: no login again');
      // Signed out, then the same person signs back in: registered again.
      t.container.read(_userState.notifier).state = null;
      await _settle();
      t.container.read(_userState.notifier).state = _user('u1');
      await _settle();
      expect(t.sdk.optIns, 1);
      expect(t.registry.registered.length, 2);
    },
  );

  test('a register that lands after release does not count as sent', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    t.sdk.granted = true;
    t.registry.holdRegister = Completer<void>();
    unawaited(t.service.attach());
    await _settle();
    final release = t.service.beforeSignOut();
    t.registry.holdRegister!.complete();
    await release;
    // Released after the in-flight register: the server ends unregistered.
    expect(t.registry.registered, [(sub, 'ios')]);
    expect(t.registry.unregistered, [sub]);
    t.container.read(_userState.notifier).state = null;
    await _settle();
    t.registry.holdRegister = null;
    t.container.read(_userState.notifier).state = _user('u1');
    await _settle();
    expect(t.registry.registered.length, 2, reason: 'fresh sign-in re-sends');
  });

  test('any sign-out opts a still-opted-in device out locally', () async {
    // Paths that skip beforeSignOut (EULA decline, a session revoked from
    // another device) still leave a phone that receives nothing.
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    await t.service.attach();
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.sdk.optOuts, 1);
    expect(t.sdk.logouts, 1);
  });

  // ---- Fix round 1 ----

  test(
    'C1: a sign-out while OneSignal is starting releases once it has started',
    () async {
      // SafetyLockController's cold-start sign-out races App.initState's
      // initialize(); attach() stands in for initialize() finishing.
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      final release = t.service.beforeSignOut();
      await _settle();
      expect(t.registry.unregistered, isEmpty);
      expect(t.sdk.optOuts, 0);
      await t.service.attach();
      await release;
      expect(t.registry.unregistered, [sub]);
      expect(t.sdk.optOuts, 1);
      expect(t.registry.registered, isEmpty, reason: 'released: never re-sent');
      expect(t.sdk.logins, isEmpty, reason: 'released: no login either');
    },
  );

  test(
    'C1: no app id (OneSignal never starts): sign-out leaves the SDK alone',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.initialize(); // tests have no ONESIGNAL_APP_ID
      await t.service.beforeSignOut();
      expect(t.registry.unregistered, isEmpty);
      expect(t.sdk.optOuts, 0);
      expect(t.sdk.initializes, 0);
    },
  );

  test(
    'C1: signed out at start with the device still opted in: opts out and logs out',
    () async {
      final t = _build();
      t.sdk.subscription = sub;
      await t.service.attach();
      await _settle();
      expect(t.sdk.optOuts, 1);
      expect(t.sdk.logouts, 1);
      expect(t.registry.registered, isEmpty);
    },
  );

  test('C1: signed out at start, already opted out: nothing to do', () async {
    final t = _build();
    t.sdk.opted = false;
    await t.service.attach();
    await _settle();
    expect(t.sdk.optOuts, 0);
    expect(t.sdk.logouts, 0);
  });

  test(
    'C1: auth still loading at start: decides only once it resolves',
    () async {
      final signedOut = StreamController<User?>();
      addTearDown(signedOut.close);
      final a = _build(auth: signedOut.stream);
      a.sdk.subscription = sub;
      await a.service.attach();
      await _settle();
      expect(
        a.sdk.optOuts,
        0,
        reason: 'unknown yet: a signed-in phone must not flap',
      );
      signedOut.add(null);
      await _settle();
      expect(a.sdk.optOuts, 1);
      expect(a.sdk.logouts, 1);

      final signedIn = StreamController<User?>();
      addTearDown(signedIn.close);
      final b = _build(auth: signedIn.stream);
      b.sdk.subscription = sub;
      await b.service.attach();
      signedIn.add(_user('u1'));
      await _settle();
      expect(b.sdk.optOuts, 0);
      expect(b.sdk.logins, ['u1']);
      expect(b.registry.registered, [(sub, 'ios')]);
    },
  );

  testWidgets(
    'C1: an init that never finishes: the release gives up at its bound',
    (tester) async {
      final originalPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {};
      try {
        final t = _build(user: _user('u1'));
        t.sdk.subscription = sub;
        var done = false;
        unawaited(t.service.beforeSignOut().then((_) => done = true));
        await tester.pump(const Duration(seconds: 4));
        expect(done, isTrue);
        expect(
          t.sdk.optOuts,
          0,
          reason: 'the plugin is not called before init',
        );
        // The SDK starts later on a now signed-out phone: attach catches up.
        t.container.read(_userState.notifier).state = null;
        await tester.pump(const Duration(milliseconds: 1));
        await t.service.attach();
        await tester.pump(const Duration(milliseconds: 1));
        expect(t.sdk.optOuts, 1);
        // The same person signs back in this run: a normal sign-in.
        t.container.read(_userState.notifier).state = _user('u1');
        await tester.pump(const Duration(milliseconds: 1));
        expect(t.sdk.logins, ['u1']);
        expect(t.registry.registered, [(sub, 'ios')]);
      } finally {
        debugPrint = originalPrint;
      }
    },
  );

  test('I1: a second release for the same person is a cheap no-op', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    await t.service.attach();
    await t.service.beforeSignOut();
    await t.service.beforeSignOut();
    expect(t.registry.unregistered, [sub]);
    expect(t.sdk.optOuts, 1);
  });

  test(
    'M2: a sign-out that failed hands the device back to the person',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.granted = true;
      await t.service.attach();
      await t.service.beforeSignOut();
      t.service.cancelRelease();
      await _settle();
      expect(t.sdk.optIns, 1);
      expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
      // Nothing to cancel any more: no second opt-in.
      t.service.cancelRelease();
      await _settle();
      expect(t.sdk.optIns, 1);
    },
  );

  test('I2: the current subscription id, once OneSignal has started', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    expect(t.service.currentSubscriptionId, isNull);
    await t.service.attach();
    expect(t.service.currentSubscriptionId, sub);
  });

  testWidgets('a hung unregister cannot hold sign-out past its bound', (
    tester,
  ) async {
    // testWidgets checks debugPrint is restored before teardown runs.
    final originalPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      t.registry.hangUnregister = Completer<void>();
      var done = false;
      unawaited(t.service.beforeSignOut().then((_) => done = true));
      await tester.pump(const Duration(seconds: 2));
      expect(done, isFalse);
      expect(t.sdk.optOuts, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(t.sdk.optOuts, 1, reason: 'still opted out locally');
    } finally {
      debugPrint = originalPrint;
    }
  });

  test(
    'addendum: a revoked session (signed out from another phone) opts out, no retry loop',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.granted = true;
      t.registry.failWith = const PostgrestException(
        message: 'push_subscription:session_revoked',
        code: 'P0001',
      );
      await t.service.attach();
      await _settle();
      expect(t.registry.registerCalls, 1);
      expect(t.sdk.optOuts, 1, reason: 'treated like signed out');
      // More triggers in the same doomed session: nothing is re-sent and the
      // device is not opted back in.
      t.sdk.listener!(sub, false);
      t.sdk.listener!(sub, true);
      t.container.read(_userState.notifier).state = _refreshed('u1');
      await _settle();
      expect(t.registry.registerCalls, 1);
      expect(t.sdk.optIns, 0);
      // The session ends; a fresh sign-in registers normally.
      t.registry.failWith = null;
      t.container.read(_userState.notifier).state = null;
      await _settle();
      t.container.read(_userState.notifier).state = _user('u1');
      await _settle();
      expect(t.registry.registered, [(sub, 'ios')]);
    },
  );

  test('addendum: any other register failure still retries', () {
    expect(
      isPushSessionRevoked(
        const PostgrestException(
          message: 'push_subscription:session_revoked',
          code: 'P0001',
        ),
      ),
      isTrue,
    );
    expect(
      isPushSessionRevoked(
        const PostgrestException(message: 'push_subscription:invalid'),
      ),
      isFalse,
    );
    expect(isPushSessionRevoked(StateError('offline')), isFalse);
  });

  // ---- Fix round 2 ----

  test(
    'R2-1: a release landing during login() is not undone by the opt-in',
    () async {
      final t = _build();
      t.sdk.subscription = sub;
      t.sdk.opted = false; // a previous sign-out on this phone opted it out
      t.sdk.granted = true;
      await t.service.attach();
      t.sdk.holdLogin = Completer<void>();
      t.container.read(_userState.notifier).state = _user('u1');
      await _settle();
      expect(t.sdk.logins, ['u1']);
      // Quick exit / sign-out while the SDK login is still in flight.
      await t.service.beforeSignOut();
      t.sdk.holdLogin!.complete();
      await _settle();
      expect(t.sdk.optIns, 0, reason: 'released: the device stays opted out');
      expect(t.registry.registered, isEmpty);
    },
  );

  test(
    'R2-1: an account switch during login() leaves the old run alone',
    () async {
      final t = _build();
      t.sdk.subscription = sub;
      t.sdk.opted = false;
      t.sdk.granted = true;
      await t.service.attach();
      t.sdk.holdLogin = Completer<void>();
      t.container.read(_userState.notifier).state = _user('u1');
      await _settle();
      t.container.read(_userState.notifier).state = _user('u2');
      await _settle();
      t.sdk.holdLogin!.complete();
      await _settle();
      // Only u2's run opts in and registers, once.
      expect(t.sdk.optIns, 1);
      expect(t.registry.registered, [(sub, 'ios')]);
    },
  );

  test(
    'R2-3: after other devices are stopped, this phone registers again',
    () async {
      final t = _build(user: _user('u1'));
      await t.service.attach(); // no subscription id yet
      t.service.refreshRegistration();
      await _settle();
      expect(t.registry.registered, isEmpty);
      // The id appears later: registered as usual.
      t.sdk.subscription = sub;
      t.sdk.listener!(sub, true);
      await _settle();
      expect(t.registry.registered, [(sub, 'ios')]);
      // A row the server deactivated (null keep id) is sent again, not deduped.
      t.service.refreshRegistration();
      await _settle();
      expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
    },
  );

  test(
    'R2-4: a release after a revoked-session opt-out still unregisters',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.registry.failWith = const PostgrestException(
        message: 'push_subscription:session_revoked',
        code: 'P0001',
      );
      await t.service.attach();
      await _settle();
      expect(t.sdk.optOuts, 1);
      t.registry.failWith = null;
      await t.service.beforeSignOut();
      expect(t.registry.unregistered, [sub]);
    },
  );

  test(
    'R2-4: a release whose unregister failed is retried by the next release',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      t.registry.failUnregister = StateError('offline');
      await t.service.beforeSignOut();
      expect(t.registry.unregisterCalls, 1);
      t.registry.failUnregister = null;
      await t.service.beforeSignOut();
      expect(t.registry.unregistered, [sub]);
      // Now done: a third release is the cheap no-op.
      await t.service.beforeSignOut();
      expect(t.registry.unregisterCalls, 2);
    },
  );

  test(
    'R2-5: permission granted later by the deferred prompt opts in and registers',
    () async {
      final t = _build(user: _user('u1'), lock: SafetyLockState.locked);
      t.sdk.subscription = sub;
      t.sdk.opted = false; // opted out at an earlier sign-out
      await t.service.attach();
      expect(t.sdk.prompts, 0);
      expect(t.registry.registered, isEmpty);
      (t.container.read(safetyLockProvider.notifier) as _Lock).set(
        SafetyLockState.open,
      );
      await _settle();
      expect(t.sdk.prompts, 1);
      expect(t.sdk.optIns, 1);
      expect(t.registry.registered, [(sub, 'ios')]);
    },
  );

  test('R2-5: a declined deferred prompt does not opt in', () async {
    final t = _build(user: _user('u1'), lock: SafetyLockState.locked);
    t.sdk.subscription = sub;
    t.sdk.opted = false;
    t.sdk.grantOnRequest = false;
    await t.service.attach();
    (t.container.read(safetyLockProvider.notifier) as _Lock).set(
      SafetyLockState.open,
    );
    await _settle();
    expect(t.sdk.prompts, 1);
    expect(t.sdk.optIns, 0);
    expect(t.registry.registered, isEmpty);
  });

  // ---- Plan 1b final review ----

  test(
    'M4: a release after cancelRelease and a failed re-register still unregisters',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.canPrompt = false; // no permission: nothing opts it back in
      await t.service.attach();
      // 1. Sign-out releases the device (server unregister succeeds).
      await t.service.beforeSignOut();
      expect(t.registry.unregistered, [sub]);
      // 2. The auth sign-out failed: the device is handed back, but the
      //    re-register fails (offline) and, without permission, the device
      //    stays opted out.
      t.registry.failWith = StateError('offline');
      t.service.cancelRelease();
      await _settle();
      expect(t.sdk.optedIn, isFalse);
      // 3. AuthOperations tries again: its unregister fails too.
      await t.service.beforeSignOut();
      expect(t.registry.unregisterCalls, 2);
      // 4. The Safety fallback releases again, back online: the server copy
      //    is still live, so the unregister must be sent, not skipped.
      t.registry.failWith = null;
      await t.service.beforeSignOut();
      expect(t.registry.unregisterCalls, 3);
      expect(t.registry.unregistered, [sub, sub]);
      // Step 3 owed the release; the unregister that landed settles it.
      expect(t.owed.owed, isNull);
    },
  );

  test(
    'I1: an offline sign-out owes the release; the next start sends it, signed out',
    () async {
      _quietLogs();
      final first = _build(user: _user('u1'));
      first.sdk.subscription = sub;
      await first.service.attach();
      first.registry.failWith = StateError('offline');
      await first.service.beforeSignOut();
      expect(first.sdk.optOuts, 1, reason: 'still opted out locally');
      expect(first.owed.owed, sub, reason: 'the release is owed');

      // The app is closed; the next start (signed out, online) pays it.
      final next = _build(owed: first.owed);
      next.sdk.subscription = sub;
      next.sdk.opted = false;
      await next.service.attach();
      await _settle();
      expect(next.registry.released, [sub]);
      expect(next.owed.owed, isNull);
    },
  );

  test(
    'I1: a sign-out whose unregister succeeded owes nothing',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      await t.service.beforeSignOut();
      expect(t.owed.writes, 0);
      expect(t.owed.owed, isNull);
    },
  );

  test(
    'I1: signed in at the next start, the owed release goes before the register',
    () async {
      final store = FakeOwedStore()..owed = sub;
      final t = _build(user: _user('u2'), owed: store);
      t.sdk.subscription = sub;
      await t.service.attach();
      await _settle();
      expect(t.registry.log, ['release:$sub', 'register:$sub']);
      expect(store.owed, isNull);
    },
  );

  test(
    'I1: still offline at start, the release is sent when the network returns',
    () async {
      _quietLogs();
      final store = FakeOwedStore()..owed = sub;
      final t = _build(owed: store);
      t.sdk.subscription = sub;
      t.sdk.opted = false;
      t.registry.failRelease = StateError('offline');
      await t.service.attach();
      await _settle();
      expect(t.registry.releaseCalls, 1);
      expect(store.owed, sub, reason: 'kept for the next try');
      t.registry.failRelease = null;
      t.online.add(false);
      await _settle();
      expect(t.registry.releaseCalls, 1, reason: 'still offline: nothing sent');
      t.online.add(true);
      await _settle();
      expect(t.registry.released, [sub]);
      expect(store.owed, isNull);
      // Paid: later network changes send nothing.
      t.online.add(false);
      t.online.add(true);
      await _settle();
      expect(t.registry.releaseCalls, 2);
    },
  );

  test(
    'I1: an offline sign-out pays its release when the network returns, app still open',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      t.registry.failWith = StateError('offline');
      await t.service.beforeSignOut();
      t.container.read(_userState.notifier).state = null;
      await _settle();
      t.registry.failWith = null;
      t.online.add(true);
      await _settle();
      expect(t.registry.released, [sub]);
      expect(t.owed.owed, isNull);
    },
  );

  test(
    'I1: registering the same device again settles the owed release',
    () async {
      _quietLogs();
      final store = FakeOwedStore()..owed = sub;
      final t = _build(user: _user('u2'), owed: store);
      t.sdk.subscription = sub;
      t.registry.failRelease = StateError('offline');
      await t.service.attach();
      await _settle();
      expect(t.registry.registered, [(sub, 'ios')]);
      expect(store.owed, isNull, reason: 'the device is u2\'s now');
      t.registry.failRelease = null;
      t.online.add(true);
      await _settle();
      expect(t.registry.released, isEmpty, reason: 'nothing owed any more');
    },
  );

  test(
    'I1: a sign-out that failed (person still signed in) owes nothing',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      await t.service.attach();
      t.registry.failWith = StateError('offline');
      await t.service.beforeSignOut();
      expect(t.owed.owed, sub);
      t.service.cancelRelease();
      await _settle();
      expect(t.owed.owed, isNull, reason: 'the device is still theirs');
      t.registry.failWith = null;
      t.online.add(true);
      await _settle();
      expect(t.registry.releaseCalls, 0);
    },
  );

  test('I1: an id the server calls invalid is not retried forever', () async {
    _quietLogs();
    final store = FakeOwedStore()..owed = 'not-a-subscription-id';
    final t = _build(owed: store);
    t.registry.failRelease = const PostgrestException(
      message: 'push_subscription:invalid',
      code: 'P0001',
    );
    await t.service.attach();
    await _settle();
    expect(t.registry.releaseCalls, 1);
    expect(store.owed, isNull);
  });

  testWidgets('I1: a hung owed release never blocks start-up', (tester) async {
    final originalPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      final store = FakeOwedStore()..owed = sub;
      final t = _build(user: _user('u2'), owed: store);
      t.sdk.subscription = sub;
      t.registry.holdRelease = Completer<void>();
      var attached = false;
      unawaited(t.service.attach().then((_) => attached = true));
      await tester.pump(const Duration(milliseconds: 1));
      // Sign-in and the prompt go ahead; only the register waits behind
      // the release, and only for its bound.
      expect(t.sdk.logins, ['u2']);
      expect(t.registry.registered, isEmpty);
      await tester.pump(const Duration(seconds: 6));
      expect(t.registry.registered, [(sub, 'ios')]);
      expect(attached, isTrue);
      expect(store.owed, isNull);
    } finally {
      debugPrint = originalPrint;
    }
  });

  test('I1: isPushSubscriptionInvalid', () {
    expect(
      isPushSubscriptionInvalid(
        const PostgrestException(message: 'push_subscription:invalid'),
      ),
      isTrue,
    );
    expect(isPushSubscriptionInvalid(StateError('offline')), isFalse);
  });

  // ---- Controller ruling: catch-all sign-out owes the release too ----

  test(
    'catch-all: a sign-out that skipped beforeSignOut owes the release; the next start pays it',
    () async {
      final first = _build(user: _user('u1'));
      first.sdk.subscription = sub;
      await first.service.attach();
      // EULA decline / session expiry: auth signs out without beforeSignOut.
      first.container.read(_userState.notifier).state = null;
      await _settle();
      expect(first.sdk.optOuts, 1, reason: 'the local opt-out is unchanged');
      expect(first.owed.owed, sub);
      expect(first.registry.releaseCalls, 0, reason: 'paid on the next start');

      final next = _build(owed: first.owed);
      next.sdk.subscription = sub;
      next.sdk.opted = false;
      await next.service.attach();
      await _settle();
      expect(next.registry.released, [sub]);
      expect(next.owed.owed, isNull);
    },
  );

  test('catch-all: after a successful beforeSignOut nothing more is owed', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = sub;
    await t.service.attach();
    await t.service.beforeSignOut();
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.owed.writes, 0);
    expect(t.owed.owed, isNull);
  });

  test('catch-all: no subscription id known, nothing owed', () async {
    final t = _build(user: _user('u1'));
    await t.service.attach();
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.owed.writes, 0);
  });

  test(
    'catch-all: a new sign-in that registers the device settles the owed release (the new owner is never silenced)',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.granted = true;
      await t.service.attach();
      t.container.read(_userState.notifier).state = null;
      await _settle();
      expect(t.owed.owed, sub);
      t.container.read(_userState.notifier).state = _user('u2');
      await _settle();
      expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
      expect(t.owed.owed, isNull);
      t.online.add(true);
      await _settle();
      expect(t.registry.releaseCalls, 0);
      expect(t.registry.log.last, 'register:$sub');
    },
  );

  test(
    'catch-all: a slow owed write cannot land after the new owner registered',
    () async {
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.granted = true;
      await t.service.attach();
      t.owed.holdWrite = Completer<void>();
      t.container.read(_userState.notifier).state = null;
      await _settle();
      t.container.read(_userState.notifier).state = _user('u2');
      await _settle();
      expect(t.registry.registered.length, 1, reason: 'waits for the write');
      t.owed.holdWrite!.complete();
      await _settle();
      expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
      expect(t.owed.owed, isNull, reason: 'the register settled it after');
    },
  );

  // ---- Re-review residual: no register/release wait cycle ----

  test(
    'a release fired while a register waits on the owed write cannot deadlock it',
    () async {
      _quietLogs();
      final t = _build(user: _user('u1'));
      t.sdk.subscription = sub;
      t.sdk.granted = true;
      await t.service.attach();
      // Offline sign-out: the release is owed (and the network watch armed).
      t.registry.failWith = StateError('offline');
      await t.service.beforeSignOut();
      expect(t.owed.owed, sub);
      // The catch-all owes it again, through a slow keystore write.
      t.owed.holdWrite = Completer<void>();
      t.container.read(_userState.notifier).state = null;
      await _settle();
      // Back online, a new person signs in: their register waits on the write.
      t.registry.failWith = null;
      t.container.read(_userState.notifier).state = _user('u2');
      await _settle();
      expect(t.registry.registered.length, 1);
      // The network-return release starts during that wait.
      t.online.add(true);
      await _settle();
      t.owed.holdWrite!.complete();
      await _settle();
      expect(t.registry.registered, [(sub, 'ios'), (sub, 'ios')]);
      expect(t.owed.owed, isNull);
      expect(
        t.registry.log.last,
        'register:$sub',
        reason: 'no release lands after the new owner registered',
      );
    },
  );
}
