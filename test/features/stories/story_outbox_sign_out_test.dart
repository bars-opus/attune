import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_base.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/outbox_fakes.dart';

class _FakeAuth implements AuthService {
  bool signedOut = false;
  @override
  Future<void> signOut() async => signedOut = true;
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache implements ChatCacheService {
  @override
  Future<void> clearAll() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The chat stores sign-out also wipes, faked so the suite never touches a
// plugin (same posture as auth_sign_out_media_wipe_test.dart).
class _NoopImageCache implements ChatImageCache {
  int clears = 0;
  @override
  Future<void> clear() async => clears++;
  @override
  Future<void> removeKeys(Iterable<String> keys) async {}
}

class _NoopMediaCache implements ChatMediaCache {
  @override
  Future<void> clear() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StuckVault extends StoryMediaVault {
  _StuckVault(Directory d) : super(supportDirectory: () async => d);
  @override
  Future<void> wipeAll() => Completer<void>().future; // never finishes
}

final _refProvider = Provider<Ref>((ref) => ref);

/// A store whose row wipe never finishes: a stuck outbox DB or keystore.
class _StuckStore extends StoryOutboxStore {
  _StuckStore() : super.forTesting(stub.createStoryOutboxBackend());
  @override
  Future<void> wipeAll() => Completer<void>().future;
}

/// The in-memory backend, with `init` counted and held until [openGate].
class _GatedBackend implements StoryOutboxBackend {
  final StoryOutboxBackend _inner = stub.createStoryOutboxBackend();
  final openGate = Completer<void>();
  int inits = 0;

  @override
  Future<void> init() async {
    inits++;
    await openGate.future;
    await _inner.init();
  }

  @override
  Future<List<String>> readAll(String userId) => _inner.readAll(userId);

  @override
  Future<void> put(
    String userId,
    String clientStoryId,
    String payload,
    int createdAtMillis,
  ) => _inner.put(userId, clientStoryId, payload, createdAtMillis);

  @override
  Future<void> remove(String userId, String clientStoryId) =>
      _inner.remove(userId, clientStoryId);

  @override
  Future<void> clearAll() => _inner.clearAll();

  @override
  Future<void> removeOtherUsers(String keepUserId) =>
      _inner.removeOtherUsers(keepUserId);

  @override
  Future<void> close() => _inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late Directory tmp;
  setUp(() {
    support = Directory.systemTemp.createTempSync('wipe_support');
    tmp = Directory.systemTemp.createTempSync('wipe_tmp');
  });
  tearDown(() {
    support.deleteSync(recursive: true);
    tmp.deleteSync(recursive: true);
  });

  Future<
    ({
      ProviderContainer container,
      StoryOutboxStore store,
      _FakeAuth auth,
      String folder,
    })
  >
  seeded({StoryMediaVault? vault, List<Override> extra = const []}) async {
    final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
    final v = vault ?? StoryMediaVault(supportDirectory: () async => support);
    final auth = _FakeAuth();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(path: RouteNames.intro, builder: (_, __) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        storyOutboxStoreProvider.overrideWithValue(store),
        storyMediaVaultProvider.overrideWithValue(v),
        authServiceProvider.overrideWithValue(auth),
        chatCacheServiceProvider.overrideWithValue(_FakeCache()),
        chatImagePickerProvider.overrideWithValue(
          ChatImagePicker(stagingDirectory: () async => support),
        ),
        chatMediaCacheProvider.overrideWithValue(_NoopMediaCache()),
        chatImageCacheProvider.overrideWithValue(_NoopImageCache()),
        signOutHooksProvider.overrideWithValue(const SignOutHooks()),
        routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
        appRouterProvider.overrideWithValue(router),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    final raw = outboxRecord(tmp);
    final stored = await StoryMediaVault(
      supportDirectory: () async => support,
    ).adopt(
      userId: outboxUserId,
      clientStoryId: raw.clientStoryId,
      mediaPath: raw.localMediaPath,
      thumbnailPath: raw.localThumbnailPath,
    );
    await store.put(
      outboxUserId,
      StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail),
    );
    return (
      container: container,
      store: store,
      auth: auth,
      folder: '${support.path}/story_outbox/$outboxUserId/cid-1',
    );
  }

  test('sign-out leaves no queued story row or capture on the phone', () async {
    final t = await seeded();
    await t.container.read(authOperationsProvider).signOut();
    expect(await t.store.readAll(outboxUserId), isEmpty);
    expect(Directory(t.folder).existsSync(), isFalse);
    expect(t.auth.signedOut, isTrue);
  });

  test(
    'quick-exit sign-out wipes too, even when AuthOperations is busy',
    () async {
      final t = await seeded(
        extra: [
          authOperationsProvider.overrideWith((ref) => _BusyAuthOps(ref)),
        ],
      );
      await safetySignOut(t.container.read(_refProvider));
      expect(await t.store.readAll(outboxUserId), isEmpty);
      expect(Directory(t.folder).existsSync(), isFalse);
    },
  );

  // Stories batch-4 review #5: AuthOperations' sign-out empties the image
  // caches; when it refuses, the fallback has to.
  test('a refused sign-out still empties the image cache', () async {
    final t = await seeded(
      extra: [authOperationsProvider.overrideWith((ref) => _BusyAuthOps(ref))],
    );
    await safetySignOut(t.container.read(_refProvider));
    final images = t.container.read(chatImageCacheProvider) as _NoopImageCache;
    expect(images.clears, 1);
  });

  test('a stuck wipe never holds sign-out past its bound', () async {
    final t = await seeded(
      vault: _StuckVault(support),
      extra: [
        storyOutboxWiperProvider.overrideWith(
          (ref) =>
              StoryOutboxWiper(ref, bound: const Duration(milliseconds: 100)),
        ),
      ],
    );
    await t.container
        .read(authOperationsProvider)
        .signOut()
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('a stuck story wipe held the sign-out'),
        );
    expect(t.auth.signedOut, isTrue);
    expect(
      await t.store.readAll(outboxUserId),
      isEmpty,
      reason: 'the rows go even when the file wipe is stuck',
    );
  });

  test('rows and files share one deadline: the wipe holds its caller at most '
      'its bound, even when both are stuck', () async {
    final container = ProviderContainer(
      overrides: [
        storyOutboxStoreProvider.overrideWithValue(_StuckStore()),
        storyMediaVaultProvider.overrideWithValue(_StuckVault(support)),
        storyOutboxWiperProvider.overrideWith(
          (ref) =>
              StoryOutboxWiper(ref, bound: const Duration(milliseconds: 100)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final watch = Stopwatch()..start();
    await container.read(storyOutboxWiperProvider).wipeAll();
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 180)));
  });

  test('an account-switch wipe bumps the epoch before the store opens', () {
    final backend = _GatedBackend();
    final store = StoryOutboxStore.forTesting(backend);
    final before = store.epoch;
    unawaited(store.removeOtherUsers('keep'));
    expect(
      store.epoch,
      before + 1,
      reason: 'a slow open must not let a drive start under the old epoch',
    );
    backend.openGate.complete();
  });

  test(
    'two first callers share one open: one connection, one cipher',
    () async {
      final backend = _GatedBackend();
      final store = StoryOutboxStore.forTesting(backend);
      final a = store.readAll('u1');
      final b = store.removeOtherUsers('u1');
      await pumpEventQueue();
      backend.openGate.complete();
      await Future.wait([a, b]);
      expect(backend.inits, 1);
    },
  );
}

class _BusyAuthOps extends AuthOperations {
  _BusyAuthOps(super.ref);
  @override
  Future<void> signOut() async =>
      throw StateError('Another auth operation is already in progress.');
}
