import 'dart:async';

import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The disk cache chat photos and video posters are drawn from (I3).
///
/// Every chat image surface (bubble, media group, video poster, viewer,
/// Media screen) draws through CachedNetworkImage with no cacheManager of
/// its own — i.e. DefaultCacheManager — under the STABLE storage key, and
/// ChatPosterPrewarmer seeds just-sent photos and posters into the same
/// store. Voice and video bytes are ChatMediaCache's, not this.
///
/// That store used to outlive both a delete-for-everyone and a sign-out:
/// the 1600 px JPEG stayed in the cache dir for the next person on a
/// shared phone. Sign-out now empties it ([clear]); a removed message's
/// photo and poster entries go with it ([removeKeys]); a relationship purge
/// removes every key it knows. Both are bounded and never throw.
class ChatImageCache {
  ChatImageCache({BaseCacheManager? manager, Duration? bound})
    : _injected = manager,
      _bound = bound ?? defaultBound;

  /// How long one step may hold the caller (sign-out runs in the auth lock).
  static const Duration defaultBound = Duration(seconds: 3);

  final BaseCacheManager? _injected;
  final Duration _bound;

  /// Resolved on use: DefaultCacheManager reaches for a platform channel,
  /// which a pure-Dart test host does not have.
  BaseCacheManager get _manager => _injected ?? _defaultManager();

  /// DefaultCacheManager's constructor starts its directory and database
  /// opens without awaiting them, so where those fail (a host with no
  /// path_provider) the errors would surface as uncaught — and the store's
  /// calls then never answer. Built in a guarded zone, the failure is
  /// logged and ends every call on it at once ([_storeFailed]) instead of
  /// at the bound. On a device the image widgets have usually built the
  /// singleton already; this is then just a lookup.
  static BaseCacheManager _defaultManager() {
    final existing = _default;
    if (existing != null) return existing;
    BaseCacheManager? built;
    runZonedGuarded(() => built = DefaultCacheManager(), (error, _) {
      ChatLog.diagnostic('image cache store unavailable (non-fatal)', error);
      _failStore(error);
    });
    final manager = built;
    if (manager == null) throw StateError('image cache store unavailable');
    return _default = manager;
  }

  static BaseCacheManager? _default;
  static final Completer<Object> _storeFailed = Completer<Object>();

  /// Calls waiting on a store that may turn out to be unusable. One
  /// listener on [_storeFailed] serves them all, so a long session of
  /// removals never piles closures onto a future that never completes.
  static final Set<Completer<void>> _failureWaiters = {};
  static Object? _storeFailure;

  static void _failStore(Object error) {
    if (_storeFailed.isCompleted) return;
    _storeFailure = error;
    _storeFailed.complete(error);
    final waiting = _failureWaiters.toList();
    _failureWaiters.clear();
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  /// [run], or the store's failure the moment it is known.
  static Future<void> _raceStoreFailure(Future<void> run, Duration bound) {
    final failure = _storeFailure;
    if (failure != null) return Future<void>.error(failure);
    final failed = Completer<void>();
    _failureWaiters.add(failed);
    return Future.any<void>([
      run,
      failed.future,
    ]).timeout(bound).whenComplete(() => _failureWaiters.remove(failed));
  }

  @visibleForTesting
  static Future<void> debugRaceStoreFailure(Future<void> run, Duration bound) =>
      _raceStoreFailure(run, bound);

  @visibleForTesting
  static void debugFailStore(Object error) => _failStore(error);

  @visibleForTesting
  static int get debugFailureWaiters => _failureWaiters.length;

  /// [step] on the store, bounded, and over as soon as the default store
  /// is known to be unusable.
  Future<void> _onStore(Future<void> Function(BaseCacheManager) step) {
    final manager = _manager;
    final run = Future.sync(() => step(manager));
    if (_injected != null) return run.timeout(_bound);
    return _raceStoreFailure(run, _bound);
  }

  /// Sign-out: every photo and poster in the store goes. DefaultCacheManager
  /// also holds avatars and other remote images; those are the previous
  /// person's too, and simply re-download.
  Future<void> clear() async {
    ChatPosterPrewarmer.forgetAllReadyPosterPaths();
    try {
      await _onStore((manager) => manager.emptyCache());
    } catch (error) {
      ChatLog.diagnostic('image cache clear unfinished (non-fatal)', error);
    }
  }

  /// Removed messages' photos and posters, by storage key. One key that
  /// cannot be removed never stops the rest.
  Future<void> removeKeys(Iterable<String> keys) async {
    final wanted = {
      for (final key in keys)
        if (key.isNotEmpty) key,
    };
    if (wanted.isEmpty) return;
    for (final key in wanted) {
      ChatPosterPrewarmer.forgetReadyPosterPath(key);
    }
    try {
      await _onStore((manager) => _removeAll(manager, wanted));
    } catch (error) {
      ChatLog.diagnostic('image cache removal unfinished (non-fatal)', error);
    }
  }

  static Future<void> _removeAll(
    BaseCacheManager manager,
    Set<String> keys,
  ) async {
    for (final key in keys) {
      try {
        await manager.removeFile(key);
      } catch (error) {
        ChatLog.diagnostic('image cache remove failed (non-fatal)', error);
      }
    }
  }
}

final chatImageCacheProvider = Provider<ChatImageCache>(
  (ref) => ChatImageCache(),
);
