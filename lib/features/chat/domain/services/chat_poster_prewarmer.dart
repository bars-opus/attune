import 'dart:async';
import 'dart:io' as io;

import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

/// Downloads video posters into the disk cache ahead of the tiles that
/// display them.
///
/// Without this, the first fetch of a poster begins when its tile mounts,
/// which is one or two frames AFTER the message list is already on screen —
/// so the tile necessarily paints a placeholder first and the poster appears
/// a beat later. That is the residual flash that survives once the tile
/// itself is doing everything right: the tile cannot paint bytes that have
/// not been fetched, and nothing had asked for them yet.
///
/// It matters most on the RECEIVING side, which never had a local copy of
/// the poster the way a sender does. Prewarming closes that gap: by the time
/// tiles mount, [VideoMessageThumbnail]'s by-key disk lookup hits and paints
/// on its first frame.
///
/// Every failure is swallowed. A poster that does not prewarm simply loads
/// the way it did before — later, through the tile's own path — so this is
/// strictly an accelerator and never a new way for the chat to break.
class ChatPosterPrewarmer {
  ChatPosterPrewarmer({
    required ChatRepository repository,
    BaseCacheManager? cacheManager,
  }) : _repository = repository,
       _injectedCacheManager = cacheManager;

  final ChatRepository _repository;
  final BaseCacheManager? _injectedCacheManager;
  BaseCacheManager? _resolvedCacheManager;

  /// Cache-manager metadata is asynchronous, but widget construction is not.
  /// This bounded registry bridges that gap: startup discovers disk hits
  /// before publishing cached messages, then video tiles can obtain a local
  /// file path synchronously for their first paint.
  static final Map<String, String> _readyPosterPaths = {};
  static const int _readyPathLimit = 512;

  static String? readyPosterPathFor(String? key) {
    if (key == null) return null;
    final path = _readyPosterPaths[key];
    if (path == null) return null;
    if (io.File(path).existsSync()) return path;
    _readyPosterPaths.remove(key);
    return null;
  }

  static void _rememberReadyPath(String key, String path) {
    if (_readyPosterPaths.length >= _readyPathLimit &&
        !_readyPosterPaths.containsKey(key)) {
      _readyPosterPaths.remove(_readyPosterPaths.keys.first);
    }
    _readyPosterPaths[key] = path;
  }

  @visibleForTesting
  static void debugClearReadyPosterPaths() => _readyPosterPaths.clear();

  @visibleForTesting
  static void debugRememberReadyPosterPath(String key, String path) =>
      _rememberReadyPath(key, path);

  /// Built on first use rather than in the constructor: DefaultCacheManager
  /// reaches for a platform channel, which throws in pure-Dart tests where
  /// no binding exists. The provider constructs this eagerly at app scope,
  /// so an eager cache manager broke every ChatController test that merely
  /// read the provider — without any of them prewarming anything.
  BaseCacheManager get _cacheManager =>
      _injectedCacheManager ??
      (_resolvedCacheManager ??= DefaultCacheManager());

  /// Storage keys already attempted this session, so repeated loads of the
  /// same conversation don't re-sign and re-check keys already handled.
  final Set<String> _attempted = {};

  /// How many posters to fetch at once. Enough to cover a screenful without
  /// putting a burst of signing requests on the wire during chat open, which
  /// competes with the message fetch the user is actually waiting on.
  static const int _concurrency = 4;

  /// Only the newest posters are worth prewarming — those are the ones on
  /// screen when the chat opens. Older ones prewarm naturally if the user
  /// scrolls to them.
  static const int _maxPerPass = 24;

  /// Discovers posters already present on disk without signing or downloading
  /// anything. Await this before publishing warm-cache messages so those
  /// tiles can paint a FileImage on their first frame.
  Future<void> discoverCached(List<Message> messages) async {
    final keys = _posterKeys(messages);
    for (var i = 0; i < keys.length; i += _concurrency) {
      final batch = keys.skip(i).take(_concurrency);
      await Future.wait(batch.map(_discoverOne));
    }
  }

  Future<void> _discoverOne(String key) async {
    try {
      final info = await _cacheManager.getFileFromCache(key);
      if (info != null) _rememberReadyPath(key, info.file.path);
    } catch (error) {
      ChatLog.e('poster cache discovery failed (non-fatal)', error);
    }
  }

  /// Copies a freshly-generated local poster into the stable cache entry used
  /// by every later signed URL. Returns the durable cache path; callers keep
  /// the staging file when this fails so the current tile never loses its
  /// only paintable frame.
  Future<String?> cacheLocalPoster({
    required String key,
    required String localPath,
  }) async {
    try {
      final source = io.File(localPath);
      if (!source.existsSync()) return null;
      final extension = p.extension(localPath).replaceFirst('.', '');
      final cached = await _cacheManager.putFileStream(
        key,
        source.openRead(),
        key: key,
        fileExtension: extension.isEmpty ? 'jpg' : extension,
      );
      _rememberReadyPath(key, cached.path);
      return cached.path;
    } catch (error) {
      ChatLog.e('local poster cache seed failed (non-fatal)', error);
      return null;
    }
  }

  /// Fetches posters for any video messages in [messages] not already
  /// cached. Safe to call repeatedly; returns once the pass is done.
  Future<void> prewarm(List<Message> messages) async {
    final keys =
        _posterKeys(messages).where((key) => _attempted.add(key)).toList();
    if (keys.isEmpty) return;

    for (var i = 0; i < keys.length; i += _concurrency) {
      final batch = keys.skip(i).take(_concurrency);
      await Future.wait(batch.map(_prewarmOne));
    }
  }

  Future<void> _prewarmOne(String key) async {
    try {
      final cache = _cacheManager;
      // Already on disk from a previous session — the common case after the
      // first run, and the whole reason this is cheap to call on every open.
      final existing = await cache.getFileFromCache(key);
      if (existing != null) {
        _rememberReadyPath(key, existing.file.path);
        return;
      }

      final url = await _repository.createSignedMediaUrl(key);
      if (url == null) return;
      // Stored under the STABLE storage key, not the signed URL, so the
      // tile's own by-key lookup finds it and a later re-sign still hits
      // the same entry.
      final downloaded = await cache.downloadFile(url, key: key);
      _rememberReadyPath(key, downloaded.file.path);
    } catch (error) {
      // Non-fatal by design: the tile's normal path still applies. The bare
      // catch is deliberate — it takes Error as well as Exception, because a
      // host with no platform binding throws the former out of the cache
      // manager. Prewarming is an optimisation and must never take a caller
      // down with it.
      ChatLog.e('poster prewarm failed (non-fatal)', error);
    }
  }

  List<String> _posterKeys(List<Message> messages) {
    final keys = <String>[];
    // ChatState and the repository both expose newest-first lists. Preserve
    // that order so the capped pass always prepares the videos visible when
    // a conversation opens, rather than spending its budget on old history.
    for (final message in messages) {
      if (keys.length >= _maxPerPass) break;
      final key = message.mediaThumbnailKey;
      if (key == null || message.isViewOnce || keys.contains(key)) continue;
      keys.add(key);
    }
    return keys;
  }

  @visibleForTesting
  void debugReset() => _attempted.clear();
}
