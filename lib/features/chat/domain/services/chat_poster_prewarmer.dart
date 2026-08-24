import 'dart:async';

import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

  /// Fetches posters for any video messages in [messages] not already
  /// cached. Safe to call repeatedly; returns once the pass is done.
  Future<void> prewarm(List<Message> messages) async {
    final keys = <String>[];
    // Newest first: the bottom of the list is what the user sees on open.
    for (final message in messages.reversed) {
      if (keys.length >= _maxPerPass) break;
      final key = message.mediaThumbnailKey;
      if (key == null) continue;
      // A view-once video's poster is deliberately not persisted; fetching
      // it here would both fail and defeat the point.
      if (message.isViewOnce) continue;
      if (!_attempted.add(key)) continue;
      keys.add(key);
    }
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
      if (await cache.getFileFromCache(key) != null) return;

      final url = await _repository.createSignedMediaUrl(key);
      if (url == null) return;
      // Stored under the STABLE storage key, not the signed URL, so the
      // tile's own by-key lookup finds it and a later re-sign still hits
      // the same entry.
      await cache.downloadFile(url, key: key);
    } catch (error) {
      // Non-fatal by design: the tile's normal path still applies. The bare
      // catch is deliberate — it takes Error as well as Exception, because a
      // host with no platform binding throws the former out of the cache
      // manager. Prewarming is an optimisation and must never take a caller
      // down with it.
      ChatLog.e('poster prewarm failed (non-fatal)', error);
    }
  }

  @visibleForTesting
  void debugReset() => _attempted.clear();
}
