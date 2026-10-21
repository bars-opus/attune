import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/domain/services/chat_media_file_service.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'chat_media_file_service.dart'
    show ChatMediaFileService, ChatMediaRejected;

/// Where [ChatMediaCache] keeps everything.
typedef ChatMediaCacheLocations =
    ({
      /// The bytes (flutter_cache_manager's IOFileSystem folder for the key).
      String files,

      /// The cache's own database (which key is which file).
      String database,

      /// Which message and relationship each key belongs to.
      String index,
    });

/// Disk cache for voice and video bytes, keyed by the STABLE storage key
/// (never the signed URL, whose token changes every 10 minutes).
///
/// Chat review #28: every replay re-downloaded the note and nothing played
/// offline. Download once here, play from the returned local path forever
/// after. Separate from DefaultCacheManager (images/posters) so its bounds
/// suit large objects: [maxObjects] entries, [stalePeriod] old, and
/// [maxTotalBytes] in all (oldest-used out first).
///
/// Privacy:
/// - Everything (bytes, database, index) lives under the OS cache directory
///   (iOS Library/Caches, Android cacheDir), which no device, iCloud or
///   Auto Backup / device transfer carries ([storageLocations]).
/// - Every key is recorded with the relationship and message ids it belongs
///   to BEFORE its bytes land, so a deleted message ([removeForMessages]) or
///   a purged relationship ([removeForRelationship]) can always find them.
/// - Sign-out empties it ([clear]).
class ChatMediaCache {
  ChatMediaCache({
    BaseCacheManager? manager,
    String? indexPath,
    @visibleForTesting Future<String?> Function()? indexLocation,
    @visibleForTesting int byteBudget = maxTotalBytes,
    Duration? networkTimeout,
    @visibleForTesting CacheInfoRepository? cacheRepository,
    @visibleForTesting String? filesDirectory,
    @visibleForTesting Duration clearBound = defaultClearBound,
  }) : _injected = manager,
       _clearBound = clearBound,
       _repo = cacheRepository,
       _injectedFilesDirectory = filesDirectory,
       _injectedIndexPath = indexPath,
       _indexLocation = indexLocation,
       _byteBudget = byteBudget,
       _networkTimeout = networkTimeout;

  static const String cacheKey = 'attune_chat_media';

  /// How long [clear] may hold a sign-out (like ChatCacheService.clearAll).
  static const Duration defaultClearBound = Duration(seconds: 3);
  static const int maxObjects = 400;
  static const Duration stalePeriod = Duration(days: 180);

  /// All cached bytes together. Past this the least recently played go.
  static const int maxTotalBytes = 1024 * 1024 * 1024;

  /// Ownership records kept. Past this the oldest record goes, and its
  /// bytes with it, so no cached file is ever left without an owner.
  static const int maxIndexEntries = maxObjects * 2;

  final BaseCacheManager? _injected;
  final String? _injectedIndexPath;
  final Future<String?> Function()? _indexLocation;
  final int _byteBudget;
  final Duration? _networkTimeout;
  final String? _injectedFilesDirectory;
  final Duration _clearBound;
  Future<BaseCacheManager>? _built;

  /// The cache manager's database, for the orphan sweep (production: the
  /// one [_build] creates).
  CacheInfoRepository? _repo;
  Future<void>? _sweeping;

  /// Bumped by [clear]: a download that started before it is not kept.
  int _epoch = 0;

  Future<Map<String, _Owner>>? _index;

  /// The index file this session read (or found absent). Only that file is
  /// ever written: an index never read is never overwritten.
  String? _readFrom;

  /// The write chain, started lazily: a completed future made at
  /// construction would run every later write in the constructing zone.
  Future<void>? _writing;

  /// The OS cache directory, never Application Support or Documents (both
  /// backed up). flutter_cache_manager's IOFileSystem stores the files in
  /// `<temporary>/<cacheKey>`; the database and index sit beside it.
  static Future<ChatMediaCacheLocations> storageLocations() async {
    final temp = (await getTemporaryDirectory()).path;
    return (
      files: p.join(temp, cacheKey),
      database: p.join(temp, '$cacheKey.db'),
      index: p.join(temp, '$cacheKey.index.json'),
    );
  }

