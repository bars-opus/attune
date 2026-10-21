// Wave 2 final fixes, sign-out: nothing of the previous person's media
// stays on a shared phone — staged picks and prepared uploads (I1), photo
// and poster bytes (I3), voice/video bytes (M3) — and no slow store holds
// the sign-out past its bound.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class _FakeCache implements ChatCacheService {
  int cleared = 0;
  @override
  Future<void> clearAll() async => cleared++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthService {
  bool signedOut = false;
  @override
  Future<void> signOut() async => signedOut = true;

  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A store whose emptyCache answers only when [release] completes (or
/// never): a slow or stuck cache database at sign-out.
class _StuckCacheManager implements BaseCacheManager {
  final release = Completer<void>();
  int emptied = 0;

  @override
  Future<void> emptyCache() async {
    emptied++;
    await release.future;
  }

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

class _RecordingImageCache implements ChatImageCache {
  int clears = 0;
  Completer<void>? hold;

  @override
  Future<void> clear() async {
    clears++;
    final gate = hold;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> removeKeys(Iterable<String> keys) async {}
}

class _Completer extends ImageStreamCompleter {}

void main() {
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('sign_out_media');
  });

  tearDown(() async {
    if (await support.exists()) await support.delete(recursive: true);
  });

  File seed(String folder, String name) =>
      File(p.join(support.path, folder, name))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);

  ({ProviderContainer container, _FakeAuth auth, _RecordingImageCache images})
  build({
    ChatImagePicker? picker,
    ChatMediaCache? mediaCache,
    _RecordingImageCache? images,
  }) {
    final auth = _FakeAuth();
    final imageCache = images ?? _RecordingImageCache();
    final container = ProviderContainer(
      overrides: [
        chatCacheServiceProvider.overrideWithValue(_FakeCache()),
        authServiceProvider.overrideWithValue(auth),
        routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
        chatImagePickerProvider.overrideWithValue(
          picker ?? ChatImagePicker(stagingDirectory: () async => support),
        ),
        chatMediaCacheProvider.overrideWithValue(
          mediaCache ??
              ChatMediaCache(manager: _StuckCacheManager()..release.complete()),
        ),
        chatImageCacheProvider.overrideWithValue(imageCache),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, auth: auth, images: imageCache);
  }

  test('I1: staged picks and prepared uploads with no live controller are '
      'gone after sign-out', () async {
    // A photo queued offline, its chat left long ago: no controller lives
    // to purge it, only these files and the queue row.
    final pick = seed(ChatImagePicker.folderName, 'pick_1.jpg');
    final upload = seed(ChatImagePicker.preparedFolderName, 'upload_1.jpg');
    final t = build();

    await t.container.read(authOperationsProvider).signOut();

    expect(pick.existsSync(), isFalse);
    expect(upload.existsSync(), isFalse);
    final picks = Directory(p.join(support.path, ChatImagePicker.folderName));
    final prepared = Directory(
      p.join(support.path, ChatImagePicker.preparedFolderName),
    );
    expect(picks.existsSync() ? picks.listSync() : const [], isEmpty);
    expect(prepared.existsSync() ? prepared.listSync() : const [], isEmpty);
    expect(t.auth.signedOut, isTrue);
  });

  test('I3: sign-out empties the photo/poster store', () async {
    final t = build();
    await t.container.read(authOperationsProvider).signOut();
    expect(t.images.clears, 1);
  });

  test('Flutter\'s in-memory ImageCache is emptied on sign-out', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.putIfAbsent('previous-persons-photo', () => _Completer());
    expect(cache.containsKey('previous-persons-photo'), isTrue);
    final t = build();
    await t.container.read(authOperationsProvider).signOut();
    expect(cache.containsKey('previous-persons-photo'), isFalse);
  });

  test('M3: a media cache clear that hangs does not hold sign-out past its '
      'bound, and its index is gone', () async {
    final indexPath = p.join(support.path, 'owners.index.json');
    final stuck = _StuckCacheManager();
    addTearDown(() {
      if (!stuck.release.isCompleted) stuck.release.complete();
    });
    final media = ChatMediaCache(
      manager: stuck,
      indexPath: indexPath,
      clearBound: const Duration(milliseconds: 100),
    );
    File(
      indexPath,
    ).writeAsStringSync('{"chat-media/v.m4a":{"r":"rel","m":["m1"]}}');
    final t = build(mediaCache: media);

    final watch = Stopwatch()..start();
    await t.container
        .read(authOperationsProvider)
        .signOut()
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('a stuck media cache held the sign-out'),
        );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(stuck.emptied, greaterThanOrEqualTo(1));
    expect(File(indexPath).existsSync(), isFalse);
    expect(t.auth.signedOut, isTrue);
  });

  test('the stores are wiped side by side: a slow one never delays the '
      'staging wipe', () async {
    final upload = seed(ChatImagePicker.preparedFolderName, 'upload_1.jpg');
    final images = _RecordingImageCache()..hold = Completer<void>();
    final t = build(images: images);
    final signOut = t.container.read(authOperationsProvider).signOut();
    for (var i = 0; i < 200 && upload.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(upload.existsSync(), isFalse);
    expect(t.auth.signedOut, isFalse, reason: 'still wiping the images');
    images.hold!.complete();
    await signOut;
    expect(t.auth.signedOut, isTrue);
  });
}
