import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:file/file.dart' as file_system;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Records what was signed and downloaded so the tests can assert on the
/// work the prewarmer actually did, rather than on its return value (it
/// deliberately returns nothing and swallows failures).
class _RecordingCacheManager implements BaseCacheManager {
  _RecordingCacheManager({
    Map<String, File> alreadyCached = const {},
    this.onDownload,
    this.seedTargetPath,
  }) : alreadyCached = Map.of(alreadyCached);

  /// Keys that a previous session already left on disk.
  final Map<String, File> alreadyCached;

  /// Lets a test make a specific download fail.
  final void Function(String key)? onDownload;
  final String? seedTargetPath;

  final List<String> cacheLookups = [];
  final List<String> downloadedKeys = [];
  final List<String> downloadedUrls = [];
  final List<String> seededKeys = [];

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    cacheLookups.add(key);
    final file = alreadyCached[key];
    if (file == null) return null;
    return FileInfo(
      const LocalFileSystem().file(file.path),
      FileSource.Cache,
      DateTime.now().add(const Duration(days: 7)),
      key,
    );
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    onDownload?.call(key ?? url);
    downloadedKeys.add(key ?? url);
    downloadedUrls.add(url);
    return FileInfo(
      const LocalFileSystem().file('/dev/null'),
      FileSource.Online,
      DateTime.now().add(const Duration(days: 7)),
      key ?? url,
    );
  }

  @override
  Future<file_system.File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    final path = seedTargetPath;
    if (path == null) throw StateError('No seed target configured');
    final target = const LocalFileSystem().file(path);
    final sink = target.openWrite();
    await sink.addStream(source);
    await sink.close();
    final stableKey = key ?? url;
    seededKeys.add(stableKey);
    alreadyCached[stableKey] = File(path);
    return target;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by the prewarmer',
      );
}

Message videoMessage(String id, {String? thumbKey, bool isViewOnce = false}) {
  return Message(
    id: id,
    clientMessageId: 'cid-$id',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content: '',
    createdAt: DateTime.now(),
    mediaKey: 'chat-media/rel-1/$id.mp4',
    mediaType: 'video',
    mediaThumbnailKey: thumbKey,
    isViewOnce: isViewOnce,
    status: MessageStatus.sent,
    isMine: false,
  );
}