  /// Built lazily: CacheManager reaches for a platform channel, which
  /// throws on a pure-Dart test host that merely reads the provider.
  Future<BaseCacheManager> _manager() {
    final injected = _injected;
    if (injected != null) return Future.value(injected);
    return _built ??= _build();
  }

  Future<BaseCacheManager> _build() async {
    try {
      final at = await storageLocations();
      // Default would be Application Support (backed up).
      final repo =
          _repo = CacheObjectProvider(
            path: at.database,
            databaseName: cacheKey,
          );
      return CacheManager(
        Config(
          cacheKey,
          stalePeriod: stalePeriod,
          maxNrOfCacheObjects: maxObjects,
          repo: repo,
          fileService: ChatMediaFileService(timeout: _networkTimeout),
        ),
      );
    } catch (_) {
      _built = null; // try again next time
      rethrow;
    }
  }

  /// Local path when the bytes are already on disk; no network.
  Future<String?> cachedPath(String mediaKey) async {
    try {
      // First use this launch: an unreadable index empties the cache before
      // anything is served from it (see _readIndex).
      await _loadIndex();
      final manager = await _manager();
      final info = await manager.getFileFromCache(mediaKey);
      if (info == null) return null;
      final file = File(info.file.path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        // A kill mid-write leaves a zero-byte entry; it is a miss.
        await manager.removeFile(mediaKey);
        return null;
      }
      return file.path;
    } catch (error) {
      ChatLog.diagnostic('media cache lookup failed (non-fatal)', error);
      return null;
    }
  }

  /// Returns a local path for [mediaKey], downloading [url] on a miss. An
  /// expired token (400/401/403) is refreshed through [refreshUrl] once.
  /// Other failures — including a link that stalls (see
  /// [ChatMediaFileService.timeout]) — rethrow so the caller can fall back
  /// to streaming.
  ///
  /// [relationshipId] and [messageIds] (client and server id) say whose
  /// bytes these are, so deleting that message or purging that
  /// relationship removes them.
  Future<String> fetch({
    required String mediaKey,
    required String url,
    required Future<String?> Function() refreshUrl,
    void Function(double fraction)? onProgress,
    String? relationshipId,
    Set<String> messageIds = const {},
  }) async {
    final hit = await cachedPath(mediaKey);
    if (hit != null) {
      try {
        // Played again: last in line for the byte budget.
        await _remember(mediaKey, relationshipId, messageIds, touch: true);
      } catch (error) {
        ChatLog.diagnostic('media cache owner update failed', error);
      }
      return hit;
    }
    final epoch = _epoch;
    // Before the download, not after: bytes that land are always findable
    // by their message. If the owner cannot be recorded, nothing is cached
    // (this throws and the caller streams).
    await _remember(mediaKey, relationshipId, messageIds);
    final String path;
    try {
      path = await _downloadRefreshingOnce(
        mediaKey,
        url,
        refreshUrl,
        onProgress,
      );
    } catch (_) {
      // A download cut short leaves its partial file behind.
      await _sweepOrphans();
      rethrow;
    }
    final index = await _loadIndex();
    final owner = index[mediaKey];
    if (epoch != _epoch || owner == null) {
      // Signed out, or the message went away, while this downloaded.
      await _evict(mediaKey);
      throw const ChatMediaRejected('removed while downloading');
    }
    index[mediaKey] = owner.withBytes(_sizeOf(path));
    await _enforceByteBudget(keep: mediaKey);
    await _persist();
    return path;
  }

  Future<String> _downloadRefreshingOnce(
    String mediaKey,
    String url,
    Future<String?> Function() refreshUrl,
    void Function(double)? onProgress,
  ) async {
    try {
      return await _download(mediaKey, url, onProgress);
    } on HttpExceptionWithStatus catch (error) {
      if (error.statusCode != 400 &&
          error.statusCode != 401 &&
          error.statusCode != 403) {
        rethrow;
      }
      final fresh = await refreshUrl();
      if (fresh == null || fresh == url) rethrow;
      return _download(mediaKey, fresh, onProgress);
    }
  }

