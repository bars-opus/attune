import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/chat/presentation/screens/video_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';
import 'support/fake_voice_engine.dart';

/// Scriptable cache manager: [store] is what is on disk (by key),
/// [responses] maps a URL to bytes or a thrown error, [downloads] records
/// every network fetch.
class _FakeCacheManager implements BaseCacheManager {
  _FakeCacheManager(this.dir);
  final Directory dir;
  final Map<String, File> store = {};
  final Map<String, Object> responses = {};
  final List<String> downloads = [];
  int emptied = 0;

  /// When set, a download waits on it after its first progress event (a
  /// download still in flight).
  Completer<void>? gate;

  FileInfo _info(String key, File f) => FileInfo(
    const LocalFileSystem().file(f.path),
    FileSource.Cache,
    DateTime.now().add(const Duration(days: 1)),
    key,
  );

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final f = store[key];
    return f == null ? null : _info(key, f);
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    downloads.add(url);
    final response = responses[url];
    if (response is Object && response is! List<int>) throw response;
    final bytes = (response as List<int>?) ?? [1, 2, 3];
    yield DownloadProgress(url, bytes.length, bytes.length ~/ 2);
    final waitFor = gate;
    if (waitFor != null) await waitFor.future;
    // Keys are storage paths ('chat-media/x.m4a'): flattened to one file.
    final name = (key ?? '${url.hashCode}').replaceAll('/', '_');
    final f = File(p.join(dir.path, '$name.bin'))..writeAsBytesSync(bytes);
    store[key ?? url] = f;
    yield _info(key ?? url, f);
  }

  @override
  Future<void> removeFile(String key) async {
    store.remove(key);
  }

  @override
  Future<void> emptyCache() async {
    emptied++;
    store.clear();
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not used');
}

/// [_FakeCacheManager] whose emptyCache never finishes until [release]: a
/// slow store (400 files / 1 GB) or a stuck database at sign-out.
class _HangingEmptyCacheManager extends _FakeCacheManager {
  _HangingEmptyCacheManager(super.dir);

  /// Off until the test arms it: first use (no index yet) empties too.
  bool hang = false;
  bool emptyStarted = false;
  final release = Completer<void>();

  @override
  Future<void> emptyCache() async {
    if (hang) {
      emptyStarted = true;
      await release.future;
    }
    await super.emptyCache();
  }
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final Directory root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(root.path, 'support');
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(root.path, 'documents');
}

/// Video platform where a FILE source cannot be opened (a bad cached copy)
/// and a network source plays. [opened] records every source tried.
class _FileFailsVideoPlatform extends VideoPlayerPlatform {
  int _nextId = 0;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final List<String> opened = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final source = options.dataSource;
    opened.add(source.uri ?? '');
    if (source.sourceType == DataSourceType.file) {
      throw PlatformException(code: 'VideoError', message: 'cannot open');
    }
    final id = _nextId++;
    _events[id] = StreamController<VideoEvent>.broadcast(
      onListen:
          () => Future.microtask(
            () => _events[id]?.add(
              VideoEvent(
                eventType: VideoEventType.initialized,
                duration: const Duration(seconds: 3),
                size: const Size(720, 1280),
              ),
            ),
          ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

void main() {
  late Directory dir;
  late _FakeCacheManager manager;
  late ChatMediaCache cache;
  const key = 'chat-media/voice.m4a';
  const url = 'https://signed.test/voice.m4a?token=1';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('media_cache');
    manager = _FakeCacheManager(dir);
    cache = ChatMediaCache(manager: manager);
  });
  tearDown(() => dir.delete(recursive: true));

  test('downloads once, then plays from disk with no network', () async {
    final first = await cache.fetch(
      mediaKey: key,
      url: url,
      refreshUrl: () async => fail('not needed'),
    );
    final second = await cache.fetch(
      mediaKey: key,
      url: 'https://signed.test/voice.m4a?token=2',
      refreshUrl: () async => fail('not needed'),
    );
    expect(first, second);
    expect(File(first).existsSync(), isTrue);
    expect(manager.downloads, [url], reason: 'exactly one download');
  });

  test('reports progress on first fetch', () async {
    final seen = <double>[];
    await cache.fetch(
      mediaKey: key,
      url: url,
      refreshUrl: () async => null,
      onProgress: seen.add,
    );
    expect(seen, isNotEmpty);
    expect(seen.last, 1.0);
  });

  test('an empty cached file (killed mid-download) is a miss', () async {
    manager.store[key] = File(p.join(dir.path, 'empty.bin'))
      ..writeAsBytesSync([]);
    await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
    expect(manager.downloads, [url]);
  });

  test('an expired signed URL (403) is refreshed once and retried', () async {
    manager.responses[url] = HttpExceptionWithStatus(
      403,
      'expired',
      uri: Uri.parse(url),
    );
    var refreshed = 0;
    final path = await cache.fetch(
      mediaKey: key,
      url: url,
      refreshUrl: () async {
        refreshed++;
        return 'https://signed.test/voice.m4a?token=fresh';
      },
    );
    expect(refreshed, 1);
    expect(manager.downloads, [
      url,
      'https://signed.test/voice.m4a?token=fresh',
    ]);
    expect(File(path).existsSync(), isTrue);
  });

  test('a server error is rethrown (caller falls back to streaming)', () async {
    manager.responses[url] = HttpExceptionWithStatus(
      503,
      'down',
      uri: Uri.parse(url),
    );
    await expectLater(
      cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null),
      throwsA(isA<HttpExceptionWithStatus>()),
    );
  });

  test('cachedPath answers without network', () async {
    expect(await cache.cachedPath(key), isNull);
    await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
    expect(await cache.cachedPath(key), isNotNull);
    expect(manager.downloads.length, 1);
  });

  test('clear empties the store (sign-out)', () async {
    await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
    await cache.clear();
    expect(manager.emptied, 1);
    expect(await cache.cachedPath(key), isNull);
  });