void main() {
  late FakeChatRepository repo;

  setUp(() {
    ChatPosterPrewarmer.debugClearReadyPosterPaths();
    repo = FakeChatRepository(currentUserId: 'me')
      // The prewarmer's whole job is signing-then-downloading, so it needs
      // real URLs back rather than the harness's default null.
      ..signMediaUrls = true;
  });

  tearDown(ChatPosterPrewarmer.debugClearReadyPosterPaths);

  test(
    'discovers an existing cache path for synchronous first paint',
    () async {
      final dir = Directory.systemTemp.createTempSync('poster_discovery');
      addTearDown(() => dir.deleteSync(recursive: true));
      final existing = File('${dir.path}/poster.jpg')..writeAsStringSync('x');
      const key = 'chat-media/rel-1/discovered-poster.jpg';
      final prewarmer = ChatPosterPrewarmer(
        repository: repo,
        cacheManager: _RecordingCacheManager(alreadyCached: {key: existing}),
      );

      await prewarmer.discoverCached([videoMessage('m1', thumbKey: key)]);

      expect(ChatPosterPrewarmer.readyPosterPathFor(key), existing.path);
      expect(repo.signedUrlRequests, isEmpty);
    },
  );

  test('seeds a generated local poster under its stable storage key', () async {
    final dir = Directory.systemTemp.createTempSync('poster_seed');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File('${dir.path}/staged.jpg')..writeAsStringSync('poster');
    final targetPath = '${dir.path}/cached.jpg';
    const key = 'chat-media/rel-1/seeded-poster.jpg';
    final cache = _RecordingCacheManager(seedTargetPath: targetPath);
    final prewarmer = ChatPosterPrewarmer(
      repository: repo,
      cacheManager: cache,
    );

    final cachedPath = await prewarmer.cacheLocalPoster(
      key: key,
      localPath: source.path,
    );

    expect(cachedPath, targetPath);
    expect(cache.seededKeys, [key]);
    expect(File(targetPath).readAsStringSync(), 'poster');
    expect(ChatPosterPrewarmer.readyPosterPathFor(key), targetPath);
  });

  test(
    'downloads a poster that is not on disk, keyed by its storage path',
    () async {
      final cache = _RecordingCacheManager();
      final prewarmer = ChatPosterPrewarmer(
        repository: repo,
        cacheManager: cache,
      );

      await prewarmer.prewarm([
        videoMessage('m1', thumbKey: 'chat-media/rel-1/m1-poster.jpg'),
      ]);

      // Stored under the STABLE storage key rather than the signed URL, which
      // is what lets the tile's own by-key lookup find it and what keeps a
      // later re-sign hitting the same entry.
      expect(cache.downloadedKeys, ['chat-media/rel-1/m1-poster.jpg']);
    },
  );

  test('skips a poster already on disk without re-signing it', () async {
    final dir = Directory.systemTemp.createTempSync('prewarm');
    addTearDown(() => dir.deleteSync(recursive: true));
    final existing = File('${dir.path}/p.jpg')..writeAsStringSync('x');

    final cache = _RecordingCacheManager(
      alreadyCached: {'chat-media/rel-1/m1-poster.jpg': existing},
    );
    final prewarmer = ChatPosterPrewarmer(
      repository: repo,
      cacheManager: cache,
    );

    await prewarmer.prewarm([
      videoMessage('m1', thumbKey: 'chat-media/rel-1/m1-poster.jpg'),
    ]);

    // The common case on every open after the first: no download, and no
    // signing request competing with the message fetch the user is waiting
    // on.
    expect(cache.downloadedKeys, isEmpty);
    expect(repo.signedUrlRequests, isEmpty);
  });

  test('ignores messages with no poster key and view-once videos', () async {
    final cache = _RecordingCacheManager();
    final prewarmer = ChatPosterPrewarmer(
      repository: repo,
      cacheManager: cache,
    );

    await prewarmer.prewarm([
      videoMessage('m1'), // no thumbnail key at all
      videoMessage(
        'm2',
        thumbKey: 'chat-media/rel-1/m2-poster.jpg',
        // A view-once poster is deliberately not persisted server-side;
        // fetching it would fail and defeat the ephemerality.
        isViewOnce: true,
      ),
    ]);

    expect(cache.downloadedKeys, isEmpty);
  });

  test('does not re-attempt a key within the same session', () async {
    final cache = _RecordingCacheManager();
    final prewarmer = ChatPosterPrewarmer(
      repository: repo,
      cacheManager: cache,
    );
    final messages = [
      videoMessage('m1', thumbKey: 'chat-media/rel-1/m1-poster.jpg'),
    ];

    // Chat open runs several passes (warm cache, then the fresh load), and
    // realtime triggers more — without the guard each one would re-sign and
    // re-check the same keys.
    await prewarmer.prewarm(messages);
    await prewarmer.prewarm(messages);
    await prewarmer.prewarm(messages);

    expect(cache.downloadedKeys, hasLength(1));
  });

  test('a failing download never throws and does not block the rest', () async {
    final cache = _RecordingCacheManager(
      onDownload: (key) {
        if (key.contains('m1')) throw Exception('network down');
      },
    );
    final prewarmer = ChatPosterPrewarmer(
      repository: repo,
      cacheManager: cache,
    );

    await prewarmer.prewarm([
      videoMessage('m1', thumbKey: 'chat-media/rel-1/m1-poster.jpg'),
      videoMessage('m2', thumbKey: 'chat-media/rel-1/m2-poster.jpg'),
    ]);

    // Strictly an accelerator: a poster that fails to prewarm just loads
    // later through the tile's own path, and its neighbours still warm.
    expect(cache.downloadedKeys, contains('chat-media/rel-1/m2-poster.jpg'));
  });

  test('prewarms newest-first and caps the number per pass', () async {
    final cache = _RecordingCacheManager();
    final prewarmer = ChatPosterPrewarmer(
      repository: repo,
      cacheManager: cache,
    );

    // ChatState stores messages newest-first, matching the server query and
    // the reverse ListView's data contract. m39 is newest and therefore sits
    // at index 0; m0 is the oldest entry at the end of the list.
    final messages = [
      for (var i = 39; i >= 0; i--)
        videoMessage('m$i', thumbKey: 'chat-media/rel-1/m$i-poster.jpg'),
    ];

    await prewarmer.prewarm(messages);

    // Capped, so opening a media-heavy chat doesn't put 40 signing requests
    // on the wire at once...
    expect(cache.downloadedKeys.length, lessThan(40));
    // ...and the newest poster is fetched while the oldest is left for the
    // tile's own path.
    expect(cache.downloadedKeys, contains('chat-media/rel-1/m39-poster.jpg'));
    expect(
      cache.downloadedKeys,
      isNot(contains('chat-media/rel-1/m0-poster.jpg')),
    );
  });
}