  Future<String> _download(
    String mediaKey,
    String url,
    void Function(double)? onProgress,
  ) async {
    String? path;
    final manager = await _manager();
    await for (final event in manager.getFileStream(
      url,
      key: mediaKey,
      withProgress: true,
    )) {
      if (event is DownloadProgress) {
        final total = event.totalSize;
        if (total != null && total > 0) {
          onProgress?.call((event.downloaded / total).clamp(0.0, 1.0));
        }
      } else if (event is FileInfo) {
        path = event.file.path;
      }
    }
    if (path == null) {
      throw const FileSystemException('download produced no file');
    }
    onProgress?.call(1.0);
    return path;
  }

  static int _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// Least recently played first, until the total fits [maxTotalBytes]. The
  /// object just committed ([keep]) is never the one to go.
  Future<void> _enforceByteBudget({required String keep}) async {
    final index = await _loadIndex();
    var total = index.values.fold<int>(0, (sum, o) => sum + (o.bytes ?? 0));
    for (final key in index.keys.toList()) {
      if (total <= _byteBudget) break;
      final bytes = index[key]?.bytes ?? 0;
      if (key == keep || bytes == 0) continue;
      index.remove(key);
      await _evictOrDrop(key);
      total -= bytes;
    }
  }

  /// [mediaKey] was played again from the cache: last in line for the byte
  /// budget. Only an existing record moves; never throws.
  Future<void> touch(String mediaKey) async {
    try {
      final index = await _loadIndex();
      if (!index.containsKey(mediaKey)) return;
      await _remember(mediaKey, null, const {}, touch: true);
    } catch (error) {
      ChatLog.diagnostic('media cache touch failed (non-fatal)', error);
    }
  }

  /// How old a file with no database row must be before it counts as an
  /// orphan. A download in flight writes its file continually, and one that
  /// goes quiet longer than the network timeout is failed by
  /// ChatMediaFileService — so nothing in flight is ever this stale. The
  /// margin covers a commit's database write, which lands just after the
  /// file is complete.
  Duration get _orphanAge =>
      (_networkTimeout ?? const ChatConfig().networkTimeout) +
      const Duration(minutes: 1);

  /// Deletes files in the cache folder that the cache manager's database
  /// does not know (partial files of downloads that failed or timed out:
  /// never served, not counted in the byte budget, and possibly a deleted
  /// message's bytes) once they are older than [_orphanAge]. Run on first
  /// use and after a failed download. Never throws.
  Future<void> _sweepOrphans() =>
      _sweeping ??= _sweep().whenComplete(() => _sweeping = null);

  Future<void> _sweep() async {
    try {
      await _manager(); // builds the production database
      final repo = _repo;
      final folder =
          _injectedFilesDirectory ??
          (_injected == null ? (await storageLocations()).files : null);
      if (repo == null || folder == null) return;
      final directory = Directory(folder);
      if (!directory.existsSync()) return;
      await repo.open();
      // By file name: relativePath is the bare '<uuid>.<ext>' the cache
      // manager writes, so no path spelling (symlinked temp dirs) can make
      // a committed file look unknown.
      final known = {
        for (final object in await repo.getAllObjects())
          p.basename(object.relativePath),
      };
      final staleBefore = DateTime.now().subtract(_orphanAge);
      for (final entity in directory.listSync()) {
        if (entity is! File || known.contains(p.basename(entity.path))) {
          continue;
        }
        try {
          if (entity.lastModifiedSync().isBefore(staleBefore)) {
            entity.deleteSync();
          }
        } catch (error) {
          ChatLog.diagnostic('media cache orphan delete failed', error);
        }
      }
    } catch (error) {
      ChatLog.diagnostic('media cache orphan sweep failed (non-fatal)', error);
    }
  }

  /// [mediaKey]'s bytes and record, e.g. a cached file that will not play
  /// (so the next play downloads a good copy).
  Future<void> remove(String mediaKey) async {
    try {
      final index = await _loadIndex();
      await _evict(mediaKey);
      index.remove(mediaKey);
      await _persist();
    } catch (error) {
      ChatLog.diagnostic('media cache remove failed (non-fatal)', error);
    }
  }

  /// Messages that went away (deleted, hidden, purged), by client or server
  /// id: their cached bytes are deleted.
  Future<void> removeForMessages(Set<String> ids) async {
    if (ids.isEmpty) return;
    await _removeWhere((owner) => owner.messageIds.any(ids.contains));
  }