  group('a clear that hangs (M3)', () {
    test('returns within its bound, and the index is gone first', () async {
      final indexPath = p.join(dir.path, 'owners.index.json');
      final hanging = _HangingEmptyCacheManager(dir);
      final bounded = ChatMediaCache(
        manager: hanging,
        indexPath: indexPath,
        clearBound: const Duration(milliseconds: 100),
      );
      await bounded.fetch(
        mediaKey: key,
        url: url,
        refreshUrl: () async => null,
        relationshipId: 'rel-1',
        messageIds: const {'m1'},
      );
      expect(File(indexPath).existsSync(), isTrue);
      hanging.hang = true;

      final watch = Stopwatch()..start();
      await bounded.clear().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('clear() held sign-out past its bound'),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(hanging.emptyStarted, isTrue);
      expect(
        File(indexPath).existsSync(),
        isFalse,
        reason: 'no index: the next open empties whatever the clear left',
      );
      hanging.release.complete();
    });

    test('the next open empties a cache whose clear was cut off', () async {
      final indexPath = p.join(dir.path, 'owners.index.json');
      final hanging = _HangingEmptyCacheManager(dir);
      final first = ChatMediaCache(
        manager: hanging,
        indexPath: indexPath,
        clearBound: const Duration(milliseconds: 50),
      );
      await first.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
      hanging.hang = true;
      await first.clear();
      // A later launch over the same store: no index → emptied before use.
      final next = ChatMediaCache(manager: manager, indexPath: indexPath);
      manager.store[key] = hanging.store[key]!;
      expect(await next.cachedPath(key), isNull);
      expect(manager.emptied, 1);
      hanging.release.complete();
    });

    test('M3: in the same run, the next use re-reads and empties what the '
        'cut-off clear left', () async {
      final indexPath = p.join(dir.path, 'owners.index.json');
      final hanging = _HangingEmptyCacheManager(dir);
      final cache = ChatMediaCache(
        manager: hanging,
        indexPath: indexPath,
        clearBound: const Duration(milliseconds: 50),
      );
      await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
      hanging.hang = true;
      await cache.clear();
      final before = hanging.emptied;
      hanging.hang = false;
      // Not trusted: the empty in-memory map must not stand in for a clear
      // that never finished.
      expect(await cache.cachedPath(key), isNull);
      expect(hanging.emptied, before + 1, reason: 'the next use emptied it');
      hanging.release.complete();
    });
  });

  test('sign-out wipes the media cache alongside the chat cache', () {
    final auth =
        File(
          'lib/features/auth/providers/auth_provider.dart',
        ).readAsStringSync();
    final signOut = auth.substring(auth.indexOf('Future<void> signOut()'));
    expect(signOut, contains('chatCacheServiceProvider).clearAll()'));
    expect(
      signOut.indexOf('chatMediaCacheProvider'),
      greaterThan(0),
      reason:
          'voice/video bytes of the previous person must not survive sign-out',
    );
  });

  group('deleted and purged messages take their bytes with them', () {
    Future<String> cacheFor(
      String mediaKey, {
      required String relationshipId,
      required Set<String> messageIds,
      ChatMediaCache? using,
    }) => (using ?? cache).fetch(
      mediaKey: mediaKey,
      url: 'https://signed.test/$mediaKey?token=1',
      refreshUrl: () async => null,
      relationshipId: relationshipId,
      messageIds: messageIds,
    );

    test('a removed message (client or server id) loses its bytes', () async {
      final gone = await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'srv-a', 'client-a'},
      );
      final kept = await cacheFor(
        'chat-media/b.m4a',
        relationshipId: 'rel-1',
        messageIds: {'srv-b', 'client-b'},
      );

      await cache.removeForMessages({'client-a'});

      expect(await cache.cachedPath('chat-media/a.m4a'), isNull);
      expect(
        File(gone).existsSync(),
        isFalse,
        reason: 'the file itself is deleted',
      );
      expect(await cache.cachedPath('chat-media/b.m4a'), kept);

      await cache.removeForMessages({'srv-b'});
      expect(await cache.cachedPath('chat-media/b.m4a'), isNull);
    });

    test(
      'a relationship purge removes only that relationship\'s bytes',
      () async {
        await cacheFor(
          'chat-media/a.m4a',
          relationshipId: 'rel-1',
          messageIds: {'a'},
        );
        await cacheFor(
          'chat-media/b.mp4',
          relationshipId: 'rel-2',
          messageIds: {'b'},
        );

        await cache.removeForRelationship('rel-1');

        expect(await cache.cachedPath('chat-media/a.m4a'), isNull);
        expect(await cache.cachedPath('chat-media/b.mp4'), isNotNull);
      },
    );

    test('who owns which bytes survives a restart', () async {
      final indexPath = p.join(dir.path, 'index.json');
      final before = ChatMediaCache(manager: manager, indexPath: indexPath);
      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'srv-a'},
        using: before,
      );

      // Next launch: a fresh instance over the same disk.
      final after = ChatMediaCache(manager: manager, indexPath: indexPath);
      await after.removeForMessages({'srv-a'});

