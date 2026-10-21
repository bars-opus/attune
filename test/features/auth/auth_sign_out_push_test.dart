// test/features/auth/auth_sign_out_push_test.dart
//
// Chat review #18: AuthOperations.signOut releases this device's push
// subscription while the session is still valid -- alongside the chat
// cache wipe (neither waits on the other) and before the auth sign-out --
// and a failed release never stops the sign-out. The auth layer reaches
// the push service only through signOutHooksProvider (no plugin import).
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeCache implements ChatCacheService {
  _FakeCache(this.events);
  final List<String> events;
  Completer<void>? hold;

  @override
  Future<void> clearAll() async {
    events.add('wipe started');
    if (hold != null) await hold!.future;
    events.add('cache wiped');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  _FakeAuth(this.events);
  final List<String> events;
  Object? failWith;
  User? stillSignedIn;

  @override
  Future<void> signOut() async {
    if (failWith != null) throw failWith!;
    events.add('auth signed out');
  }

  @override
  User? get currentUser => stillSignedIn;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Push {
  _Push(this.events);
  final List<String> events;
  bool fail = false;
  Completer<void>? hold;
  int cancels = 0;

  Future<void> beforeSignOut() async {
    events.add('release started');
    if (fail) throw StateError('plugin gone');
    if (hold != null) await hold!.future;
    events.add('push released');
  }
}

({
  ProviderContainer container,
  List<String> events,
  _Push push,
  _FakeCache cache,
  _FakeAuth auth,
})
_build() {
  final events = <String>[];
  final push = _Push(events);
  final cache = _FakeCache(events);
  final auth = _FakeAuth(events);
  final container = ProviderContainer(
    overrides: [
      chatCacheServiceProvider.overrideWithValue(cache),
      authServiceProvider.overrideWithValue(auth),
      routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
      signOutHooksProvider.overrideWithValue(
        SignOutHooks(
          beforeSignOut: push.beforeSignOut,
          signOutFailed: () => push.cancels++,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    events: events,
    push: push,
    cache: cache,
    auth: auth,
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('wipes the cache and releases the device, then signs out', () async {
    final t = _build();
    await t.container.read(authOperationsProvider).signOut();
    expect(t.events.first, 'wipe started', reason: 'the wipe is not delayed');
    expect(
      t.events,
      containsAll(['cache wiped', 'push released', 'auth signed out']),
    );
    expect(t.events.last, 'auth signed out');
  });

  test('the wipe does not wait on a slow release', () async {
    final t = _build();
    t.push.hold = Completer<void>();
    final signOut = t.container.read(authOperationsProvider).signOut();
    await _settle();
    expect(t.events, contains('cache wiped'));
    expect(t.events, isNot(contains('auth signed out')));
    t.push.hold!.complete();
    await signOut;
    expect(t.events.last, 'auth signed out');
  });

  test('the release does not wait on a slow wipe', () async {
    final t = _build();
    t.cache.hold = Completer<void>();
    final signOut = t.container.read(authOperationsProvider).signOut();
    await _settle();
    expect(t.events, contains('push released'));
    expect(t.events, isNot(contains('auth signed out')));
    t.cache.hold!.complete();
    await signOut;
    expect(t.events.last, 'auth signed out');
  });

  test('a failed release still signs out', () async {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      final t = _build();
      t.push.fail = true;
      await t.container.read(authOperationsProvider).signOut();
      expect(t.events.last, 'auth signed out');
    } finally {
      debugPrint = original;
    }
  });

  test(
    'M2: a failed auth sign-out with the person still signed in hands the device back',
    () async {
      final t = _build();
      t.auth.failWith = const AuthException('offline');
      t.auth.stillSignedIn = User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-10-01T00:00:00Z',
      );
      await expectLater(
        t.container.read(authOperationsProvider).signOut(),
        throwsA(isA<AuthException>()),
      );
      expect(t.push.cancels, 1);
    },
  );

  test(
    'a failed auth sign-out that still signed out keeps the release',
    () async {
      final t = _build();
      t.auth.failWith = const AuthException('server said no');
      await expectLater(
        t.container.read(authOperationsProvider).signOut(),
        throwsA(isA<AuthException>()),
      );
      expect(t.push.cancels, 0);
    },
  );

  test('M3: the composition root binds the hooks to OneSignalService', () {
    // main.dart is not runnable in a unit test; this keeps the one binding
    // from being dropped silently (the default hooks do nothing).
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('signOutHooksProvider.overrideWith('));
    expect(main, contains('.beforeSignOut()'));
    expect(main, contains('.cancelRelease()'));
    final auth =
        File(
          'lib/features/auth/providers/auth_provider.dart',
        ).readAsStringSync();
    expect(auth, isNot(contains('onesignal')), reason: 'no import cycle');
  });
}