  /// A relationship's local state was purged (archive, account change, the
  /// conversation gone): its cached bytes go too.
  Future<void> removeForRelationship(String relationshipId) =>
      _removeWhere((owner) => owner.relationshipId == relationshipId);

  Future<void> _removeWhere(bool Function(_Owner owner) matches) async {
    try {
      final index = await _loadIndex();
      final keys = [
        for (final entry in index.entries)
          if (matches(entry.value)) entry.key,
      ];
      if (keys.isEmpty) return;
      // Bytes first, record second: a crash in between leaves a record of
      // bytes already gone, never bytes nobody can name. A key whose bytes
      // could not be deleted keeps its record for the next removal.
      for (final key in keys) {
        try {
          await _evict(key);
          index.remove(key);
        } catch (error) {
          ChatLog.diagnostic('media cache evict failed; kept', error);
        }
      }
      await _persist();
    } catch (error) {
      ChatLog.diagnostic('media cache removal failed (non-fatal)', error);
    }
  }

  /// Sign-out: nothing of the previous person's media stays on disk. Never
  /// throws, and never holds the sign-out longer than about two
  /// [defaultClearBound]s (M3).
  ///
  /// The ownership index goes FIRST: with no index the next first use
  /// empties the whole cache ([_readIndex]), so a clear cut off by its bound
  /// (up to 400 files / 1 GB, a stuck database) still finishes then.
  Future<void> clear() async {
    _epoch++;
    final previous = _index;
    _index = Future.value(<String, _Owner>{});
    // A write already queued with the old map must not bring entries back.
    if (previous != null) {
      unawaited(previous.then((index) => index.clear(), onError: (_) {}));
    }
    try {
      await _deleteIndexFile().timeout(_clearBound);
    } catch (error) {
      ChatLog.diagnostic('media cache index delete failed (non-fatal)', error);
    }
    try {
      await _clearBytes().timeout(_clearBound);
    } catch (error) {
      ChatLog.diagnostic(
        'media cache clear unfinished; the next open empties it',
        error,
      );
      // Not the empty in-memory map: the next use in this run re-reads the
      // (deleted) index and empties the store, as a new launch would.
      _index = null;
    }
  }