      expect(await after.cachedPath('chat-media/a.m4a'), isNull);
      expect(manager.downloads, hasLength(1));
    });

    test('an unreadable ownership index empties the cache', () async {
      // Bytes whose message cannot be named could never be removed when
      // that message is deleted: start over rather than keep them.
      final indexPath = p.join(dir.path, 'index.json');
      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
        using: ChatMediaCache(manager: manager, indexPath: indexPath),
      );
      File(indexPath).writeAsStringSync('{not json');
      final emptiedBefore = manager.emptied;

      final after = ChatMediaCache(manager: manager, indexPath: indexPath);
      expect(await after.cachedPath('chat-media/a.m4a'), isNull);
      expect(manager.emptied, emptiedBefore + 1);
    });

    test('an index the OS purged on its own takes the bytes with it', () async {
      final indexPath = p.join(dir.path, 'index.json');
      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
        using: ChatMediaCache(manager: manager, indexPath: indexPath),
      );
      File(indexPath).deleteSync();

      final after = ChatMediaCache(manager: manager, indexPath: indexPath);
      expect(await after.cachedPath('chat-media/a.m4a'), isNull);
    });

    test('the total cached bytes are capped: oldest out first', () async {
      expect(ChatMediaCache.maxTotalBytes, 1024 * 1024 * 1024);
      final small = ChatMediaCache(manager: manager, byteBudget: 10);
      manager.responses['https://signed.test/chat-media/a.m4a?token=1'] =
          List<int>.filled(6, 1);
      manager.responses['https://signed.test/chat-media/b.m4a?token=1'] =
          List<int>.filled(6, 2);
      manager.responses['https://signed.test/chat-media/c.m4a?token=1'] =
          List<int>.filled(3, 3);

      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
        using: small,
      );
      await cacheFor(
        'chat-media/b.m4a',
        relationshipId: 'rel-1',
        messageIds: {'b'},
        using: small,
      );

      expect(
        await small.cachedPath('chat-media/a.m4a'),
        isNull,
        reason: '6 + 6 bytes is over a 10-byte budget',
      );
      expect(await small.cachedPath('chat-media/b.m4a'), isNotNull);

      await cacheFor(
        'chat-media/c.m4a',
        relationshipId: 'rel-1',
        messageIds: {'c'},
        using: small,
      );
      expect(
        await small.cachedPath('chat-media/b.m4a'),
        isNotNull,
        reason: '6 + 3 bytes fits',
      );
      expect(await small.cachedPath('chat-media/c.m4a'), isNotNull);
    });

    test('a play moves its bytes to the back of the eviction line', () async {
      final small = ChatMediaCache(manager: manager, byteBudget: 10);
      for (final name in ['a', 'b', 'c']) {
        manager.responses['https://signed.test/chat-media/$name.m4a?token=1'] =
            List<int>.filled(4, 1);
      }
      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
        using: small,
      );
      await cacheFor(
        'chat-media/b.m4a',
        relationshipId: 'rel-1',
        messageIds: {'b'},
        using: small,
      );
      // a is played again: b is now the oldest.
      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
        using: small,
      );
      await cacheFor(
        'chat-media/c.m4a',
        relationshipId: 'rel-1',
        messageIds: {'c'},
        using: small,
      );

      expect(await small.cachedPath('chat-media/a.m4a'), isNotNull);
      expect(await small.cachedPath('chat-media/b.m4a'), isNull);
    });

    test('the ownership index is capped at ${ChatMediaCache.maxIndexEntries} '
        'entries, its bytes going with the oldest record', () async {
      for (var i = 0; i <= ChatMediaCache.maxIndexEntries; i++) {
        await cacheFor(
          'chat-media/n$i.m4a',
          relationshipId: 'rel-1',
          messageIds: {'n$i'},
        );
      }
      expect(await cache.cachedPath('chat-media/n0.m4a'), isNull);
      expect(await cache.cachedPath('chat-media/n1.m4a'), isNotNull);
      expect(
        await cache.cachedPath(
          'chat-media/n${ChatMediaCache.maxIndexEntries}.m4a',
        ),
        isNotNull,
      );
      expect(manager.store, hasLength(ChatMediaCache.maxIndexEntries));
    });

    test(
      'bytes that cannot be deleted at the index cap do not stop caching',
      () async {
        await cacheFor(
          'chat-media/n0.m4a',
          relationshipId: 'rel-1',
          messageIds: {'n0'},
        );
        // n0's file sits where it cannot be deleted.
        final locked = Directory(p.join(dir.path, 'locked'))..createSync();
        final stuck = File(p.join(locked.path, 'n0.bin'))
          ..writeAsBytesSync([1]);
        manager.store['chat-media/n0.m4a'] = stuck;
        Process.runSync('chmod', ['555', locked.path]);
        addTearDown(() => Process.runSync('chmod', ['755', locked.path]));

        // One past the cap: n0's record is the one to go, and its delete fails.
        for (var i = 1; i <= ChatMediaCache.maxIndexEntries + 1; i++) {
          await cacheFor(
            'chat-media/n$i.m4a',
            relationshipId: 'rel-1',
            messageIds: {'n$i'},
          );
        }
        final last = 'chat-media/n${ChatMediaCache.maxIndexEntries + 1}.m4a';
        expect(await cache.cachedPath(last), isNotNull);
      },
    );

    test(
      'a location that fails once does not cost the index on disk',
      () async {
        final indexPath = p.join(dir.path, 'index.json');
        await cacheFor(
          'chat-media/a.m4a',
          relationshipId: 'rel-1',
          messageIds: {'a'},
          using: ChatMediaCache(manager: manager, indexPath: indexPath),
        );

        var calls = 0;
        final flaky = ChatMediaCache(
          manager: manager,
          indexLocation: () async {
            if (calls++ == 0) throw const FileSystemException('not yet');
            return indexPath;
          },
        );
        await flaky.cachedPath('chat-media/x.m4a'); // no location this time
        await cacheFor(
          'chat-media/b.m4a',
          relationshipId: 'rel-1',
          messageIds: {'b'},
          using: flaky,
        );

        await flaky.removeForMessages({'a'});
        expect(
          await flaky.cachedPath('chat-media/a.m4a'),
          isNull,
          reason: 'a\'s owner record survived on disk',
        );

        // ...and b's record reached the disk too.
        final next = ChatMediaCache(manager: manager, indexPath: indexPath);
        await next.removeForMessages({'b'});
        expect(await next.cachedPath('chat-media/b.m4a'), isNull);
      },
    );

    test('remove drops one key\'s bytes and record', () async {
      await cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
      );
      await cache.remove('chat-media/a.m4a');
      expect(await cache.cachedPath('chat-media/a.m4a'), isNull);
    });

    test(
      'a message removed while its bytes download does not keep them',
      () async {
        manager.gate = Completer<void>();
        final download = cacheFor(
          'chat-media/a.m4a',
          relationshipId: 'rel-1',
          messageIds: {'a'},
        );
        await Future<void>.delayed(Duration.zero);
        await cache.removeForMessages({'a'});
        manager.gate!.complete();

        await expectLater(download, throwsA(isA<ChatMediaRejected>()));
        expect(manager.store, isEmpty);
      },
    );

    test('a sign-out while bytes download does not keep them', () async {
      manager.gate = Completer<void>();
      final download = cacheFor(
        'chat-media/a.m4a',
        relationshipId: 'rel-1',
        messageIds: {'a'},
      );
      await Future<void>.delayed(Duration.zero);
      await cache.clear();
      manager.gate!.complete();

      await expectLater(download, throwsA(isA<ChatMediaRejected>()));
      expect(manager.store, isEmpty);
    });
  });

  group('downloads are verified before the cache commits them', () {
    // A real CacheManager over a scripted HTTP client: what the app runs,
    // minus the network.
    late Directory root;
    late PathProviderPlatform previous;
    final repos = <JsonCacheInfoRepository>[];

    setUp(() async {
      root = await Directory.systemTemp.createTemp('media_cache_real');
      previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(root);
    });
    final roots = <Directory>[];
    tearDown(() {
      // The JSON repo saves on a 3 s debounce timer, and the file system
      // creates its folder asynchronously: neither may land in a folder a
      // later test sees deleted, so the folders go once the group is done.
      for (final repo in repos) {
        repo.timer?.cancel();
      }
      repos.clear();
      PathProviderPlatform.instance = previous;
      roots.add(root);
    });
    tearDownAll(() async {
      for (final r in roots) {
        if (r.existsSync()) await r.delete(recursive: true);
      }
    });

    ({
      ChatMediaCache cache,
      CacheManager manager,
      JsonCacheInfoRepository repo,
      String files,
    })
    realCache(
      Future<http.StreamedResponse> Function(http.BaseRequest) handler, {
      Duration timeout = const Duration(seconds: 20),
    }) {
      final repo = JsonCacheInfoRepository.withFile(
        File(p.join(root.path, 'repo.json')),
      );
      repos.add(repo);
      final configKey = 'media_test_${root.path.hashCode}';
      // Where IOFileSystem puts this config's files (temp dir + its key).
      final files = p.join(root.path, 'tmp', configKey);
      final real = CacheManager(
        Config(
          configKey,
          repo: repo,
          fileService: ChatMediaFileService(
            client: MockClient.streaming((request, _) => handler(request)),
            timeout: timeout,
          ),
        ),
      );
      return (
        cache: ChatMediaCache(
          manager: real,
          cacheRepository: repo,
          filesDirectory: files,
        ),
        manager: real,
        repo: repo,
        files: files,
      );
    }

    http.StreamedResponse reply(
      int status,
      List<int> body, {
      String? contentType = 'audio/mp4',
      int? contentLength,
      bool unknownLength = false,
    }) => http.StreamedResponse(
      Stream.value(body),
      status,
      contentLength: unknownLength ? null : (contentLength ?? body.length),
      headers: {if (contentType != null) 'content-type': contentType},
    );

    Future<void> expectRejectedAndNotCached(
      ({
        ChatMediaCache cache,
        CacheManager manager,
        JsonCacheInfoRepository repo,
        String files,
      })
      c,
    ) async {
      await expectLater(
        c.cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null),
        throwsA(isA<ChatMediaRejected>()),
      );
      expect(await c.manager.getFileFromCache(key), isNull);
    }

    test(
      'a complete audio reply is cached under the key, with its type',
      () async {
        final c = realCache((_) async => reply(200, [1, 2, 3, 4]));
        final path = await c.cache.fetch(
          mediaKey: key,
          url: url,
          refreshUrl: () async => null,
        );
        expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
        expect(
          p.extension(path),
          '.m4a',
          reason: 'players pick the decoder from the extension',
        );
        expect(await c.cache.cachedPath(key), path);
      },
    );

    test(
      'an HTML page answered with 200 (captive portal) is not cached',
      () async {
        final c = realCache(
          (_) async => reply(
            200,
            utf8.encode('<html>log in</html>'),
            contentType: 'text/html; charset=utf-8',
          ),
        );
        await expectLater(
          c.cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null),
          throwsA(isA<ChatMediaRejected>()),
        );
        expect(await c.manager.getFileFromCache(key), isNull);
      },
    );

    test('a JSON error body is not cached', () async {
      final c = realCache(
        (_) async => reply(
          200,
          utf8.encode('{"error":"x"}'),
          contentType: 'application/json',
        ),
      );
      await expectLater(
        c.cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null),
        throwsA(isA<ChatMediaRejected>()),
      );
      expect(await c.manager.getFileFromCache(key), isNull);
    });

    test('a reply cut short is not cached', () async {
      final c = realCache(
        (_) async => reply(200, [1, 2, 3, 4], contentLength: 10),
      );
      await expectRejectedAndNotCached(c);
    });

    test('an empty reply is not cached', () async {
      final c = realCache((_) async => reply(200, const []));
      await expectRejectedAndNotCached(c);
    });

    test('an empty reply with no Content-Length is not cached', () async {
      final c = realCache(
        (_) async => reply(200, const [], unknownLength: true),
      );
      await expectRejectedAndNotCached(c);
    });

    test('a reply with no Content-Length is checked by what arrives', () async {
      final c = realCache(
        (_) async => reply(200, [5, 6, 7], unknownLength: true),
      );
      final path = await c.cache.fetch(
        mediaKey: key,
        url: url,
        refreshUrl: () async => null,
      );
      expect(File(path).readAsBytesSync(), [5, 6, 7]);
    });

    test(
      '202 Accepted (which the cache manager would keep) is refused',
      () async {
        final c = realCache((_) async => reply(202, [1, 2]));
        await expectRejectedAndNotCached(c);
      },
    );

    test('304 Not Modified (nothing to keep on a miss) is refused', () async {
      final c = realCache((_) async => reply(304, const []));
      await expectRejectedAndNotCached(c);
    });

    group('a stalled download is bounded', () {
      const bound = Duration(milliseconds: 80);

      test('no reply at all: fetch fails within the bound', () async {
        final c = realCache(
          (_) => Completer<http.StreamedResponse>().future,
          timeout: bound,
        );
        final watch = Stopwatch()..start();
        await expectRejectedAndNotCached(c);
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      });

      test('a body that stops arriving: fetch fails within the bound, and '
          'nothing is kept', () async {
        final c = realCache(
          (_) async => http.StreamedResponse(
            // One chunk, then silence: the connection never closes.
            Stream<List<int>>.multi((sink) => sink.add([1, 2])),
            200,
            contentLength: 10,
            headers: {'content-type': 'audio/mp4'},
          ),
          timeout: bound,
        );
        final watch = Stopwatch()..start();
        await expectRejectedAndNotCached(c);
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      });

      test(
        'the next open starts a fresh download (not the dead one)',
        () async {
          var calls = 0;
          final c = realCache((_) async {
            calls++;
            if (calls == 1) {
              return http.StreamedResponse(
                Stream<List<int>>.multi((_) {}),
                200,
                contentLength: 4,
                headers: {'content-type': 'audio/mp4'},
              );
            }
            return reply(200, [1, 2, 3, 4]);
          }, timeout: bound);
          await expectRejectedAndNotCached(c);

          final path = await c.cache.fetch(
            mediaKey: key,
            url: url,
            refreshUrl: () async => null,
          );
          expect(calls, 2);
          expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
        },
      );

      test(
        'a voice note whose download stalls streams the signed URL',
        () async {
          final repo = FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true;
          final engine = FakeVoiceEngine();
          final c = realCache(
            (_) async => http.StreamedResponse(
              Stream<List<int>>.multi((_) {}),
              200,
              contentLength: 4,
              headers: {'content-type': 'audio/mp4'},
            ),
            timeout: bound,
          );
          final container = buildChatContainer(
            repository: repo,
            userId: 'u1',
            extraOverrides: [
              voicePlaybackEngineProvider.overrideWithValue(engine),
              chatMediaCacheProvider.overrideWithValue(c.cache),
            ],
          );
          addTearDown(container.dispose);
          final voice = container.read(
            voicePlaybackControllerProvider.notifier,
          );

          await voice.toggle(
            'c1',
            () => voice.signedUrlFor('chat-media/v.m4a'),
            mediaKey: 'chat-media/v.m4a',
            ownerId: 'rel-1',
          );

          expect(
            engine.lastSource,
            'https://signed.test/chat-media/v.m4a?token=abc',
          );
          expect(engine.lastIsLocalFile, isFalse);
          expect(voice.state.isLoading, isFalse);
          expect(voice.state.isPlaying, isTrue);
          // Tapping again works (it pauses; nothing is stuck loading).
          await voice.toggle(
            'c1',
            () => voice.signedUrlFor('chat-media/v.m4a'),
            mediaKey: 'chat-media/v.m4a',
          );
          expect(voice.state.isPlaying, isFalse);
          await voice.stop();
        },
      );

      test('a voice note on a trickling link streams after the give-up; the '
          'late download only fills the cache', () async {
        const voiceKey = 'chat-media/v.m4a';
        const signedUrl = 'https://signed.test/chat-media/v.m4a?token=abc';
        final repo = FakeChatRepository(currentUserId: 'u1')
          ..signMediaUrls = true;
        final engine = FakeVoiceEngine();
        final body = StreamController<List<int>>();
        // Never silent long enough for the 20 s inactivity bound: one byte
        // every 100 ms, 6 in all.
        final c = realCache(
          (_) async => http.StreamedResponse(
            body.stream,
            200,
            contentLength: 6,
            headers: {'content-type': 'audio/mp4'},
          ),
        );
        final container = buildChatContainer(
          repository: repo,
          userId: 'u1',
          extraOverrides: [
            voicePlaybackEngineProvider.overrideWithValue(engine),
            chatMediaCacheProvider.overrideWithValue(c.cache),
            voicePlaybackBufferingGiveUpProvider.overrideWithValue(
              const Duration(milliseconds: 150),
            ),
          ],
        );
        addTearDown(container.dispose);
        final voice = container.read(voicePlaybackControllerProvider.notifier);
        var sent = 0;
        final trickle = Timer.periodic(const Duration(milliseconds: 100), (t) {
          body.add([sent++]);
          if (sent == 6) {
            t.cancel();
            body.close();
          }
        });
        addTearDown(trickle.cancel);

        final watch = Stopwatch()..start();
        await voice.toggle(
          'c1',
          () => voice.signedUrlFor(voiceKey),
          mediaKey: voiceKey,
          ownerId: 'rel-1',
          serverMessageId: 'srv-1',
        );

        expect(
          watch.elapsed,
          lessThan(const Duration(milliseconds: 450)),
          reason: 'streams at the give-up, not when the file is whole',
        );
        expect(engine.lastSource, signedUrl);
        expect(engine.lastIsLocalFile, isFalse);

        // The download finishes later: cached and owned, and nothing plays.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        expect(engine.calls.where((call) => call == 'play'), hasLength(1));
        expect(engine.lastSource, signedUrl);
        expect(await c.cache.cachedPath(voiceKey), isNotNull);
        await c.cache.removeForMessages({'srv-1'});
        expect(
          await c.cache.cachedPath(voiceKey),
          isNull,
          reason: 'its owner was recorded',
        );
        await voice.stop();
      });
    });

    test('an old orphan partial file is swept on first use; committed bytes '
        'stay', () async {
      final old = DateTime.now().subtract(const Duration(hours: 1));
      final c = realCache((_) async => reply(200, [1, 2, 3, 4]));
      final kept = await c.cache.fetch(
        mediaKey: key,
        url: url,
        refreshUrl: () async => null,
      );
      File(kept).setLastModifiedSync(old);
      final orphan =
          File(p.join(c.files, 'dead.m4a'))
            ..writeAsBytesSync([9])
            ..setLastModifiedSync(old);

      // Next launch over the same disk.
      final next = ChatMediaCache(
        manager: c.manager,
        cacheRepository: c.repo,
        filesDirectory: c.files,
      );
      expect(await next.cachedPath(key), kept);
      expect(orphan.existsSync(), isFalse, reason: 'no database row: orphan');
      expect(File(kept).existsSync(), isTrue, reason: 'has a row: kept');
    });

    test(
      'a failed download sweeps old orphans, never a download in flight',
      () async {
        final old = DateTime.now().subtract(const Duration(hours: 1));
        final held = StreamController<List<int>>();
        final c = realCache((request) async {
          if (request.url.path.endsWith('held.m4a')) {
            return http.StreamedResponse(
              held.stream,
              200,
              contentLength: 4,
              headers: {'content-type': 'audio/mp4'},
            );
          }
          return reply(404, const []);
        });
        await c.cache.cachedPath('chat-media/warm-up.m4a'); // first-use sweep
        final orphan =
            File(p.join(c.files, 'dead.m4a'))
              ..createSync(recursive: true)
              ..writeAsBytesSync([9])
              ..setLastModifiedSync(old);

        held.add([1, 2]);
        final inFlight = c.cache.fetch(
          mediaKey: 'chat-media/held.m4a',
          url: 'https://signed.test/chat-media/held.m4a?token=1',
          refreshUrl: () async => null,
        );
        List<File> partials() =>
            Directory(c.files)
                .listSync()
                .whereType<File>()
                .where((f) => f.path != orphan.path)
                .toList();
        for (var i = 0; i < 200 && partials().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final partial = partials().single;

        await expectLater(
          c.cache.fetch(
            mediaKey: 'chat-media/gone.m4a',
            url: 'https://signed.test/chat-media/gone.m4a?token=1',
            refreshUrl: () async => null,
          ),
          throwsA(isA<HttpExceptionWithStatus>()),
        );
        expect(
          orphan.existsSync(),
          isFalse,
          reason: 'swept after the failed download',
        );
        expect(partial.existsSync(), isTrue, reason: 'still downloading');

        held.add([3, 4]);
        await held.close();
        final path = await inFlight;
        expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
      },
    );

    test('a reply larger than any chat media is refused unread', () async {
      final c = realCache(
        (_) async => reply(200, [
          1,
        ], contentLength: ChatMediaFileService.defaultMaxBytes + 1),
      );
      await expectLater(
        c.cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null),
        throwsA(isA<ChatMediaRejected>()),
      );
      expect(await c.manager.getFileFromCache(key), isNull);
    });

    test('an expired token (403) is re-signed once; the error body is never '
        'cached', () async {
      final asked = <String>[];
      final c = realCache((request) async {
        asked.add(request.url.toString());
        return request.url.queryParameters['token'] == 'fresh'
            ? reply(200, [9, 9])
            : reply(
              403,
              utf8.encode('{"error":"expired"}'),
              contentType: 'application/json',
            );
      });
      final path = await c.cache.fetch(
        mediaKey: key,
        url: url,
        refreshUrl: () async => 'https://signed.test/voice.m4a?token=fresh',
      );
      expect(asked, hasLength(2));
      expect(File(path).readAsBytesSync(), [9, 9]);
    });
  });

  test(
    'everything lives in the OS cache directory, which no backup carries',
    () async {
      // iOS Library/Caches and Android cacheDir are excluded from iCloud /
      // device backup and from Auto Backup / device transfer by the OS, so
      // unlike chat_picks/ (Application Support) no exclusion is needed —
      // as long as nothing lands in Application Support or Documents.
      final root = await Directory.systemTemp.createTemp('media_locations');
      addTearDown(() => root.delete(recursive: true));
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(root);
      addTearDown(() => PathProviderPlatform.instance = previous);

      final at = await ChatMediaCache.storageLocations();
      final temp = p.join(root.path, 'tmp');
      for (final path in [at.files, at.database, at.index]) {
        expect(p.isWithin(temp, path), isTrue, reason: '$path is backed up');
      }
      expect(
        at.files,
        p.join(temp, ChatMediaCache.cacheKey),
        reason: 'flutter_cache_manager\'s IOFileSystem stores files here',
      );
    },
  );

  group('voice plays from the cache (VoicePlaybackController)', () {
    late FakeChatRepository repo;
    late ProviderContainer container;
    late FakeVoiceEngine engine;
    VoicePlaybackController voice() =>
        container.read(voicePlaybackControllerProvider.notifier);
    const voiceKey = 'chat-media/v.m4a';
    const signed = 'https://signed.test/chat-media/v.m4a?token=abc';

    ProviderContainer launch({ChatMediaCache? using}) {
      engine = FakeVoiceEngine();
      final launched = buildChatContainer(
        repository: repo,
        userId: 'u1',
        extraOverrides: [
          voicePlaybackEngineProvider.overrideWithValue(engine),
          chatMediaCacheProvider.overrideWithValue(using ?? cache),
        ],
      );
      addTearDown(launched.dispose);
      return launched;
    }

    setUp(() {
      repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
      container = launch();
    });

    Future<String?> resolveSigned() => voice().signedUrlFor(voiceKey);

    Future<void> play() => voice().toggle(
      'c1',
      resolveSigned,
      mediaKey: voiceKey,
      ownerId: 'rel-1',
      serverMessageId: 'srv-1',
    );

    Future<void> finish() async {
      engine.positionsController.add(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      engine.completionsController.add(null);
      await Future<void>.delayed(Duration.zero);
    }

    test('the first play downloads once and plays the file; a replay uses '
        'the file', () async {
      await play();
      expect(manager.downloads, [signed]);
      expect(engine.lastIsLocalFile, isTrue);
      expect(engine.lastSource, startsWith(dir.path));
      await finish();

      await play();
      expect(manager.downloads, hasLength(1));
      expect(engine.lastIsLocalFile, isTrue);
      expect(voice().state.isPlaying, isTrue);
    });

    test('after a restart, offline, a note played before still plays with '
        'no signing at all', () async {
      await play();
      await finish();

      // Next launch (no signed URL held in memory), and no network.
      container.dispose();
      container = launch();
      repo.signMediaUrls = false;
      final signsBefore = repo.signedUrlRequests.length;
      await play();

      expect(voice().state.isPlaying, isTrue);
      expect(engine.lastIsLocalFile, isTrue);
      expect(engine.lastSource, startsWith(dir.path));
      expect(
        repo.signedUrlRequests.length,
        signsBefore,
        reason: 'cached bytes are played before anything is signed',
      );
    });

    test('a replayed note goes to the back of the eviction line', () async {
      final small = ChatMediaCache(manager: manager, byteBudget: 10);
      container.dispose();
      container = launch(using: small);
      Future<void> playNote(String id) => voice().toggle(
        id,
        () => voice().signedUrlFor('chat-media/$id.m4a'),
        mediaKey: 'chat-media/$id.m4a',
        ownerId: 'rel-1',
        serverMessageId: 'srv-$id',
      );
      for (final id in ['a', 'b', 'c']) {
        manager.responses['https://signed.test/chat-media/$id.m4a?token=abc'] =
            List<int>.filled(4, 1);
      }

      await playNote('a');
      await finish();
      await playNote('b');
      await finish();
      await playNote('a'); // a replay, from the cache
      await finish();
      await playNote('c'); // 12 bytes > 10: the least recently played goes
      await finish();

      expect(
        await small.cachedPath('chat-media/a.m4a'),
        isNotNull,
        reason: 'played most recently but one',
      );
      expect(await small.cachedPath('chat-media/b.m4a'), isNull);
      expect(await small.cachedPath('chat-media/c.m4a'), isNotNull);
    });

    test('a download that fails streams the signed URL instead', () async {
      manager.responses[signed] = HttpExceptionWithStatus(
        503,
        'down',
        uri: Uri.parse(signed),
      );
      await play();
      expect(engine.lastSource, signed);
      expect(engine.lastIsLocalFile, isFalse);
      expect(voice().state.isPlaying, isTrue);
    });

    test('a cached file that will not play is dropped and the URL streamed '
        'once', () async {
      await play();
      await finish();
      engine.nextPlayError = Exception('undecodable');

      await play();

      expect(engine.lastSource, signed);
      expect(engine.lastIsLocalFile, isFalse);
      expect(voice().state.isPlaying, isTrue);
      expect(
        await cache.cachedPath(voiceKey),
        isNull,
        reason: 'the next play downloads it again',
      );
    });

    test('the heal-once retry borrows the audio session once (chat review '
        '#40)', () async {
      final session = container.read(audioSessionProvider);
      await play();
      await finish();
      expect(session.playbackHeld, isFalse);
      engine.nextPlayError = Exception('undecodable');

      await play(); // cached file refused → dropped → URL streamed

      expect(engine.lastSource, signed);
      expect(
        engine.contexts,
        hasLength(2),
        reason: 'one borrow per play; the retry reuses the hold',
      );
      expect(session.playbackHeld, isTrue);
      await finish();
      expect(
        session.playbackHeld,
        isFalse,
        reason: 'a second hold from the retry would leak here',
      );
    });

    test('a heal-once retry that also fails holds nothing', () async {
      final session = container.read(audioSessionProvider);
      await play();
      await finish();
      engine.nextPlayError = Exception('undecodable');

      // The cached file is refused; the stream it falls back to is refused
      // too (resolve runs only for that retry, the cache hit skips it).
      await voice().toggle('c1', () async {
        engine.nextPlayError = Exception('no codec either');
        return resolveSigned();
      }, mediaKey: voiceKey, ownerId: 'rel-1', serverMessageId: 'srv-1');

      expect(voice().state.failedMessageId, 'c1');
      expect(session.playbackHeld, isFalse);
    });

    test('a just-recorded file on this device is played as it is', () async {
      final local = File(p.join(dir.path, 'mine.m4a'))..writeAsBytesSync([1]);
      await voice().toggle(
        'c1',
        () async => local.path,
        mediaKey: voiceKey,
        ownerId: 'rel-1',
      );
      expect(engine.lastSource, local.path);
      expect(manager.downloads, isEmpty);
    });

    test('a note deleted on the server loses its cached bytes (removals '
        'bus)', () async {
      await play();
      await finish();
      expect(await cache.cachedPath(voiceKey), isNotNull);

      container.read(chatMessageRemovalsProvider).announce({'srv-1'});
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(await cache.cachedPath(voiceKey), isNull);
    });
  });

  group('chat controller paths that remove cached bytes', () {
    const userId = 'u1';
    const relId = 'rel-1';

    Future<
      ({
        ChatController controller,
        FakeChatRepository repo,
        ProviderContainer container,
      })
    >
    boot() async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.seedIncoming(
        id: 'm-1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime(2026, 10, 18, 9),
        mediaType: 'audio',
      );
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        extraOverrides: [chatMediaCacheProvider.overrideWithValue(cache)],
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return (controller: controller, repo: repo, container: container);
    }

    Future<void> cacheNote(String messageId, {String relationship = relId}) =>
        cache.fetch(
          mediaKey: 'chat-media/$messageId.m4a',
          url: 'https://signed.test/$messageId.m4a?token=1',
          refreshUrl: () async => null,
          relationshipId: relationship,
          messageIds: {messageId, 'seed-$messageId'},
        );

    test('the conversation archived (purge) removes its bytes, not another '
        'relationship\'s', () async {
      final b = await boot();
      await cacheNote('m-1');
      await cacheNote('x-9', relationship: 'rel-other');
      b.repo.conversationOverride = activeConversation(
        relId,
      ).copyWith(availability: ConversationAvailability.archived);

      await b.controller.debugRefreshConversation();

      expect(await cache.cachedPath('chat-media/m-1.m4a'), isNull);
      expect(await cache.cachedPath('chat-media/x-9.m4a'), isNotNull);
    });

    test('the conversation gone (purge) removes its bytes', () async {
      final b = await boot();
      await cacheNote('m-1');
      b.repo.returnNullConversation = true;

      await b.controller.debugRefreshConversation();

      expect(await cache.cachedPath('chat-media/m-1.m4a'), isNull);
    });

    test('deleting a message removes its bytes', () async {
      final b = await boot();
      await cacheNote('m-1');
      final message = b.controller.state.messages.firstWhere(
        (m) => m.id == 'm-1',
      );

      await b.controller.deleteMessage(message);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(await cache.cachedPath('chat-media/m-1.m4a'), isNull);
    });

    test(
      'a deletion learned by the changes-since sync removes its bytes',
      () async {
        final b = await boot();
        await cacheNote('m-1');
        b.repo.serverMessages['m-1'] = b.repo.serverMessages['m-1']!.copyWith(
          deletedAt: DateTime(2026, 10, 18, 10),
          content: '',
        );
        b.repo.touch('m-1', DateTime(2026, 10, 18, 10));

        await b.controller.syncChangesSinceCursor();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(await cache.cachedPath('chat-media/m-1.m4a'), isNull);
      },
    );
  });

  testWidgets('the viewer shows a download ring, then plays the local file', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final message = Message(
      id: 'srv-1',
      clientMessageId: 'c1',
      relationshipId: 'rel',
      senderId: 'partner',
      content: '',
      createdAt: DateTime(2026, 10, 18),
      status: MessageStatus.delivered,
      isMine: false,
      mediaKey: 'chat-media/clip.mp4',
      mediaType: 'video',
      mediaDurationMs: 3000,
      mediaWidth: 720,
      mediaHeight: 1280,
    );
    manager.gate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatMediaCacheProvider.overrideWithValue(
            ChatMediaCache(manager: manager),
          ),
        ],
        child: MaterialApp(
          home: VideoViewerScreen(videos: [message], initialIndex: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('video_download_ring')), findsOneWidget);
    manager.gate!.complete();
    await tester.pumpAndSettle();
    final player = tester.widget<VideoMessagePlayer>(
      find.byType(VideoMessagePlayer),
    );
    expect(
      player.videoUrl,
      startsWith(dir.path),
      reason: 'plays the cached file',
    );
    expect(manager.downloads, hasLength(1));
  });

  testWidgets('a view-once video is never written to the cache', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final message = Message(
      id: 'srv-2',
      clientMessageId: 'c2',
      relationshipId: 'rel',
      senderId: 'partner',
      content: '',
      createdAt: DateTime(2026, 10, 18),
      status: MessageStatus.delivered,
      isMine: false,
      mediaKey: 'chat-media/once.mp4',
      mediaType: 'video',
      isViewOnce: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatMediaCacheProvider.overrideWithValue(
            ChatMediaCache(manager: manager),
          ),
        ],
        child: MaterialApp(
          home: VideoViewerScreen(videos: [message], initialIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final player = tester.widget<VideoMessagePlayer>(
      find.byType(VideoMessagePlayer),
    );
    expect(player.videoUrl, startsWith('https://'));
    expect(manager.downloads, isEmpty);
  });

  Message clip({String id = 'srv-1', String client = 'c1'}) => Message(
    id: id,
    clientMessageId: client,
    relationshipId: 'rel',
    senderId: 'partner',
    content: '',
    createdAt: DateTime(2026, 10, 18),
    status: MessageStatus.delivered,
    isMine: false,
    mediaKey: 'chat-media/clip.mp4',
    mediaType: 'video',
    mediaDurationMs: 3000,
    mediaWidth: 720,
    mediaHeight: 1280,
  );

  testWidgets('a download that fails or stalls leaves the ring for the '
      'stream', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    const signed = 'https://signed.test/chat-media/clip.mp4?token=abc';
    manager.responses[signed] = const ChatMediaRejected('stalled');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatMediaCacheProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(
          home: VideoViewerScreen(videos: [clip()], initialIndex: 0),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const ValueKey('video_download_ring')), findsNothing);
    final player = tester.widget<VideoMessagePlayer>(
      find.byType(VideoMessagePlayer),
    );
    expect(player.videoUrl, signed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cached video that will not open is dropped and streamed '
      'once', (tester) async {
    final previous = VideoPlayerPlatform.instance;
    final platform = _FileFailsVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    // Already on disk from an earlier open.
    final cachedFile = await cache.fetch(
      mediaKey: 'chat-media/clip.mp4',
      url: 'https://signed.test/old',
      refreshUrl: () async => null,
      relationshipId: 'rel',
      messageIds: {'srv-1', 'c1'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatMediaCacheProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(
          home: VideoViewerScreen(videos: [clip()], initialIndex: 0),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.opened, hasLength(2));
    expect(platform.opened.first, contains(p.basename(cachedFile)));
    expect(platform.opened.last, startsWith('https://signed.test/'));
    expect(
      manager.store.containsKey('chat-media/clip.mp4'),
      isFalse,
      reason: 'the next open downloads a good copy',
    );
    await tester.pumpWidget(const SizedBox()); // disposes the player
  });
}