  Future<void> _deleteIndexFile() async {
    final path = await _indexPath();
    if (path == null) return;
    _readFrom = path; // the (now empty) index this session writes from here
    for (final file in [File(path), File('$path.tmp')]) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  Future<void> _clearBytes() async {
    try {
      // After any write still queued with the old map: deletes it again.
      await _persist();
    } catch (error) {
      ChatLog.diagnostic('media cache index clear failed (non-fatal)', error);
    }
    try {
      await (await _manager()).emptyCache();
    } catch (error) {
      ChatLog.e('media cache clear failed (non-fatal)', error);
    }
    if (_injected != null) return;
    // Also any file the database never recorded (a download cut short).
    try {
      final files = Directory((await storageLocations()).files);
      if (files.existsSync()) await files.delete(recursive: true);
    } catch (error) {
      ChatLog.diagnostic('media cache folder wipe failed (non-fatal)', error);
    }
  }

  /// Deletes [mediaKey]'s bytes. removeFile skips an entry whose database
  /// row is still being written (a download that just finished), so the
  /// file itself is deleted as well. Throws only when that file cannot be
  /// deleted.
  Future<void> _evict(String mediaKey) async {
    final manager = await _manager();
    String? path;
    try {
      path = (await manager.getFileFromCache(mediaKey))?.file.path;
    } catch (error) {
      ChatLog.diagnostic('media cache lookup before evict failed', error);
    }
    try {
      await manager.removeFile(mediaKey);
    } catch (error) {
      ChatLog.diagnostic('media cache evict failed', error);
    }
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// [_evict] for a record that is going regardless (a cap): a delete that
  /// fails is logged, and those bytes are left to the count/age bound —
  /// keeping the record would fail every later fetch on the same cap.
  Future<void> _evictOrDrop(String mediaKey) async {
    try {
      await _evict(mediaKey);
    } catch (error) {
      ChatLog.diagnostic('media cache evict failed; record dropped', error);
    }
  }

  Future<void> _remember(
    String mediaKey,
    String? relationshipId,
    Set<String> messageIds, {
    bool touch = false,
  }) async {
    final index = await _loadIndex();
    final known = index[mediaKey];
    final ids = {...?known?.messageIds, ...messageIds};
    final owner = relationshipId ?? known?.relationshipId;
    final unchanged =
        known != null &&
        known.relationshipId == owner &&
        known.messageIds.length == ids.length;
    if (unchanged && (!touch || index.keys.last == mediaKey)) return;
    // Re-inserted so the map's order is least recently used first.
    index.remove(mediaKey);
    index[mediaKey] = _Owner(owner, ids, known?.bytes);
    while (index.length > maxIndexEntries) {
      final oldest = index.keys.first;
      index.remove(oldest);
      await _evictOrDrop(oldest);
    }
    await _persist();
  }

  Future<String?> _indexPath() async {
    final locate = _indexLocation;
    if (locate != null) return locate();
    if (_injected != null) return _injectedIndexPath;
    return (await storageLocations()).index;
  }

  /// The index, read once per session; reading it also sweeps orphans
  /// (first use).
  Future<Map<String, _Owner>> _loadIndex() =>
      _index ??= _readIndex().then((index) async {
        await _sweepOrphans();
        return index;
      });

  Future<Map<String, _Owner>> _readIndex() async {
    final index = <String, _Owner>{};
    final String? path;
    try {
      path = await _indexPath();
    } catch (error) {
      // No location this time: memory only, and NOT remembered — the next
      // use reads the real index instead of overwriting it with this one.
      ChatLog.diagnostic('media cache index has no location', error);
      _index = null;
      return index;
    }
    if (path == null) return index;
    final file = File(path);
    if (!file.existsSync()) {
      _readFrom = path;
      // No index means nothing is attributable — normally because nothing
      // is cached (first run, or emptied), when this costs nothing. If the
      // OS purged the index alone, the bytes it described go too.
      await _emptyQuietly();
      return index;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      for (final entry in (decoded as Map<String, dynamic>).entries) {
        final value = entry.value as Map<String, dynamic>;
        index[entry.key] = _Owner(value['r'] as String?, {
          for (final id in value['m'] as List<dynamic>) id as String,
        }, value['b'] as int?);
      }
    } catch (error) {
      // Bytes whose message cannot be named could never be removed when
      // that message is deleted: start over rather than keep them.
      ChatLog.diagnostic('media cache index unreadable; emptying', error);
      index.clear();
      await _emptyQuietly();
      try {
        await file.delete();
      } catch (deleteError) {
        ChatLog.diagnostic('media cache index delete failed', deleteError);
      }
    }
    _readFrom = path;
    return index;
  }

  Future<void> _emptyQuietly() async {
    try {
      await (await _manager()).emptyCache();
    } catch (error) {
      ChatLog.diagnostic('media cache reset failed', error);
    }
  }

  /// Writes the index as it is now: to a temporary name, then renamed over
  /// the old one, so a kill mid-write never leaves half a file. Serialised.
  Future<void> _persist() {
    final next = (_writing ?? Future<void>.value()).then((_) => _writeIndex());
    _writing = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeIndex() async {
    final index = await _loadIndex();
    final path = _readFrom;
    if (path == null) return; // never read: never overwritten
    final file = File(path);
    if (index.isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final json = jsonEncode({
      for (final entry in index.entries)
        entry.key: {
          'r': entry.value.relationshipId,
          'm': entry.value.messageIds.toList(),
          if (entry.value.bytes != null) 'b': entry.value.bytes,
        },
    });
    final temp = File('$path.tmp');
    await temp.parent.create(recursive: true);
    await temp.writeAsString(json, flush: true);
    await temp.rename(path);
  }
}

@immutable
class _Owner {
  const _Owner(this.relationshipId, this.messageIds, [this.bytes]);
  final String? relationshipId;
  final Set<String> messageIds;

  /// Size on disk once committed; null while the download is in flight.
  final int? bytes;

  _Owner withBytes(int size) => _Owner(relationshipId, messageIds, size);
}

final chatMediaCacheProvider = Provider<ChatMediaCache>(
  (ref) => ChatMediaCache(
    networkTimeout: ref.watch(chatConfigProvider).networkTimeout,
  ),
);
