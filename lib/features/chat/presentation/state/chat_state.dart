import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ref.watch(supabaseChatRepositoryProvider);
});

/// Thrown by [signedMediaUrlProvider] when a storage key could not be
/// signed (offline, policy, missing object). Content-free.
class SignedMediaUrlUnavailable implements Exception {
  const SignedMediaUrlUnavailable(this.mediaKey, {this.lastGoodExpired = false});
  final String mediaKey;

  /// True once the URL this member last resolved is past its grant too, so
  /// a tile must stop showing it (Riverpod carries a previous value through
  /// every later error; this says it is no longer usable).
  final bool lastGoodExpired;
  @override
  String toString() => 'SignedMediaUrlUnavailable';
}

/// The longest a resolved signed URL is trusted before the provider re-signs
/// it, whatever its grant says. The usual trigger is the grant itself — its
/// expiry less [signedMediaUrlRefreshMargin]; for a fresh sign (10-minute
/// token, trusted 9 by SupabaseChatRepository) both land at 8 minutes. The
/// cap keeps an unexpectedly long grant, or a test, bounded.
final signedMediaUrlRefreshAfterProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 8),
);

/// How long before a grant stops being trusted the provider re-signs it —
/// room for a slow download that started late.
const signedMediaUrlRefreshMargin = Duration(seconds: 60);

/// Floor on the scheduled refresh, so a grant that comes back already near
/// its end cannot spin the provider into back-to-back re-signs.
const _signedMediaUrlMinimumRefresh = Duration(seconds: 5);

/// Resolves a signed URL for a chat media storage key on demand — used by
/// MessageBubble's media slots (via ResolvedMediaUrl) and the voice
/// resolver. Keyed on mediaKey (not the message id), so messages with the
/// same key share one resolution, and SupabaseChatRepository's own
/// signed-URL cache makes a re-sign a memory hit in the common case.
///
/// autoDispose + keepAlive-on-success (chat review #22): a resolution that
/// FAILED used to sit in a non-autoDispose family as `data(null)` for the
/// rest of the app session, so one photo opened in a tunnel stayed broken
/// until restart. Now a failure is an error state that lives only while a
/// tile listens, retries briefly in place, re-resolves when connectivity
/// changes or on tap (ResolvedMediaUrl), and a success is kept and
/// re-signed before its grant expires.
/// Messages this device learned went away on the server — soft-deleted, or
/// gone outright (hard delete, purge) — named by server id and, when known,
/// client id. Announced by [ChatController.refreshMessagesByIds] (realtime),
/// [ChatController.syncChangesSinceCursor] (deleted while away) and
/// [ChatController.deleteMessage] whether or not the row was in the loaded
/// list, for consumers that hold a message the list never had (voice
/// playback started from the Media screen; ChatMediaCache's bytes). A
/// plain event stream: the chat controller does not know who listens.
class ChatMessageRemovals {
  final _removed = StreamController<Set<String>>.broadcast();
  final _removedMedia = StreamController<Set<String>>.broadcast();

  Stream<Set<String>> get stream => _removed.stream;

  /// The storage keys (media and poster) of removed messages, where the
  /// announcer knew them — a row it had loaded (I3). The server's tombstone
  /// carries none, so an unloaded row's photo is left to the sign-out wipe.
  Stream<Set<String>> get mediaKeys => _removedMedia.stream;

  void announce(Set<String> ids, {Set<String> mediaKeys = const {}}) {
    if (ids.isNotEmpty && !_removed.isClosed) _removed.add(ids);
    if (mediaKeys.isNotEmpty && !_removedMedia.isClosed) {
      _removedMedia.add(mediaKeys);
    }
  }

  void close() {
    _removed.close();
    _removedMedia.close();
  }
}

final chatMessageRemovalsProvider = Provider<ChatMessageRemovals>((ref) {
  final removals = ChatMessageRemovals();
  // A removed message's voice/video bytes leave the disk cache (#28).
  // Subscribed here, where the bus is born, so no announcement can go out
  // before the cache listens — whoever happens to read the cache first.
  final cached = removals.stream.listen((ids) {
    unawaited(ref.read(chatMediaCacheProvider).removeForMessages(ids));
  });
  // ...and its photo and poster leave the image cache (I3).
  final images = removals.mediaKeys.listen((keys) {
    unawaited(ref.read(chatImageCacheProvider).removeKeys(keys));
  });
  ref.onDispose(() {
    unawaited(cached.cancel());
    unawaited(images.cancel());
    removals.close();
  });
  return removals;
});

final signedMediaUrlProvider = AsyncNotifierProvider.autoDispose
    .family<SignedMediaUrlNotifier, String, String>(SignedMediaUrlNotifier.new);

/// A FORCED re-sign of a storage key, bypassing the repository's URL cache:
/// for a consumer that has proven its URL dead (an expired token on a media
/// download, a player that would not open it). Null when it cannot sign.
/// One definition for the voice controller, the video viewer and
/// ChatMediaCache's refresh.
final resignMediaUrlProvider = Provider<Future<String?> Function(String)>(
  (ref) =>
      (mediaKey) => ref
          .read(chatRepositoryProvider)
          .createSignedMediaUrl(mediaKey, forceRefresh: true),
);

/// See [signedMediaUrlProvider]. A notifier rather than a plain
/// FutureProvider because it carries one fact across rebuilds (the notifier
/// outlives them): how long the last good URL may still be shown.
class SignedMediaUrlNotifier
    extends AutoDisposeFamilyAsyncNotifier<String, String> {
  /// When the URL this member last resolved stops being trusted; null once
  /// it has been dropped (or before the first success).
  DateTime? _lastGoodUntil;

  /// Whether a tile (or the voice resolver) listens now. Kept on the
  /// notifier, which outlives rebuilds; a member is built for a reader.
  bool _listened = true;

  @override
  Future<String> build(String mediaKey) async {
    var resolved = false;
    var disposed = false;
    ref.onDispose(() => disposed = true);
    ref.onCancel(() => _listened = false);
    ref.onResume(() => _listened = true);

    // Connectivity is LISTENED, not watched: only a member that has not
    // resolved (failed, or still trying) re-runs on a flip. A watch would
    // rebuild — and re-sign — every listened tile in the list on each flip,
    // including the ones already showing their image.
    ref.listen<bool>(
      chatConnectivityProvider.select((state) => state.valueOrNull ?? true),
      (previous, next) {
        if (!resolved) ref.invalidateSelf();
      },
    );
    final online = ref.read(chatConnectivityProvider).valueOrNull ?? true;
    final repository = ref.watch(chatRepositoryProvider);

    // A member that already holds a URL is rebuilt to REPLACE it (the timed
    // refresh, or a reconnect after that refresh failed): the repository's
    // cache entry is the one about to expire, so sign past the cache.
    var forceRefresh = _lastGoodUntil != null;

    // Brief in-place retry while online; offline, one try is enough (the
    // connectivity flip above is the retry). A disposed or rebuilt member
    // stops retrying: dispose ENDS the wait (it does not just cancel the
    // timer) so the build still settles — a caller awaiting `.future`
    // without listening (the voice resolver) gets an answer, not a future
    // that never completes.
    final backoff =
        online
            ? const [Duration(milliseconds: 400), Duration(milliseconds: 1200)]
            : const <Duration>[];
    SignedMediaGrant? grant;
    for (var attempt = 0; ; attempt++) {
      grant = await repository.createSignedMediaGrant(
        mediaKey,
        forceRefresh: forceRefresh,
      );
      if (grant != null || disposed || attempt == backoff.length) break;
      final waited = Completer<void>();
      void endWait() {
        if (!waited.isCompleted) waited.complete();
      }

      final timer = Timer(backoff[attempt], endWait);
      ref.onDispose(() {
        timer.cancel();
        endWait();
      });
      await waited.future;
      if (disposed) break;
    }

    // A cache hit already inside the refresh margin: re-sign now rather
    // than schedule a refresh in the past. The near-dead URL stays the
    // answer if that fails — it is still valid for a few seconds.
    if (grant != null &&
        !forceRefresh &&
        !disposed &&
        _untilRefresh(grant) <= Duration.zero) {
      forceRefresh = true;
      grant =
          await repository.createSignedMediaGrant(
            mediaKey,
            forceRefresh: true,
          ) ??
          grant;
    }

    // Disposed while signing (an unlistened `.future` read — the voice
    // resolver): hand back what was signed, and register NOTHING on the
    // dead member — a keepAlive link or refresh timer there would outlive
    // it and later fire against a live member for the same key.
    if (disposed) {
      if (grant == null) throw SignedMediaUrlUnavailable(mediaKey);
      return grant.url;
    }

    if (grant == null) {
      _dropLastGoodUrlWhenItExpires();
      // Riverpod carries the previous value into this error, so say whether
      // it is still usable: no last good URL left (dropped, or never had
      // one — then there is no value to carry anyway) or one past its grant
      // is expired.
      final until = _lastGoodUntil;
      throw SignedMediaUrlUnavailable(
        mediaKey,
        lastGoodExpired: until == null || !until.isAfter(clock.now()),
      );
    }

    resolved = true;
    _lastGoodUntil = grant.expiresAt;
    final link = ref.keepAlive();
    final cap = ref.read(signedMediaUrlRefreshAfterProvider);
    var delay = _untilRefresh(grant);
    if (delay < _signedMediaUrlMinimumRefresh) {
      delay = _signedMediaUrlMinimumRefresh;
    }
    if (delay > cap) delay = cap;
    final refresh = Timer(delay, () {
      link.close();
      // M1: only a member someone still shows is re-signed. One nobody
      // listens to (scrolled past) just goes — closing the link disposes
      // it — and the next view resolves afresh through the repository's
      // cache, instead of a forced createSignedUrl per photo scrolled past.
      // (Riverpod 2.6's scheduler also skips flushing an unlistened
      // element; this keeps the rule explicit across framework versions.)
      if (_listened) ref.invalidateSelf();
    });
    ref.onDispose(refresh.cancel);
    return grant.url;
  }

  Duration _untilRefresh(SignedMediaGrant grant) =>
      grant.expiresAt.difference(clock.now()) - signedMediaUrlRefreshMargin;

  /// After a failed re-sign, a tile keeps showing the last good URL (its
  /// media is disk-cached under the stable key) — but only while that URL
  /// is still trusted. Past it, the error says so (lastGoodExpired) and the
  /// tile becomes the retry button instead of an expired link.
  void _dropLastGoodUrlWhenItExpires() {
    final until = _lastGoodUntil;
    if (until == null) return;
    var remaining = until.difference(clock.now());
    if (remaining.isNegative) remaining = Duration.zero;
    final timer = Timer(remaining, () {
      _lastGoodUntil = null;
      state = AsyncError(
        SignedMediaUrlUnavailable(arg, lastGoodExpired: true),
        StackTrace.current,
      );
    });
    ref.onDispose(timer.cancel);
  }
}

/// Warms video posters into the disk cache ahead of their tiles. Kept at
/// app scope (not per-conversation) so its already-attempted set survives
/// navigating between chats.
final chatPosterPrewarmerProvider = Provider<ChatPosterPrewarmer>((ref) {
  return ChatPosterPrewarmer(repository: ref.watch(chatRepositoryProvider));
});

final conversationsRefreshProvider = StateProvider<int>((ref) => 0);

/// This user's starred messages, newest-starred first. autoDispose so a
/// reopened Starred screen fetches fresh, and invalidated by
/// ChatController.starMessage/unstarMessage so a screen left open updates.
final starredMessagesProvider = FutureProvider.autoDispose<List<Message>>((
  ref,
) async {
  final repository = ref.watch(chatRepositoryProvider);
  return repository.getStarredMessages();
});

final chatImageSharingEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.imageSharing,
  );
});

final chatVoiceMessagesEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.voiceMessages,
  );
});

final chatVideoSharingEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.videoSharing,
  );
});

/// Gates offering the ephemeral (view-once) camera capture entry point.
/// This flag alone is NOT sufficient to enable capture — the RPC behind it
/// (create_chat_media_upload_intent) cannot distinguish an ephemeral video
/// intent from a gallery-pick one (both request media_type = 'video'), so
/// callers must additionally require chatVideoSharingEnabledProvider AND
/// chatImageSharingEnabledProvider, exactly like Part 1's videoAttachEnabled
/// derivation in chat_screen.dart. See the 20260816130000 migration's header
/// comment, the source of truth for this three-way requirement.
final chatEphemeralVideoEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.ephemeralVideo,
  );
});

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
      ConversationsNotifier.new,
    );

/// Cache-then-refresh: paints the last-known conversation list (including
/// each conversation's unreadCount, which arrives baked into the same rows)
/// immediately on a cold start, so ConversationsScreen isn't blank while the
/// fetch runs, then swaps in fresh data when it lands. Mirrors forums'
/// _CachedTopicsNotifier (forum_providers.dart) — reuses ChatCacheService
/// (encrypted SQLite) rather than a second, plaintext cache, since this is
/// the same conversation/message data chat's own cache already protects.
///
/// _servedCache is static so it survives this notifier being recreated by
/// invalidate/refresh — a manual pull-to-refresh (conversationsRefreshProvider)
/// or a user switch must always re-fetch live, never replay the cache.
class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  static bool _servedCache = false;

  /// Test-only: whether the one cold-start cache paint has been used, so a
  /// test can reach the network path regardless of test order.
  @visibleForTesting
  static set debugServedCache(bool value) => _servedCache = value;

  /// Realtime refreshes landing inside this window are one refetch. A
  /// message and its receipt/worker UPDATE frames arrive within tens of
  /// milliseconds of each other; each used to be a full list fetch.
  static const _refreshCoalesce = Duration(milliseconds: 300);

  /// The longest a requested refresh waits, however steadily frames keep
  /// resetting [_refreshCoalesce].
  static const _refreshMaxWait = Duration(seconds: 1);

  StreamSubscription<void>? _inboxSubscription;
  List<String>? _subscribedIds;
  String? _subscribedUserId;
  Timer? _refreshDebounce;
  Timer? _refreshMaxWaitTimer;

  /// The list fetch running now, and the one re-run queued behind it (see
  /// [refreshQuietly]).
  Future<void>? _refreshRunning;
  Future<void>? _refreshQueued;

  /// ref.onDispose fires on every rebuild AND on real disposal, and the
  /// notifier object survives rebuilds — which is why the subscription must
  /// not be torn down in onDispose. While this is false (after a dispose
  /// callback, before the rebuild — or for good) inbox frames and refreshes
  /// write nothing. A bump nobody is listening to runs onDispose at once
  /// and rebuilds only on the next read, so a frame in that gap is ignored
  /// rather than dropping the subscription: the rebuild fetches anyway, and
  /// a drop cost a channel rejoin. After a real disposal (the container is
  /// gone) the idle listener is released with the repository's stream.
  bool _isBuilt = false;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reports delivery for conversations the device now holds.
  ///
  /// The notification worker used to stamp delivered_at when it QUEUED a
  /// push, which claimed delivery for a phone that might be switched off.
  /// The honest signal is this: the recipient's own device has the rows.
  ///
  /// Driven off unreadCount because that is what the list already knows --
  /// an unread partner message the device is holding is exactly a message
  /// that has been delivered but not read.
  void _markDeliveredForFetched(
    ChatRepository repository,
    List<Conversation> conversations,
  ) {
    for (final conversation in conversations) {
      if (conversation.unreadCount > 0) {
        unawaited(
          repository.markRelationshipDelivered(conversation.relationshipId),
        );
      }
    }
  }

  @override
  Future<List<Conversation>> build() async {
    _isBuilt = true;
    ref.onDispose(() {
      _isBuilt = false;
      _cancelPendingRefresh();
    });
    ref.watch(conversationsRefreshProvider);
    final repository = ref.watch(chatRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      _dropInbox();
      return const [];
    }
    // The inbox subscription outlives rebuilds on purpose: a bump of
    // conversationsRefreshProvider (identity edit, pull-to-refresh) must not
    // tear down and rejoin the websocket channel. It is dropped only when the
    // signed-in user changes.
    if (_subscribedUserId != null && _subscribedUserId != user.id) {
      _dropInbox();
    }

    final cache = ref.read(chatCacheServiceProvider);

    if (!_servedCache) {
      _servedCache = true;
      final cached = await cache.readConversations(user.id);
      if (cached.isNotEmpty) {
        // Subscribed from the CACHED ids too: this path returns before the
        // network fetch, and without this a cold start that painted from
        // cache would leave the list unsubscribed until the next rebuild.
        _subscribeToInbox(repository, user.id, cached);
        unawaited(refreshQuietly());
        return cached;
      }
    }

    try {
      final conversations = await repository.getConversations();
      unawaited(cache.writeConversations(user.id, conversations));
      _subscribeToInbox(repository, user.id, conversations);
      _markDeliveredForFetched(repository, conversations);
      return conversations;
    } catch (_) {
      final cached = await cache.readConversations(user.id);
      // Subscribed from the cached ids: otherwise a list built while the
      // fetch failed stays deaf until something rebuilds it, and the next
      // message is exactly what should refresh it.
      _subscribeToInbox(repository, user.id, cached);
      return cached;
    }
  }

  void _dropInbox() {
    _inboxSubscription?.cancel();
    _inboxSubscription = null;
    _subscribedIds = null;
    _subscribedUserId = null;
    _cancelPendingRefresh();
  }

  /// Keeps the conversation list live.
  ///
  /// The list was fetched once at build and never again: a message
  /// arriving while the user sat on the conversations screen changed
  /// neither the preview nor the unread badge until they pulled to
  /// refresh or restarted the app. The chat screen had its own
  /// subscription; the list had none.
  ///
  /// Refreshes in place rather than invalidating: invalidate() would
  /// rebuild through AsyncLoading and flash the list away under the user
  /// for something as ordinary as a message arriving.
  void _subscribeToInbox(
    ChatRepository repository,
    String userId,
    List<Conversation> conversations,
  ) {
    final ids = conversations.map((c) => c.relationshipId).toList()..sort();
    if (ids.isEmpty) return;

    // Re-subscribed only when the SET of relationships changes. Without
    // this the subscription would tear itself down and rebuild on every
    // event it delivered -- each refresh calls back into here -- churning
    // a websocket channel for every message that arrives.
    if (_subscribedUserId == userId &&
        _subscribedIds != null &&
        _listEquals(_subscribedIds!, ids)) {
      return;
    }

    _inboxSubscription?.cancel();
    _subscribedIds = ids;
    _subscribedUserId = userId;

    _inboxSubscription = repository
        .watchInboxEvents(ids)
        .listen((_) => refreshSoon());
  }

  /// Asks for a refresh inside the coalescing window: every request and
  /// inbox frame landing within it is one fetch. A read and the receipt
  /// UPDATE frame it causes (while receipts are on) land tens of
  /// milliseconds apart, so the chat controller asks this way after a read.
  ///
  /// Trailing, with a ceiling: frames arriving steadily inside the window
  /// (a busy conversation, a burst of receipts) would otherwise postpone the
  /// refresh for as long as they kept coming, so the first pending request
  /// also arms [_refreshMaxWait].
  void refreshSoon() {
    if (!_isBuilt) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_refreshCoalesce, _runPendingRefresh);
    _refreshMaxWaitTimer ??= Timer(_refreshMaxWait, _runPendingRefresh);
  }

  void _cancelPendingRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _refreshMaxWaitTimer?.cancel();
    _refreshMaxWaitTimer = null;
  }

  void _runPendingRefresh() {
    _cancelPendingRefresh();
    unawaited(refreshQuietly());
  }

  /// Refetches the list in place: no AsyncLoading flash, no rebuild, no
  /// inbox resubscribe. Completes once data fetched AFTER the call has
  /// landed (or failed): while a fetch is running the call joins the one
  /// re-run queued behind it, which re-reads the signed-in user and
  /// repository when it starts.
  Future<void> refreshQuietly() {
    if (!_isBuilt) return Future<void>.value();
    final running = _refreshRunning;
    if (running != null) {
      return _refreshQueued ??= running.then((_) {
        _refreshQueued = null;
        return refreshQuietly();
      });
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return Future<void>.value();
    final run = _fetchInPlace(
      ref.read(chatRepositoryProvider),
      ref.read(chatCacheServiceProvider),
      user.id,
    );
    _refreshRunning = run;
    return run.whenComplete(() {
      if (identical(_refreshRunning, run)) _refreshRunning = null;
    });
  }

  /// One fetch behind an already-painted list. Never surfaces an
  /// AsyncLoading (that would flash the list away) and swallows failure —
  /// the user keeps reading what they have until a later refresh succeeds.
  Future<void> _fetchInPlace(
    ChatRepository repository,
    ChatCacheService cache,
    String userId,
  ) async {
    try {
      final conversations = await repository.getConversations();
      if (!_isBuilt) return;
      // Signed out or into another account while the fetch was in flight:
      // this list (and its inbox ids) belongs to the previous user.
      if (ref.read(currentUserProvider)?.id != userId) return;
      state = AsyncData(conversations);
      unawaited(cache.writeConversations(userId, conversations));
      _markDeliveredForFetched(repository, conversations);
      // A new relationship (or a first fetch behind the cache) means new
      // ids to filter on, and the subscription is per relationship.
      _subscribeToInbox(repository, userId, conversations);
    } catch (error) {
      ChatLog.e('conversations background refresh failed', error);
    }
  }
}

final primaryConversationProvider = FutureProvider<Conversation?>((ref) async {
  final conversations = await ref.watch(conversationsProvider.future);
  if (conversations.isEmpty) return null;
  return conversations.firstWhere(
    (conversation) => conversation.canSend,
    orElse: () => conversations.first,
  );
});

final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatState, Conversation>((ref, conversation) {
      final link = ref.keepAlive();
      final config = ref.read(chatConfigProvider);
      final keepAlive = config.controllerKeepAlive;
      final ceiling = config.controllerKeepAliveCeiling;
      Timer? evictionTimer;
      // When the last listener left (null while listened).
      DateTime? leftAt;

      // Nullable, not `late final` (M7): the timer never relies on onCancel
      // firing only after this build returned.
      ChatController? controller;
      // Evicted once idle for [keepAlive] — but not while a send is in
      // flight: a 25 MB upload outlasting the keep-alive used to be cut off
      // mid-way (its writes stop once disposed) and wait for the next open.
      // Only up to [ceiling] after the chat was left, though (M7): a request
      // the network black-holes must not pin the realtime channel, heartbeat
      // and timers for the rest of the app session. An evicted send is
      // durable in the outbox and resumes on the next open or drainer pass.
      void evictWhenIdle() {
        evictionTimer = Timer(keepAlive, () {
          final inFlight = controller?.hasSendInFlight ?? false;
          final since = leftAt;
          final pastCeiling =
              since != null && clock.now().difference(since) >= ceiling;
          if (inFlight && !pastCeiling) {
            evictWhenIdle();
            return;
          }
          if (inFlight) {
            ChatLog.d(
              '[CHAT] keep-alive ceiling reached with a send in flight; '
              'the outbox resumes it on the next open',
            );
          }
          link.close();
        });
      }

      ref.onCancel(() {
        leftAt = clock.now();
        evictWhenIdle();
      });
      ref.onResume(() {
        leftAt = null;
        evictionTimer?.cancel();
      });
      ref.onDispose(() => evictionTimer?.cancel());

      return controller = ChatController(ref, conversation);
    });

/// Whether a single message (by id) within [conversation] currently has
/// [Message.isEphemeralVideoExpired] true. Derived from
/// chatControllerProvider(conversation)'s own state.messages — the same
/// list realtime updates (Spec 6.2 catch-up, mark_video_viewed revocations
/// from another device, etc.) already flow into — rather than a new
/// standalone provider, so EphemeralVideoViewerScreen (or any other single-
/// message watcher) recomputes exactly when that message's row actually
/// changes.
final ephemeralVideoExpiredProvider = Provider.autoDispose
    .family<bool, ({Conversation conversation, String messageId})>((ref, args) {
      final messages = ref.watch(
        chatControllerProvider(args.conversation).select((s) => s.messages),
      );
      for (final message in messages) {
        if (message.id == args.messageId) {
          return message.isEphemeralVideoExpired;
        }
      }
      return false;
    });

class ChatController extends StateNotifier<ChatState> {
  static const _maxAutomaticSendAttempts = 5;

  /// Fresh uploads one send may make after the server refused its stored
  /// key at insert (expired intent / missing object).
  static const maxMediaReuploads = 3;
  static final _backoffJitter = Random();
  ChatController(this.ref, this.initialConversation)
    : super(ChatState.initial(initialConversation)) {
    // Cache the repository so dispose-time cleanup never reads a provider from
    // an already-disposed container.
    _repository = ref.read(chatRepositoryProvider);
    ref.listen(currentUserProvider, (previous, next) {
      if (previous?.id != null && previous?.id != next?.id) {
        unawaited(_handleAccountChange(previous!.id, reopen: true));
      } else if (previous == null && next != null && _awaitingSignIn) {
        // Signed out (or never signed in) while this controller lived: the
        // family is keyed by relationship, so whoever signs in now — the
        // partner on a shared phone, or the same person again — would get
        // this archived, unsubscribed controller until its keep-alive ran
        // out (M6). Rebuild it for them.
        _reopenForNewAccount();
      }
    });
    // Chat identity (name/photo) is edited elsewhere — the identity sheet
    // on PulseTab — and signals the change by bumping this counter. The
    // header reads state.conversation, which otherwise only refreshes on
    // _init or a realtime event, so an avatar/name edit didn't show here
    // until the screen was left and re-entered.
    ref.listen(conversationsRefreshProvider, (previous, next) {
      if (previous != next) unawaited(_refreshConversationSafely());
    });
    // The device saying "network is back" is seconds earlier than the socket
    // noticing (heartbeat 25 s + backoff). Treat it like a resubscribe:
    // catch up, sync changes, refresh the page, and send what waited (#1).
    ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        _onConnectivityRegained();
      }
    });
    unawaited(_init());
  }

  final Ref ref;
  final Conversation initialConversation;
  late final ChatRepository _repository;
  StreamSubscription<void>? _realtimeSubscription;
  Timer? _refreshDebounce;

  // Realtime frames are coalesced: everything inside one debounce window is
  // one batch, run new-rows-first with every metadata step guarded (#9).
  bool _pendingResync = false;

  /// The channel's first subscribe (see [ChatRealtimeEvent.resync]): a
  /// resync that skips what the open has just read (final-review M2).
  bool _pendingInitialResync = false;
  bool _pendingRelationship = false;
  bool _pendingPins = false;
  final Set<String> _touchedMessageIds = <String>{};

  /// Rows INSERT frames named. The forward catch-up usually brings them;
  /// the ones it did not are read by id (final-review C1).
  final Set<String> _insertedMessageIds = <String>{};

  /// Which of the open's reads succeeded ('first page', 'conversation',
  /// 'pins', 'delivered'), and when they finished: the channel's first
  /// subscribe skips those — if it lands within a network timeout of them.
  /// A join that took longer than that (an open offline, the socket blocked)
  /// is treated as the reconnect it effectively is.
  final Set<String> _openReadsDone = <String>{};
  DateTime? _openReadsAt;
  bool _batchInFlight = false;
  bool _batchRequested = false;

  /// Rows a by-id refresh failed to re-read go back into the next batch,
  /// on a bounded backoff (1, 2, 4, 8, 16 s). Past that the next resync's
  /// changes-since read repairs them: their updated_at moved.
  static const _touchedRetryBase = Duration(seconds: 1);
  static const _maxTouchedRetries = 5;
  int _touchedRetries = 0;
  Timer? _touchedRetryTimer;
  Timer? _readDebounce;

  /// Partner messages already reported read in this session. While the
  /// couple's seen-state is off the server never sets a receipt on them, so
  /// without this every visible sync would call mark_conversation_read again
  /// (Spec 1a). Pruned to the loaded window after each call.
  final Set<String> _markedReadIds = <String>{};
  Timer? _presenceHeartbeat;
  Timer? _retryTimer;

  /// The deadline [_retryTimer] is armed for, so a later failure never
  /// replaces an earlier deadline (that is how an item got stranded, #3).
  DateTime? _retryDeadline;
  bool _forceRequestedWhileBusy = false;

  /// Whether the conversation is currently visible on-screen, the app is
  /// foregrounded, and the message list has rendered. Read receipts are only
  /// written while this is true (Spec 6.4). Defaults to false until the screen
  /// reports it is visible so that a background push-open catch-up never marks
  /// messages read before the user actually sees them.
  bool _isViewActive = false;

  /// The id of the newest partner (non-local) message we've observed, used to
  /// detect a genuinely new arrival for the receive haptic (Task 10). Seeded
  /// once after the first [loadMessages] call in [_init] so initial history
  /// never buzzes.
  String? _lastPartnerMessageId;

  /// Whether [_lastPartnerMessageId] has been seeded from the initial load
  /// yet. Distinguishes "no partner messages in history" (baseline is
  /// genuinely null, but still seeded) from "haven't loaded yet" — a
  /// conversation's very first-ever partner message must still buzz even
  /// though the seeded baseline was null.
  bool _hasSeededPartnerBaseline = false;

  /// sortAt of every canonical game card we have seen, by message id. A
  /// partner's move keeps the card's id and advances sort_at
  /// (move_game_card), so a later sortAt on a known, now partner-owned card
  /// IS the move — the only live signal the transcript gets. Re-seeded at
  /// the baseline fold in [_init], so moves made while away never buzz.
  final Map<String, DateTime> _gameCardSortAt = {};

  /// Partner rows already considered for the receive feedback. The newest
  /// one can leave the fold (an invite becomes a known card, I take a card)
  /// and uncover an older row; that row is not a new message.
  final Set<String> _seenPartnerIds = {};

  /// Serializes outbox flushing so overlapping triggers cannot double-send the
  /// same queued item. [_inFlightClientIds] tracks items currently being sent
  /// (including single-message sends) so a concurrent flush skips them.
  bool _isFlushing = false;
  bool _flushRequestedWhileBusy = false;
  final Set<String> _inFlightClientIds = {};
  final Set<String> _preparingClientIds = {};

  /// Media items whose upload is running outside the queue (Design 3).
  final Set<String> _uploadingClientIds = {};

  /// Whether a send is still being prepared, uploaded or inserted — what
  /// keeps an idle controller from being evicted (chatControllerProvider).
  bool get hasSendInFlight =>
      _isFlushing ||
      _inFlightClientIds.isNotEmpty ||
      _preparingClientIds.isNotEmpty ||
      _uploadingClientIds.isNotEmpty;

  /// In-flight upload cancel tokens by clientMessageId (chat review #25).
  final Map<String, ChatUploadCancelToken> _uploadCancelTokens = {};
  final Map<String, double> _lastPublishedUploadProgress = {};
  final Map<String, DateTime> _lastPublishedUploadAt = {};

  /// The fastest the ring redraws: a burst on fast Wi-Fi would otherwise
  /// copy the message list and notify every listener per 2% step.
  static const _uploadProgressMinInterval = Duration(milliseconds: 100);

  /// Sends whose outbox row could not be written (a dead local cache): the
  /// one copy Retry can resend from (M1). Cleared on purge.
  final Map<String, PendingSend> _unsavedSends = {};

  /// Fixed for the controller's life (the family key), so reading it never
  /// touches `state` — which throws once disposed — from a send that is
  /// still unwinding.
  String get relationshipId => initialConversation.relationshipId;

  /// Opens the conversation, then sends what the last session left queued.
  ///
  /// Runs unawaited from the constructor, so nothing may escape it: every
  /// step is best-effort (guarded), and none of them can stop the open-time
  /// flush at the end. An offline open used to die on its header or
  /// delivered-mark read before reaching the flush, and the queue then
  /// waited for a trigger that never came (#1).
  Future<void> _init() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        _awaitingSignIn = true;
        return;
      }
      // A sign-out's staging wipe that was cut off is finished now (I1):
      // nothing of the previous person's picks outlives the next chat open.
      unawaited(ref.read(chatImagePickerProvider).finishOwedWipe());
      try {
        await _open(user.id);
      } catch (error) {
        // Backstop only: every step in _open is guarded on its own.
        ChatLog.e(
          'chat open failed rel=${ChatLog.shortId(relationshipId)}',
          error,
        );
      }
      if (!mounted) return;
      // Read is only recorded once the screen reports the conversation is
      // visible and foregrounded (Spec 6.4); do not mark read here.
      // The open-time flush: whatever the last session left queued goes
      // now (or, offline, gets its timer and waits for the next trigger).
      unawaited(flushOutbox());
    } finally {
      if (!_opened.isCompleted) _opened.complete();
    }
  }

  final Completer<void> _opened = Completer<void>();

  /// Completes once the open has run (local restore, first page, header,
  /// pins, delivered), however each step went. A caller that wakes a chat
  /// only to send (the outbox drainer) waits for this, so its flush never
  /// races the outbox restore into a stale local bubble.
  Future<void> get whenOpened => _opened.future;

  Future<void> _open(String userId) async {
    // Local reads are best-effort: a cache that cannot be read is a cold
    // start, never a chat that stays on a spinner or skips its flush (#12).
    var cached = const <Message>[];
    var restoredPending = const <Message>[];
    try {
      cached = await ref
          .read(chatCacheServiceProvider)
          .readMessages(userId, relationshipId);
      if (!mounted) return;
      restoredPending = await _restorePendingMessages(
        userId,
        acknowledged: {
          for (final m in cached)
            if (!m.id.startsWith('_local_')) m.clientMessageId,
        },
      );
    } catch (error) {
      ChatLog.e('chat cache read failed; starting cold', error);
    }
    if (!mounted) return;
    final restoredMessages = _mergeInitialMessages(cached, restoredPending);
    final hasWarmCache = restoredMessages.isNotEmpty;
    if (hasWarmCache && mounted) {
      // Publish the local snapshot before optional poster work. Persisted
      // dimensions reserve each tile's geometry, so hydration cannot shift
      // the message list after first paint.
      state = state.copyWith(isLoading: false, messages: restoredMessages);
      unawaited(_discoverAndPrewarmPosters(restoredMessages));
    }

    // Subscribe before fetching to close the query-to-subscribe race. Header
    // metadata and messages are independent reads, so a slow avatar/name
    // refresh must not hold a cold message list blank — and an offline one
    // must not stop anything below from running (#1).
    await _guard(
      'subscribe',
      () async => _subscribeToRealtime(),
      scope: 'open',
    );
    final conversationRefresh = _guard(
      'conversation',
      _refreshConversation,
      scope: 'open',
    );
    // With a warm cache the user already sees their history, so refresh
    // silently — no loading spinner and no "Syncing" banner flash. Only a
    // cold open (empty cache) shows the initial loading state.
    await _guard(
      'first page',
      () => loadMessages(silent: hasWarmCache),
      scope: 'open',
    );
    // The open's read failed: the page that lands later may hold rows sent
    // after the open (the unread divider skips those).
    if (mounted && !state.firstPageLanded) {
      state = state.copyWith(firstPageLate: true);
    }
    // What the open read successfully, the channel's first subscribe does
    // not read again (M2). Its first page only counts when the join has
    // something else to catch up from: a canonical row (the forward
    // catch-up's cursor) or a sync cursor (changes-since). An empty chat has
    // neither, so a message landing between this read and the join would
    // stay hidden until the next frame; there the join reads the page again.
    if (mounted &&
        _serverPageLanded &&
        (_canonicalIdsHeld().isNotEmpty || _syncCursor != null)) {
      _openReadsDone.add('first page');
    }
    if (await conversationRefresh) _openReadsDone.add('conversation');
    if (!mounted) return;
    // Seed the baseline after the first load so initial history (warm cache
    // or cold fetch) never triggers the receive haptic; only messages that
    // arrive after this point can be "new" (Task 10).
    _lastPartnerMessageId =
        state.messages
            .where(
              (m) =>
                  !m.isMine &&
                  !m.id.startsWith('_local_') &&
                  !m.isGame &&
                  !m.isGameTrail,
            )
            .fold<Message?>(
              null,
              (best, m) =>
                  best == null || m.createdAt.isAfter(best.createdAt)
                      ? m
                      : best,
            )
            ?.id;
    // Same baseline for game cards: where each card sits at open is not a
    // move, however far it travelled since the cache was written. Kept even
    // though most opens are safe without it (review M-1): a batch during the
    // first page can record the warm cache's slot through a by-id refresh.
    for (final m in state.messages) {
      if (m.id.startsWith('_local_')) continue;
      if (m.isGame) _gameCardSortAt[m.id] = m.sortAt;
      if (!m.isMine) _seenPartnerIds.add(m.id);
    }
    _hasSeededPartnerBaseline = true;
    var pinsRead = false;
    await _guard('pins', () async {
      pinsRead = await _refreshPinnedMessages();
    }, scope: 'open');
    if (pinsRead) _openReadsDone.add('pins');
    if (!mounted) return;
    await _guard('stars', _refreshStarredMessageIds, scope: 'open');
    if (!mounted) return;
    if (await _guard(
      'delivered',
      _markPartnerMessagesDelivered,
      scope: 'open',
    )) {
      _openReadsDone.add('delivered');
    }
    _openReadsAt = DateTime.now();
  }

  /// Pulls video posters into the disk cache ahead of the tiles that show
  /// them, so a tile's by-key lookup hits on its first frame instead of the
  /// poster arriving a beat after the list is already on screen.
  ///
  /// Fire-and-forget and fully guarded: a prewarm failure must never affect
  /// the message list, which is why every call site wraps it in unawaited
  /// and this swallows anything the service lets through.
  Future<void> _prewarmPosters(List<Message> messages) async {
    try {
      await ref.read(chatPosterPrewarmerProvider).prewarm(messages);
    } catch (error) {
      ChatLog.e('poster prewarm pass failed (non-fatal)', error);
    }
  }

  Future<void> _discoverAndPrewarmPosters(List<Message> messages) async {
    try {
      await ref.read(chatPosterPrewarmerProvider).discoverCached(messages);
      if (!mounted) return;
      await _prewarmPosters(messages);
    } catch (_) {
      // Optional acceleration only. Rows are already paintable from their
      // persisted content and geometry.
    }
  }

  /// The device saying "network is back" (or the app returning to the
  /// foreground): hurry the socket, then run a resync batch — catch-up,
  /// changes since the cursor, the first page, and a forced flush — instead
  /// of waiting 25–45 s for the heartbeat to notice (#1).
  void _onConnectivityRegained() {
    if (!mounted) return;
    unawaited(
      _repository.ensureRealtimeConnected().catchError((Object error) {
        ChatLog.e('realtime connect nudge failed', error);
      }),
    );
    _onRealtimeEvent(const ChatRealtimeEvent.resync());
  }

  /// The screen reports the app coming back to the foreground. supabase_flutter
  /// rejoins channels on resume too (which emits a resync), but that waits on
  /// the socket; this runs the same batch immediately.
  void onAppResumed() => _onConnectivityRegained();

  /// Reports whether the conversation view is visible and the app is
  /// foregrounded. The screen drives this from its route/lifecycle observers.
  /// Turning the view active marks the currently-loaded partner messages read;
  /// turning it inactive cancels any pending debounced read.
  void setViewActive(bool active) {
    if (_isViewActive == active) return;
    _isViewActive = active;
    // Report presence so the backend can suppress a redundant push while the
    // recipient is looking at this conversation (Spec 9.2). Best-effort.
    unawaited(
      ref
          .read(chatRepositoryProvider)
          .setPresence(active ? relationshipId : null),
    );
    if (active) {
      _startPresenceHeartbeat();
      markAsReadDebounced();
    } else {
      _stopPresenceHeartbeat();
      _readDebounce?.cancel();
    }
  }

  /// Refreshes presence while the conversation is open.
  ///
  /// Presence used to be written once, on entry, and its freshness window
  /// is 45 seconds -- so a partner reading quietly for a minute looked
  /// like they had left. The heartbeat is what makes "Active in this
  /// chat" mean what it says.
  ///
  /// 20 seconds against a 45-second window: two beats can be lost to a
  /// flaky connection before the indicator drops, so it does not flicker
  /// on a brief blip. One row is updated per beat, per open chat.
  void _startPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_isViewActive) return;
      unawaited(ref.read(chatRepositoryProvider).setPresence(relationshipId));
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
  }

  Future<void> _refreshConversation() async {
    final repository = ref.read(chatRepositoryProvider);
    final epoch = _purgeEpoch;
    final updated = await _bounded(repository.getConversation(relationshipId));
    // Purged while the header was in flight (account change, archive): a
    // late answer would un-archive the closed conversation and run the
    // queue-close path for whoever is signed in now.
    if (!mounted || _purgedSince(epoch)) return;

    if (updated == null) {
      await _purgeRelationshipLocalState();
      // The screen may have closed during the purge.
      if (!mounted) return;
      state = state.copyWith(
        conversation: state.conversation.copyWith(
          availability: ConversationAvailability.archived,
        ),
        error: 'This conversation is no longer available.',
        messages: const [],
      );
      return;
    }

    state = state.copyWith(conversation: updated);
    if (!updated.canSend &&
        updated.availability != ConversationAvailability.archived) {
      final user = ref.read(currentUserProvider);
      if (user != null) await _failQueuedForInactiveRelationship(user.id);
    }
    if (updated.availability == ConversationAvailability.archived) {
      await _purgeRelationshipLocalState();
      if (!mounted) return;
      state = state.copyWith(messages: const []);
    }
  }

  /// [_refreshConversation] for callers that do not await it, or must not
  /// stop on it: header metadata being unreachable is logged, never thrown
  /// into an unawaited future or past the steps that follow it.
  Future<void> _refreshConversationSafely() async {
    try {
      await _refreshConversation();
    } catch (error) {
      if (!mounted) return;
      ChatLog.e(
        'conversation refresh failed rel=${ChatLog.shortId(relationshipId)}',
        error,
      );
    }
  }

  void _subscribeToRealtime() {
    final repository = ref.read(chatRepositoryProvider);
    ChatLog.d(
      '[CHAT] realtime subscribe rel=${ChatLog.shortId(relationshipId)}',
    );
    _realtimeSubscription = repository
        .watchConversationEvents(relationshipId)
        .listen(_onRealtimeEvent);
  }

  void _onRealtimeEvent(ChatRealtimeEvent event) {
    switch (event.kind) {
      case ChatRealtimeKind.resync:
        if (event.initial) {
          _pendingInitialResync = true;
        } else {
          _pendingResync = true;
        }
      case ChatRealtimeKind.relationship:
        _pendingRelationship = true;
      case ChatRealtimeKind.pin:
        _pendingPins = true;
      case ChatRealtimeKind.messageInsert:
        // The forward catch-up restores inserts by cursor — but sort_at is
        // the transaction's START time, so a row that began before the
        // newest one held and committed after it sits behind the cursor.
        // Remember the id; the batch reads it if the catch-up did not.
        final id = event.messageId;
        if (id != null) _insertedMessageIds.add(id);
      case ChatRealtimeKind.messageUpdate:
      case ChatRealtimeKind.messageDelete:
      case ChatRealtimeKind.reaction:
        final id = event.messageId;
        if (id == null) {
          _pendingResync = true;
        } else {
          _touchedMessageIds.add(id);
        }
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      ref.read(chatConfigProvider).realtimeRefreshDebounce,
      () => unawaited(_processRealtimeBatch()),
    );
  }

  /// One pass over everything the last debounce window announced, in the
  /// order a person feels it: the new bubble first, then the rows events
  /// named, then (after a reconnect) the cursor sync and the authoritative
  /// first page, then header, pins and delivery marks — each guarded so a
  /// failure in one cannot drop the rest. Frames that land while this runs
  /// get exactly one follow-up pass. A purge (archive, account change)
  /// landing mid-batch ends it: nothing after it may write or send for the
  /// purged state.
  Future<void> _processRealtimeBatch() async {
    if (!mounted) return;
    if (_batchInFlight) {
      _batchRequested = true;
      return;
    }
    _batchInFlight = true;
    try {
      var resync = _pendingResync;
      // The channel's first subscribe, with no reconnect behind it.
      var joined = _pendingInitialResync && !resync;
      final relationship = _pendingRelationship;
      final pins = _pendingPins;
      final touched = Set<String>.of(_touchedMessageIds);
      final inserted = Set<String>.of(_insertedMessageIds);
      _pendingResync = false;
      _pendingInitialResync = false;
      _pendingRelationship = false;
      _pendingPins = false;
      _touchedMessageIds.clear();
      _insertedMessageIds.clear();

      final epoch = _purgeEpoch;
      bool stale() => !mounted || _purgedSince(epoch);
      Future<bool> step(String name, Future<void> Function() run) async {
        if (stale()) return false;
        return _guard(name, run);
      }

      if (joined) {
        // The open subscribes before it reads, so it may still be reading
        // (its steps are bounded): let it finish, then skip what it read
        // moments ago (M2). The catch-up and the changes-since read below
        // still cover the moments before the channel was live.
        await _opened.future;
        if (stale()) return;
        final readAt = _openReadsAt;
        final recent =
            readAt != null &&
            DateTime.now().difference(readAt) <=
                ref.read(chatConfigProvider).networkTimeout;
        if (!recent) {
          joined = false;
          resync = true;
        }
      }
      bool openRead(String name) => joined && _openReadsDone.contains(name);
      final heldBefore = _canonicalIdsHeld();

      var loadedFirstPage = false;
      await step('catch-up', () async {
        loadedFirstPage = await _catchUpFromCursor(
          firstPageIfEmpty: !openRead('first page'),
        );
      });
      // An insert frame whose row the catch-up did not bring committed
      // behind the cursor (C1): read it by id. The common case — the
      // catch-up brought it — costs nothing more.
      if (stale()) return;
      final missedInserts = inserted.difference(_canonicalIdsHeld());
      final byId = {...touched, ...missedInserts};
      if (byId.isNotEmpty) {
        final refreshed = await step(
          'touched rows',
          () => refreshMessagesByIds(byId),
        );
        if (refreshed) {
          _touchedRetries = 0;
          // One entry point for both cues: a move is an UPDATE of a held
          // card, but an UPDATE frame can also be the first sight of a NEW
          // card whose insert frame was lost (T7 carry) — only
          // _maybeReceiveHaptic tells the two apart before recording it.
          if (!stale()) _maybeReceiveHaptic();
        } else if (!stale()) {
          _retryTouchedLater(byId);
        }
      }
      if (resync || joined) {
        await step('changes since cursor', syncChangesSinceCursor);
        // The catch-up already read the first page when nothing canonical
        // was held; a second read would be the same page.
        if (!loadedFirstPage && !openRead('first page')) {
          await step('first page', () => loadMessages(silent: true));
        }
      }
      if (((resync || joined) && !openRead('conversation')) || relationship) {
        await step('conversation', _refreshConversation);
      }
      if (((resync || joined) && !openRead('pins')) || pins) {
        await step('pins', _refreshPinnedMessages);
      }
      if (stale()) return;
      // The open reported what it held as delivered; on the join only rows
      // that arrived since need it.
      final brought = _canonicalIdsHeld().difference(heldBefore).isNotEmpty;
      if (!openRead('delivered') || brought) {
        await step('delivered', _markPartnerMessagesDelivered);
      }
      if (stale()) return;
      // If the user is actively viewing this conversation, newly arrived
      // partner messages are seen immediately (Spec 6.4).
      if (_isViewActive) markAsReadDebounced();
      // A successful (re)subscribe is the best "the network is back" signal
      // there is: send what waited (#1).
      if (resync || joined) unawaited(flushOutbox(force: true));
    } finally {
      _batchInFlight = false;
      if (_batchRequested) {
        _batchRequested = false;
        unawaited(_processRealtimeBatch());
      }
    }
  }

  /// Bounds one network request. A request the network black-holes (no
  /// error, no answer) used to hold the realtime batch open — and with it
  /// every later frame, the resync flush and each first-page load queued
  /// behind it — for as long as the socket lived. Bounded per request
  /// rather than per batch step: the awaiting code is gone once this
  /// throws, so a late answer can never be applied after the step moved on.
  ///
  /// [requests] scales the bound for a call that is several sequential
  /// requests underneath (a changed-since read pages internally, each page
  /// bounded on its own); one bound for all of them failed every sync on a
  /// slow link where no single page was slow.
  Future<T> _bounded<T>(Future<T> request, {int requests = 1}) => request
      .timeout(ref.read(chatConfigProvider).networkTimeout * requests);

  /// Runs one batch (or open) step; a failure is logged, never thrown.
  /// Returns whether the step completed.
  Future<bool> _guard(
    String step,
    Future<void> Function() run, {
    String scope = 'realtime',
  }) async {
    try {
      await run();
      return true;
    } catch (error) {
      if (!mounted) return false;
      ChatLog.e(
        '$scope $step failed rel=${ChatLog.shortId(relationshipId)}',
        error,
      );
      return false;
    }
  }

  /// Puts [ids] back for a later batch after a failed by-id refresh, so an
  /// edit, deletion or reaction is not lost until the next reconnect.
  void _retryTouchedLater(Set<String> ids) {
    if (_touchedRetries >= _maxTouchedRetries) {
      _touchedRetries = 0;
      ChatLog.d(
        '[CHAT] by-id refresh gave up after $_maxTouchedRetries retries '
        'rel=${ChatLog.shortId(relationshipId)} (next resync repairs)',
      );
      return;
    }
    _touchedMessageIds.addAll(ids);
    final delay = _touchedRetryBase * (1 << _touchedRetries);
    _touchedRetries++;
    _touchedRetryTimer?.cancel();
    _touchedRetryTimer = Timer(delay, () => unawaited(_processRealtimeBatch()));
  }

  /// The tail of the first-page load chain (see [loadMessages]).
  Future<void> _firstPageTail = Future<void>.value();

  /// Reads the newest page and makes it authoritative for its span.
  ///
  /// Serialized: a call made while another is in flight sends its request
  /// only after that one has landed. Two overlapping reads (init and the
  /// first resync, a resume and a realtime batch) could land out of order,
  /// and the older response — built before a deletion — re-added the row
  /// the newer one had just dropped. Each link's read is bounded
  /// ([_bounded]), so a hung load cannot hold the chain.
  Future<void> loadMessages({bool silent = false}) {
    final previous = _firstPageTail;
    final run = previous.then((_) => _loadFirstPage(silent: silent));
    _firstPageTail = run.catchError((Object _) {});
    return run;
  }

  Future<void> _loadFirstPage({required bool silent}) async {
    if (!mounted) return;
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    if (!silent) {
      // A Retry: the old failure gives way to the spinner; a new failure
      // sets it again below.
      state = state.copyWith(
        isLoading: true,
        error: null,
        clearLoadFailure: true,
      );
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final epoch = _purgeEpoch;

    try {
      final repository = ref.read(chatRepositoryProvider);
      final pageSize = ref.read(chatConfigProvider).messagePageSize;
      // Only rows held BEFORE the request left may be reconciled away by its
      // response: a send acknowledged or a catch-up row merged while the
      // request was in flight is newer than the server's snapshot.
      final knownBefore = _canonicalIdsHeld();
      final messages = await _bounded(
        repository.getMessages(relationshipId, limit: pageSize),
      );

      if (!mounted) return;
      if (epoch != _purgeEpoch) {
        // Purged while the page was in flight: write nothing back — not the
        // rows, the history cache or a cursor seed. Only drop the spinner.
        if (state.isLoading) state = state.copyWith(isLoading: false);
        return;
      }
      if (messages.isNotEmpty) {
        // First server-confirmed row of the session; older pages continue
        // from here (see _oldestFetchedCursor).
        _oldestFetchedCursor ??= ChatMessageCursor(
          sortAt: messages.last.sortAt,
          id: messages.last.id,
        );
      }
      // The page is authoritative for the span it covers (#6): a row the
      // server no longer returns inside that span is gone everywhere.
      final merged = reconcileWindow(
        _mergeMessages(messages),
        messages,
        exhaustive: messages.length < pageSize,
        knownBefore: knownBefore,
      );
      _serverPageLanded = true;
      state = state.copyWith(
        isLoading: false,
        messages: merged,
        hasMore: messages.length >= pageSize,
        lastSyncedAt: DateTime.now(),
        firstPageLanded: true,
        clearLoadFailure: true,
      );
      _persistHistory(user.id);
      unawaited(_seedSyncCursor(user.id, messages, epoch));
      unawaited(_discoverAndPrewarmPosters(state.messages));
      _maybeReceiveHaptic();
    } catch (error) {
      final mapped = ChatError.from(error);
      ChatLog.e(
        'load messages failed cat=${mapped.category.name} '
        'id=${mapped.correlationId} rel=${ChatLog.shortId(relationshipId)}',
        mapped.cause,
      );
      if (!mounted) return;
      if (epoch != _purgeEpoch) {
        if (state.isLoading) state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(
        isLoading: false,
        // On a silent (realtime/reconnect) refresh, keep the cached view rather
        // than flashing an error banner over live content.
        // Load copy, never send copy (a page read is not a send).
        error: silent ? state.error : mapped.toLoadMessage(),
        // Kept past the writes that follow (header, pins) until a page
        // lands; a silent failure leaves an earlier one as it was.
        loadFailure: silent ? null : mapped.toLoadMessage(),
      );
    }
  }

  /// Fetches every canonical row newer than the newest one we already hold and
  /// merges it in. Used on realtime events and reconnect so a gap larger than
  /// one page is fully restored (Spec 6.1, 6.2, 16). Falls back silently on
  /// error; the subsequent [loadMessages] refresh still runs.
  ///
  /// Read one page per request, each bounded on its own, continuing from the
  /// last row received, at most [_maxCatchUpPages] per pass: one bound over
  /// an unbounded number of pages failed every catch-up of a big gap on a
  /// slow link, and the pages that had arrived were thrown away with it
  /// (M5). A longer gap continues on the next pass, from the newest row now
  /// held.
  ///
  /// Returns true when it loaded the first page itself (nothing canonical
  /// was held), so the caller skips its own, now duplicate, refresh. With
  /// [firstPageIfEmpty] false (the open has just read it) that case reads
  /// nothing.
  Future<bool> _catchUpFromCursor({bool firstPageIfEmpty = true}) async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return false;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    final epoch = _purgeEpoch;

    ChatMessageCursor? cursor;
    for (final message in state.messages) {
      if (message.id.startsWith('_local_')) continue;
      // state.messages is newest-first; the first canonical row is the newest.
      cursor = ChatMessageCursor(sortAt: message.sortAt, id: message.id);
      break;
    }
    if (cursor == null) {
      if (!firstPageIfEmpty) return false;
      // Nothing canonical yet: the first page owns this case. An open-ended
      // forward catch-up would page the entire history oldest-first.
      await loadMessages(silent: true);
      return true;
    }

    final repository = ref.read(chatRepositoryProvider);
    final limit = ref.read(chatConfigProvider).messagePageSize;
    var merged = false;
    try {
      for (var page = 0; page < _maxCatchUpPages; page++) {
        final fresh = await _bounded(
          repository.getMessagesAfter(
            relationshipId,
            after: cursor,
            limit: limit,
            maxPages: 1,
          ),
          // The page, then hydrating its rows.
          requests: 2,
        );
        if (!mounted || epoch != _purgeEpoch || fresh.isEmpty) break;
        state = state.copyWith(
          messages: _mergeMessages(fresh),
          lastSyncedAt: DateTime.now(),
          firstPageLanded: true,
        );
        merged = true;
        // A short page: the gap is closed.
        if (fresh.length < limit) break;
        // Oldest-first: the last row is where the next page continues.
        cursor = ChatMessageCursor(
          sortAt: fresh.last.sortAt,
          id: fresh.last.id,
        );
      }
    } catch (_) {
      // Non-fatal; the reads that landed are kept, the loadMessages()
      // refresh follows on a resync, and the next pass continues.
    }
    if (merged && mounted && epoch == _purgeEpoch) {
      _persistHistory(user.id);
      unawaited(_prewarmPosters(state.messages));
      _maybeReceiveHaptic();
    }
    return false;
  }

  /// See [_catchUpFromCursor]: 20 pages of 50 is 1 000 rows, the same
  /// ceiling a changes-since sync has.
  static const _maxCatchUpPages = 20;

  /// Writes the in-memory history to the cache off the critical path. The
  /// cache's writeMessages throws by design (the cursor sync and the
  /// acknowledged-media handoff await it and depend on that); here a disk
  /// cache failing at runtime is logged — ids and shapes only — instead of
  /// raising an uncaught async error on every page and batch (M1).
  void _persistHistory(String userId, [List<Message>? messages]) {
    unawaited(
      ref
          .read(chatCacheServiceProvider)
          .writeMessages(userId, relationshipId, messages ?? state.messages)
          .catchError((Object error) {
            ChatLog.e(
              'history cache write failed (non-fatal) '
              'rel=${ChatLog.shortId(relationshipId)}',
              error,
            );
          }),
    );
  }

  /// Fires a soft haptic exactly once when a genuinely new partner message
  /// has arrived while the view is active. Content-blind: keys off message
  /// id and [Message.isMine] only, never message content (Task 10). Not fired
  /// for the user's own messages, initial history, or while backgrounded.
  void _maybeReceiveHaptic() {
    // Cards held before this merge. One seen for the first time now is a
    // fresh invite (post_game_message inserts a new row): a message.
    final knownCards = {..._gameCardSortAt.keys};
    final partnerMoved = _notePartnerMoves();
    // Trails and KNOWN cards are excluded: a moved card keeps an old
    // createdAt yet flips to !isMine, and a trail is a new row carrying the
    // card's old sender and createdAt — neither is a new message, and
    // either used to fire the receive chirp depending on what else was in
    // history.
    final eligible = state.messages.where(
      (m) =>
          !m.isMine &&
          !m.id.startsWith('_local_') &&
          !m.isGameTrail &&
          (!m.isGame || !knownCards.contains(m.id)),
    );
    final newestPartner = eligible.fold<Message?>(
      null,
      (best, m) =>
          best == null || m.createdAt.isAfter(best.createdAt) ? m : best,
    );
    final id = newestPartner?.id;
    // Seen before: an older row uncovered when the newest left the fold (an
    // invite that is now a known card, a card I took) is not new.
    final isNew =
        id != null &&
        _hasSeededPartnerBaseline &&
        id != _lastPartnerMessageId &&
        !_seenPartnerIds.contains(id);
    if (id != null) _lastPartnerMessageId = id;
    _seenPartnerIds.addAll(eligible.map((m) => m.id));
    if (!_isViewActive) return;
    if (isNew) {
      ref.read(hapticsProvider).selection();
      if (ref.read(messageSoundsEnabledProvider)) {
        ref.read(soundServiceProvider).play(ChatSound.receive);
      }
    } else if (partnerMoved && _hasSeededPartnerBaseline) {
      // One haptic per merge: a new message in the same merge wins.
      ref.read(hapticsProvider).light();
    }
  }

  /// Records every canonical card's sortAt; true when a partner-owned card
  /// we already knew moved (sortAt advanced) since the previous call.
  bool _notePartnerMoves() {
    var partnerMoved = false;
    for (final m in state.messages) {
      if (!m.isGame || m.id.startsWith('_local_')) continue;
      final previous = _gameCardSortAt[m.id];
      _gameCardSortAt[m.id] = m.sortAt;
      if (previous != null && m.sortAt.isAfter(previous) && !m.isMine) {
        partnerMoved = true;
      }
    }
    return partnerMoved;
  }

  /// The oldest row the SERVER has confirmed this session (first page, then
  /// each older page). Paging continues from here, not from the oldest row
  /// in memory: the cache may hold 200 rows the server never re-sent, and
  /// paging from its bottom would skip refreshing every one of them.
  ChatMessageCursor? _oldestFetchedCursor;

  /// Whether a first page has come back from the server this session. Until
  /// then the list is the warm cache alone and `hasMore` is only
  /// ChatState.initial's default, so it says nothing about history.
  bool _serverPageLanded = false;

  /// The changes-since cursor: the newest server `updated_at` a
  /// changes-since read has applied (or, before the first such read, a seed
  /// from the first page's server timestamps). Server-sourced only — never
  /// a device-stamped editedAt/deletedAt/viewedAt or DateTime.now(), which
  /// on a phone whose clock runs ahead would push it into the future and
  /// skip every change in between. Persisted per (user, relationship),
  /// with [_syncCursorId], the id of that newest change: (updated_at, id) is
  /// the keyset order the server pages in.
  DateTime? _syncCursor;
  String? _syncCursorId;
  bool _syncCursorRestored = false;

  /// How many older pages one pull may fetch while every page it gets is
  /// rows already on screen (see [loadMoreMessages]).
  static const _maxOlderPagesPerPull = 5;

  /// The older-history pull in flight, if any: a jump waits on it rather
  /// than polling [ChatState.isLoadingMore] against a time budget.
  Future<void>? _loadMoreInFlight;

  /// [cancelled], when given, is asked after each page lands; true ends the
  /// pull there (a cancelled jump stops paging between pages).
  Future<void> loadMoreMessages({
    int? limit,
    bool Function()? cancelled,
  }) async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    final user = ref.read(currentUserProvider);
    final epoch = _purgeEpoch;
    state = state.copyWith(isLoadingMore: true);
    final inFlight = Completer<void>();
    _loadMoreInFlight = inFlight.future;

    try {
      final repository = ref.read(chatRepositoryProvider);
      final pageSize = limit ?? ref.read(chatConfigProvider).messagePageSize;
      // Paging from _oldestFetchedCursor re-fetches rows the cache already
      // put on screen. A page made only of those shows the person nothing
      // new, so the same pull continues to the next page (bounded).
      for (var page = 0; page < _maxOlderPagesPerPull; page++) {
        final cursor =
            _oldestFetchedCursor ??
            ChatMessageCursor(
              sortAt: state.messages.last.sortAt,
              id: state.messages.last.id,
            );
        final knownBefore = _canonicalIdsHeld();
        // Bounded like every other read (M4): a black-holed page used to
        // leave isLoadingMore set until the socket died.
        final older = await _bounded(
          repository.getMessages(
            relationshipId,
            before: cursor,
            limit: pageSize,
          ),
        );

        if (!mounted) return;
        if (epoch != _purgeEpoch) {
          // Purged while the page was in flight: write nothing back.
          state = state.copyWith(isLoadingMore: false);
          return;
        }
        if (older.isNotEmpty) {
          _oldestFetchedCursor = ChatMessageCursor(
            sortAt: older.last.sortAt,
            id: older.last.id,
          );
        }
        final hasMore = older.length >= pageSize;
        // Incoming wins (a cached copy of an old row may predate an edit, a
        // deletion or a reaction) and the span below the cursor is reconciled
        // against what the server actually returned (#7).
        state = state.copyWith(
          messages: reconcileWindow(
            _mergeMessages(older),
            older,
            before: cursor,
            exhaustive: !hasMore,
            knownBefore: knownBefore,
          ),
          hasMore: hasMore,
        );
        final showedNew = older.any((m) => !knownBefore.contains(m.id));
        if (showedNew || !hasMore) break;
        if (cancelled?.call() ?? false) break;
      }
      state = state.copyWith(isLoadingMore: false);
      // Persist the refreshed/reconciled history: an older-page drop or
      // patch must survive a restart.
      if (user != null) _persistHistory(user.id);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    } finally {
      if (identical(_loadMoreInFlight, inFlight.future)) {
        _loadMoreInFlight = null;
      }
      inFlight.complete();
    }
  }

  /// The current jump's generation. [ensureMessageLoaded] takes a new one;
  /// a newer jump or [cancelJump] makes an older loop stop between pages.
  int _jumpGeneration = 0;

  /// Stops a running [ensureMessageLoaded] between pages (a touch on the
  /// list, leaving the screen). Writes no state, so it is safe from a
  /// widget's dispose — and on a disposed controller.
  void cancelJump() => _jumpGeneration++;

  /// Pages history back (contiguously, in jumpPageSize pages) until
  /// [messageId] is in state.messages. The target's own (sort_at, id)
  /// bounds the loop against the SERVER-CONFIRMED span: once
  /// _oldestFetchedCursor is at or below the target and the target still is
  /// not loaded, it cannot be — stop instead of paging to the beginning of
  /// time (#30). The fetched cursor, not state.messages.last, is the bound
  /// because the cache may hold older rows the server has not re-sent yet
  /// (loadMoreMessages re-fetches that span page by page).
  ///
  /// The by-id lookup is bounded ([_bounded]) like every other read. If it
  /// fails or times out the jump ends ([JumpTargetResult.exhausted]): with
  /// no position to bound it, paging would be blind, on exactly the slow
  /// link where it costs most.
  ///
  /// One jump at a time: starting one cancels the previous, which stops
  /// after its in-flight page. A pull already in flight (a scroll-triggered
  /// one, or the previous jump's) is awaited, never raced against a time
  /// budget.
  Future<JumpTargetResult> ensureMessageLoaded(
    String messageId, {
    int maxPages = 40,
  }) async {
    final generation = ++_jumpGeneration;
    bool cancelled() => generation != _jumpGeneration;
    bool loaded() => state.messages.any((m) => m.id == messageId);
    if (loaded()) return JumpTargetResult.loaded;

    final Message target;
    try {
      final rows = await _bounded(
        ref.read(chatRepositoryProvider).getMessagesByIds(relationshipId, [
          messageId,
        ]),
      );
      if (!mounted) return JumpTargetResult.cancelled;
      if (cancelled()) return JumpTargetResult.cancelled;
      if (loaded()) return JumpTargetResult.loaded;
      if (rows.isEmpty) return JumpTargetResult.notFound;
      target = rows.first;
    } catch (_) {
      if (!mounted || cancelled()) return JumpTargetResult.cancelled;
      return JumpTargetResult.exhausted; // offline / timed out
    }

    bool pagedPastTarget() {
      final floor = _oldestFetchedCursor;
      // Target not older than the oldest fetched row → it lies inside the
      // span the server has already answered for.
      return floor != null && !isOlderThanCursor(target, floor);
    }

    final limit = ref.read(chatConfigProvider).jumpPageSize;
    var pages = 0;
    while (true) {
      if (!mounted || cancelled()) return JumpTargetResult.cancelled;
      if (loaded()) return JumpTargetResult.loaded;
      if (pagedPastTarget()) return JumpTargetResult.notFound;
      if (!state.hasMore) return JumpTargetResult.notFound;
      final inFlight = _loadMoreInFlight;
      if (state.isLoadingMore && inFlight != null) {
        // A pull is in flight (scroll-triggered, or a cancelled jump's last
        // page); let it land. Every page in it is bounded.
        await inFlight;
        continue;
      }
      if (pages >= maxPages) return JumpTargetResult.tooFarBack;
      pages++;
      final cursorBefore = _oldestFetchedCursor;
      await loadMoreMessages(limit: limit, cancelled: cancelled);
      if (!mounted || cancelled()) return JumpTargetResult.cancelled;
      if (identical(_oldestFetchedCursor, cursorBefore) && state.hasMore) {
        // The fetch failed (loadMoreMessages swallows the error and leaves
        // hasMore true). Don't spin on a dead network.
        return JumpTargetResult.exhausted;
      }
    }
  }

  /// Canonical ids in memory right now — the set a page response may
  /// reconcile against (see [reconcileWindow]'s `knownBefore`).
  Set<String> _canonicalIdsHeld() => {
    for (final m in state.messages)
      if (!m.id.startsWith('_local_')) m.id,
  };

  Future<void> sendMessage(
    String content, {
    String? replyToMessageId,
    String? quotedText,
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!Message.isValidContent(content) || !state.conversation.canSend) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: content,
      createdAt: now,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );

    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: content,
      createdAt: now,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );

    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    // The optimistic row is intentionally published first so a local
    // SQLite write can never delay the tap-to-bubble response.
    await _enqueueAndFlush(user.id, pending);
  }

  /// Every send enters the durable queue first and leaves through
  /// [flushOutbox], so a message typed while an earlier one is still waiting
  /// for the network goes out after it (Spec 4.2 enqueue order) instead of
  /// overtaking it and showing the two phones different orders (#5). The
  /// optimistic bubble is already on screen; this is the disk + network leg.
  Future<void> _enqueueAndFlush(String userId, PendingSend pending) async {
    final epoch = _purgeEpoch;
    try {
      await ref.read(chatCacheServiceProvider).putOutbox(userId, pending);
    } catch (error) {
      if (!mounted || _purgedSince(epoch)) return;
      ChatLog.e('outbox write failed; sending once without the queue', error);
      await _sendWithoutOutbox(userId, pending);
      return;
    }
    // Purged while the write was in flight (sign-out, account switch,
    // archive): the row went with the purge, and nothing may follow it —
    // above all not under whichever account is signed in now (I1).
    // Disposed: the row is durable; the drainer or the next open sends it.
    if (!mounted || _purgedSince(epoch)) return;
    _unsavedSends.remove(pending.clientMessageId);
    if (_needsUpload(pending)) {
      // Design 3: the upload runs outside the queue; the insert joins it
      // when the upload lands.
      await _uploadOutsideQueue(pending);
      return;
    }
    await flushOutbox();
  }

  /// The preparation sends' version of [_enqueueAndFlush]: durable row
  /// first, then preparation. On a dead cache the bubble is held failed and
  /// retryable instead of spinning forever with no row behind it (M1).
  Future<void> _enqueuePreparation(String userId, PendingSend pending) async {
    final epoch = _purgeEpoch;
    try {
      await ref.read(chatCacheServiceProvider).putOutbox(userId, pending);
    } catch (error) {
      if (_purgedSince(epoch)) return;
      ChatLog.e('outbox write failed; holding the media unsent', error);
      _holdUnsaved(pending, null);
      return;
    }
    // Purged while the write was in flight: nothing may follow it (I1).
    if (_purgedSince(epoch)) return;
    _unsavedSends.remove(pending.clientMessageId);
    await _prepareAndAttemptSend(pending);
  }

  /// Takes the RAW picked (pre-compression) image path — deliberately not
  /// an already-prepared one. The optimistic bubble is added using this raw
  /// file FIRST, so it appears the instant the user taps send; ChatImage-
  /// Preparer's compression (a real decode/resize/encode pass, not
  /// instant) runs after, in the background, before the actual upload.
  /// Compression happening before the optimistic add was the cause of the
  /// visible "nothing happens for a moment" delay this used to have.
  Future<void> sendImageMessage({
    required String localPath,
    String caption = '',
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!state.conversation.canSend) return;
    if (!Message.isValidContent(caption, hasMedia: true)) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (!_localFileExists(localPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That image is no longer available.');
      }
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();

    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: caption,
      localMediaPath: localPath,
      mediaType: 'image',
      requiresPreparation: true,
      createdAt: now,
    );

    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: caption,
      createdAt: now,
      mediaType: 'image',
      localMediaPath: localPath,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    // Persist the raw-source preparation job before doing any decode/encode
    // work. If the app is killed mid-compression, the same visible bubble and
    // source can be restored and prepared again on the next outbox flush.
    await _enqueuePreparation(user.id, pending);
  }

  String _imageRejectionMessage(String code) {
    switch (code) {
      case 'media_type_unsupported':
        return 'That file type is not supported. Choose a JPG, PNG, or WebP image.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'That image is too large to send. Try a smaller one.';
      case 'media_decode_failed':
      case 'media_dimensions_excessive':
        return 'That image could not be read. Try a different one.';
      default:
        return 'That image is no longer available.';
    }
  }

  /// Sends a voice message, mirroring sendImageMessage's exact shape:
  /// duration-bounds check (mirrors sendImageMessage's byte-size check),
  /// optimistic Message + outbox write, flush through the shared retry
  /// path. See design spec's "Sending" section.
  Future<void> sendVoiceMessage({
    required String localPath,
    required int durationMs,
    required List<int> waveform,
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (!_localFileExists(localPath)) {
      if (mounted) {
        state = state.copyWith(
          error: 'That voice message is no longer available.',
        );
      }
      return;
    }

    // Belt-and-suspenders duration check mirroring VoiceRecorderService's
    // own maxDuration cap — a stale/modified local file or a future
    // caller bypassing the recorder service should not be able to queue
    // an oversized send.
    if (durationMs > VoiceRecorderService.maxDuration.inMilliseconds) {
      if (mounted) {
        state = state.copyWith(
          error: 'That voice message is too long to send.',
        );
      }
      return;
    }
    if (durationMs < VoiceRecorderService.minDuration.inMilliseconds) {
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: localPath,
      mediaMimeType: 'audio/mp4',
      mediaType: 'audio',
      mediaDurationMs: durationMs,
      waveform: waveform,
      createdAt: now,
    );
    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: '',
      createdAt: now,
      mediaType: 'audio',
      localMediaPath: localPath,
      mediaDurationMs: durationMs,
      waveform: waveform,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    await _enqueueAndFlush(user.id, pending);
  }

  /// Queues a streak, mirroring sendEphemeralVideoMessage's shape.
  ///
  /// Returns as soon as the row is queued: the upload happens behind the
  /// optimistic bubble, and _attemptSend owns retry and backoff. The
  /// camera therefore pops immediately rather than holding the user
  /// through a 25MB upload.
  /// Records the budget the server returned after a streak view.
  ///
  /// mark_streak_viewed decrements server-side and returns what remains,
  /// but nothing was applying that locally: the bubble kept the count it
  /// was built with, so a streak could be reopened indefinitely until an
  /// unrelated refresh happened to bring the new row down.
  ///
  /// Trusts the server's number rather than decrementing locally — the
  /// budget is server-owned, and a client that computes it can drift from
  /// (or outvote) the row that actually gates the clips.
  void applyStreakViewSpent(String messageId, int viewsRemaining) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    ChatLog.diagnostic(
      'applyStreakViewSpent',
      'id=${ChatLog.shortId(messageId)} left=$viewsRemaining found=${index != -1}',
    );
    if (index == -1) return;

    final updated = [...state.messages];
    // viewedAt is stamped alongside the count. It is what locks the SENDER
    // out — their bubble reads "Opened" once the recipient has watched, and
    // the server refuses their reopen on the same field. Applying only the
    // count left the sender's side of the conversation still offering Play
    // after it had been seen.
    //
    // Only ever set, never cleared: the server owns the real timestamp and
    // the next refresh replaces this approximation with it.
    updated[index] = updated[index].copyWith(
      streakViewsRemaining: viewsRemaining,
      viewedAt: updated[index].viewedAt ?? DateTime.now(),
    );
    state = state.copyWith(messages: updated);
  }

  Future<void> sendStreakMessage({
    required String localPath,
    required int durationMs,
    required int viewsRemaining,
    // Defaults to the video mime every existing caller already sends,
    // so an unmigrated/older call site (or an already-queued outbox
    // entry rehydrated by an app update, which calls _attemptSend
    // directly rather than re-running this constructor — see that
    // method's own read of pending.mediaMimeType) behaves exactly as it
    // did before photo streaks existed.
    String mimeType = 'video/mp4',
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (!_localFileExists(localPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That streak is no longer available.');
      }
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();

    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: localPath,
      mediaMimeType: mimeType,
      mediaType: 'streak',
      mediaDurationMs: durationMs,
      streakViewsRemaining: viewsRemaining,
      createdAt: now,
    );
    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: '',
      createdAt: now,
      mediaType: 'streak',
      localMediaPath: localPath,
      mediaDurationMs: durationMs,
      streakViewsRemaining: viewsRemaining,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    await _enqueueAndFlush(user.id, pending);
  }

  /// Sends a video message, mirroring sendImageMessage/sendVoiceMessage's
  /// exact shape. Unlike either of those, this requires the thumbnail file
  /// to also exist before queueing — a video with no way to ever get a
  /// poster is a worse outcome than asking the user to retry the whole
  /// prepare step (see design spec's error table: thumbnail EXTRACTION
  /// failure blocks the send before it's queued; thumbnail UPLOAD failure,
  /// handled in _attemptSend below, is non-fatal once the video itself has
  /// already uploaded successfully).
  ///
  /// Takes an ALREADY-PREPARED file (post-ChatVideoPreparer) — this is
  /// deliberate, not an oversight: it's what keeps this method fully
  /// testable with plain fixture files and no real video_compress/native
  /// calls (see chat_state_send_video_message_test.dart). The gallery-pick
  /// flow that needs the optimistic bubble to appear BEFORE compression
  /// finishes calls [sendVideoMessageFromTrim] instead, which runs
  /// ChatVideoPreparer itself and then calls this method with the result —
  /// this method's own optimistic Message becomes the SECOND bubble
  /// insertion in that flow only if called directly; sendVideoMessageFromTrim
  /// avoids that by updating its own already-inserted bubble in place
  /// rather than going through this method's optimistic-insert path (see
  /// its own doc comment for the split).
  Future<void> sendVideoMessage({
    required String localPath,
    required int durationMs,
    required String thumbnailLocalPath,
    required int width,
    required int height,
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (!_localFileExists(localPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }
    if (!_localFileExists(thumbnailLocalPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }

    // Belt-and-suspenders duration check mirroring sendVoiceMessage's own
    // check against VoiceRecorderService.maxDuration — a stale/modified
    // local file or a future caller bypassing ChatVideoPreparer should not
    // be able to queue an oversized send.
    if (durationMs > ChatVideoPreparer.maxDuration.inMilliseconds) {
      if (mounted) {
        state = state.copyWith(error: 'That video is too long to send.');
      }
      return;
    }
    if (durationMs < ChatVideoPreparer.minDuration.inMilliseconds) {
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: localPath,
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: durationMs,
      localThumbnailPath: thumbnailLocalPath,
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: width,
      mediaHeight: height,
      createdAt: now,
    );
    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: '',
      createdAt: now,
      mediaType: 'video',
      localMediaPath: localPath,
      // On-device poster so the bubble renders a real thumbnail
      // immediately, rather than a blank tile until the upload and server
      // round-trip produce a signed thumbnail URL.
      localThumbnailPath: thumbnailLocalPath,
      mediaDurationMs: durationMs,
      mediaWidth: width,
      mediaHeight: height,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    await _enqueueAndFlush(user.id, pending);
  }

  /// Gallery-pick entry point for video: shows the optimistic bubble the
  /// instant the user confirms their trim selection (isPreparing: true, no
  /// real media yet), matching sendImageMessage's "show first, prepare in
  /// the background" ordering — no more blocking modal dialog
  /// (VideoPrepareProgressDialog, now unused by chat_screen.dart's
  /// _attachVideo) held open until ChatVideoPreparer's compression
  /// finishes. MessageBubble/VideoMessagePlayer render a
  /// compressing-progress state while isPreparing is true (see
  /// _VideoCompressingTile). Once prepare() finishes, the SAME message
  /// (same id) is updated in place with the real duration/dimensions/local
  /// paths and isPreparing: false, then the upload runs via the same
  /// PendingSend/_attemptSend path sendVideoMessage itself uses — this
  /// method deliberately does NOT call sendVideoMessage (that would insert
  /// a SECOND, separate optimistic bubble on top of this one); it inlines
  /// the equivalent PendingSend/outbox/_attemptSend steps against its own
  /// already-inserted message instead.
  Future<void> sendVideoMessageFromTrim({
    required String localPath,
    required Duration trimStart,
    required Duration trimEnd,
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (!_localFileExists(localPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final trimWindowMs = (trimEnd - trimStart).inMilliseconds;

    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: localPath,
      mediaType: 'video',
      mediaDurationMs: trimWindowMs,
      requiresPreparation: true,
      trimStartMs: trimStart.inMilliseconds,
      trimEndMs: trimEnd.inMilliseconds,
      createdAt: now,
    );

    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: '',
      createdAt: now,
      mediaType: 'video',
      // The RAW (uncompressed) picked file — good enough for
      // VideoMessagePlayer's eventual real render once isPreparing flips
      // false and the compressed file/thumbnail are threaded through
      // below; while isPreparing is true this path isn't rendered as a
      // player at all (see _VideoCompressingTile), so its exact
      // provenance (raw vs. compressed) doesn't matter yet.
      localMediaPath: localPath,
      // Provisional — the trim window's own length, not yet the real
      // post-compress duration (which can differ by a frame or two of
      // encoder rounding). Corrected below once prepare() returns.
      mediaDurationMs: trimWindowMs,
      isPreparing: true,
      compressProgress: 0,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    await _enqueuePreparation(user.id, pending);
  }

  String _videoRejectionMessage(String code) {
    switch (code) {
      case 'media_type_unsupported':
        return 'That file type is not supported. Choose an MP4 or MOV video.';
      case 'media_too_large':
        return 'That video is more than 500MB. Trim it shorter or compress it before sending.';
      case 'media_compress_failed':
        return "That video couldn't be compressed small enough to send. Try trimming it shorter.";
      case 'media_too_long':
        return 'That video is too long. Trim it to 3 minutes or less.';
      case 'media_too_short':
        return 'That clip is too short to send.';
      case 'media_decode_failed':
        return 'That video could not be read. Try a different one.';
      case 'thumbnail_failed':
        return 'Could not prepare that video. Try again.';
      default:
        return 'That video is no longer available.';
    }
  }

  /// Completes a persisted raw-media job, updates the same optimistic bubble
  /// in place, then hands the prepared payload to the ordinary durable send
  /// pipeline (upload outside the queue, then the insert in queue order —
  /// Design 3). This is deliberately shared by first send, manual retry, and
  /// process-restart outbox recovery so those paths cannot drift apart.
  Future<void> _prepareAndAttemptSend(PendingSend pending) async {
    // Reached after a caller's await (the enqueue write, Retry's write): a
    // disposed controller has no ref to read.
    if (!mounted) return;
    final user = ref.read(currentUserProvider);
    // Never prepare or write a row for a different account (I1).
    if (user == null || user.id != pending.senderId) return;
    if (!_preparingClientIds.add(pending.clientMessageId)) return;
    // A compression runs for seconds: an account change or archive landing
    // meanwhile must not put this row back into the purged queue.
    final epoch = _purgeEpoch;

    var preparing = pending.copyWith(
      state: PendingSendState.sending,
      nextAttemptAt: null,
      lastErrorCategory: null,
    );
    String? generatedPosterPath = pending.localThumbnailPath;
    PendingSend? ready;

    try {
      // The caller's copy may be a stale flush snapshot (I3): the row
      // decides. Already prepared, removed or failed — nothing to do here;
      // whoever prepared it carries it on.
      final current = await _readOutboxRow(user.id, pending.clientMessageId);
      // Disposed (the person left the chat) or purged meanwhile: no ref
      // read may follow — it throws once the provider is gone — and the
      // row, still awaiting preparation, is prepared again on the next open.
      if (!mounted ||
          _purgedSince(epoch) ||
          current == null ||
          current.state == PendingSendState.failedPermanent ||
          !current.requiresPreparation) {
        return;
      }
      preparing = current.copyWith(
        state: PendingSendState.sending,
        nextAttemptAt: null,
        lastErrorCategory: null,
      );
      await ref.read(chatCacheServiceProvider).putOutbox(user.id, preparing);
      if (!mounted || _purgedSince(epoch)) return;

      late final PendingSend prepared;
      if (preparing.mediaType == 'image') {
        final image = await const ChatImagePreparer().prepare(
          preparing.localMediaPath!,
          // Durable, chat-owned (ChatImagePicker.ownsPath): the queued
          // upload must outlive an OS temp purge.
          outputDirectory: ref.read(chatImagePickerProvider).preparedDirectory,
        );
        if (!mounted || _purgedSince(epoch)) {
          // The purge already cleaned what it could see; this file landed
          // after it, in a folder nothing else reads. Disposed: the next
          // open prepares the raw pick again.
          await ChatImagePicker.discard(image.file.path);
          return;
        }
        prepared = preparing.copyWith(
          localMediaPath: image.file.path,
          mediaMimeType: image.mimeType,
          requiresPreparation: false,
          state: PendingSendState.queued,
        );
        _updateOptimisticMessage(
          preparing.clientMessageId,
          (message) => message.copyWith(localMediaPath: image.file.path),
        );
      } else if (preparing.mediaType == 'video') {
        final video = await const ChatVideoPreparer().prepare(
          localPath: preparing.localMediaPath!,
          trimStart:
              preparing.trimStartMs == null
                  ? null
                  : Duration(milliseconds: preparing.trimStartMs!),
          trimEnd:
              preparing.trimEndMs == null
                  ? null
                  : Duration(milliseconds: preparing.trimEndMs!),
          onProgress: (value) {
            _updateOptimisticMessage(
              preparing.clientMessageId,
              (message) => message.copyWith(
                isPreparing: true,
                compressProgress: (value / 100).clamp(0.0, 1.0),
              ),
            );
          },
          onPosterReady: (posterPath) {
            generatedPosterPath = posterPath;
            _updateOptimisticMessage(
              preparing.clientMessageId,
              (message) => message.copyWith(localThumbnailPath: posterPath),
            );
          },
        );
        if (!mounted || _purgedSince(epoch)) return;
        prepared = preparing.copyWith(
          localMediaPath: video.file.path,
          mediaMimeType: video.mimeType,
          mediaDurationMs: video.durationMs,
          localThumbnailPath: video.thumbnailFile.path,
          thumbnailMimeType: video.thumbnailMimeType,
          mediaWidth: video.width,
          mediaHeight: video.height,
          requiresPreparation: false,
          state: PendingSendState.queued,
        );
        _updateOptimisticMessage(
          preparing.clientMessageId,
          (message) => message.copyWith(
            localMediaPath: video.file.path,
            localThumbnailPath: video.thumbnailFile.path,
            mediaDurationMs: video.durationMs,
            mediaWidth: video.width,
            mediaHeight: video.height,
            isPreparing: false,
          ),
        );
      } else {
        // Old/corrupt cache rows cannot be prepared safely. Keep the bubble
        // visible and removable instead of attempting a payload-less insert.
        await _handlePreparationFailure(
          user.id,
          preparing,
          'media_type_unsupported',
          'That media could not be prepared. Try choosing it again.',
          epoch: epoch,
        );
        return;
      }

      // Commit the prepared paths before upload. A crash after this point
      // resumes upload directly instead of recompressing the original file.
      await ref.read(chatCacheServiceProvider).putOutbox(user.id, prepared);
      // The prepared file is now the durable source; the staged pick (only
      // paths ChatImagePicker owns — never a place photo or a share) can go.
      if (prepared.mediaType == 'image') {
        await ChatImagePicker.discard(preparing.localMediaPath);
      }
      if (!mounted || _purgedSince(epoch)) return;
      ready = prepared;
    } on ChatImageRejected catch (rejected) {
      await _handlePreparationFailure(
        user.id,
        preparing,
        rejected.code,
        _imageRejectionMessage(rejected.code),
        epoch: epoch,
      );
    } on ChatVideoRejected catch (rejected) {
      preparing = preparing.copyWith(localThumbnailPath: generatedPosterPath);
      await _handlePreparationFailure(
        user.id,
        preparing,
        rejected.code,
        _videoRejectionMessage(rejected.code),
        epoch: epoch,
      );
    } catch (error) {
      // Unexpected/native preparation failures use the same bounded retry
      // policy as uploads. The outbox row still contains the raw source and
      // trim window, so an automatic retry is safe and complete. Not once
      // disposed: nothing can be written through a provider that is gone.
      if (!mounted) return;
      await _handleSendFailure(
        user.id,
        preparing,
        ChatError.from(error),
        epoch: epoch,
      );
    } finally {
      _preparingClientIds.remove(pending.clientMessageId);
    }
    // Preparation is over (the item is no longer "preparing"): upload it
    // outside the queue, then the insert joins the queue (Design 3).
    final prepared = ready;
    if (prepared != null && mounted) await _uploadOutsideQueue(prepared);
  }

  Future<void> _handlePreparationFailure(
    String userId,
    PendingSend pending,
    String code,
    String userMessage, {
    required int epoch,
  }) async {
    // Runs after the preparer's awaits: the person may have left the chat
    // (a ref read on a disposed provider throws, and from a catch clause
    // nothing above catches it). The row stays awaiting preparation; the
    // next open prepares it again and fails it there.
    if (!mounted || _purgedSince(epoch)) return;
    final failed = pending.copyWith(
      state: PendingSendState.failedPermanent,
      lastErrorCategory: code,
      nextAttemptAt: null,
    );
    await ref.read(chatCacheServiceProvider).putOutbox(userId, failed);
    if (!mounted || _purgedSince(epoch)) return;
    state = state.copyWith(
      isSending: false,
      error: userMessage,
      messages:
          state.messages
              .map(
                (message) =>
                    _isLocalBubbleFor(message, pending.clientMessageId)
                        ? message.copyWith(
                          status: MessageStatus.failed,
                          isPreparing: false,
                        )
                        : message,
              )
              .toList(),
    );
  }

  /// Whether [message] is the still-local bubble of [clientMessageId]. Every
  /// failure path maps statuses through this: the canonical row of the same
  /// message (merged by a realtime catch-up while the failing attempt's
  /// answer was lost) is delivered and must never read queued or failed
  /// (final-review I1).
  static bool _isLocalBubbleFor(Message message, String clientMessageId) =>
      message.clientMessageId == clientMessageId &&
      message.id.startsWith('_local_');

  /// Whether the server's row for [clientMessageId] is on screen with no
  /// local bubble left beside it: the message arrived, whatever the attempt
  /// that sent it went on to report.
  bool _deliveredOnScreen(String clientMessageId) {
    var canonical = false;
    for (final m in state.messages) {
      if (m.clientMessageId != clientMessageId) continue;
      if (m.id.startsWith('_local_')) return false;
      canonical = true;
    }
    return canonical;
  }

  void _updateOptimisticMessage(
    String clientMessageId,
    Message Function(Message current) update,
  ) {
    if (!mounted) return;
    final index = state.messages.indexWhere(
      (message) => _isLocalBubbleFor(message, clientMessageId),
    );
    if (index == -1) return;
    final messages = List<Message>.from(state.messages);
    messages[index] = update(messages[index]);
    state = state.copyWith(messages: messages);
  }

  /// Sends an ephemeral (view-once) video message, mirroring
  /// sendVideoMessage's exact shape with one addition: the constructed
  /// PendingSend/Message carries isViewOnce: true. Deliberately a separate
  /// method rather than a parameter on sendVideoMessage — the two have
  /// different validation (10s cap here vs. ChatVideoPreparer.maxDuration's
  /// 3-minute default there) and conflating them risks exactly the kind of
  /// accidental cross-contamination Part 1 was careful to avoid with
  /// _attemptSend's branching. _attemptSend itself needs NO new branching:
  /// an ephemeral capture's PendingSend.mediaType is 'video' just like a
  /// gallery pick, so it flows through the identical two-intent upload path
  /// already there — only the final sendTextMessage call (below, and in
  /// _attemptSend) needs isViewOnce threaded through.
  Future<void> sendEphemeralVideoMessage({
    required String localPath,
    required int durationMs,
    required String thumbnailLocalPath,
    required int width,
    required int height,
    ValueChanged<Message>? onOptimisticMessage,
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (!_localFileExists(localPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }
    if (!_localFileExists(thumbnailLocalPath)) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }

    // Belt-and-suspenders duration check against the 10-second ephemeral
    // cap — mirrors sendVideoMessage's identical check against
    // ChatVideoPreparer.maxDuration, but against the ephemeral-specific
    // bound, since a stale/modified local file or a future caller
    // bypassing EphemeralCameraScreen's own recording cap should not be
    // able to queue an oversized ephemeral send.
    const ephemeralMaxDuration = Duration(seconds: 10);
    if (durationMs > ephemeralMaxDuration.inMilliseconds) {
      if (mounted) {
        state = state.copyWith(error: 'That video is too long to send.');
      }
      return;
    }
    if (durationMs < ChatVideoPreparer.minDuration.inMilliseconds) {
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: localPath,
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: durationMs,
      localThumbnailPath: thumbnailLocalPath,
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: width,
      mediaHeight: height,
      isViewOnce: true,
      createdAt: now,
    );
    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: '',
      createdAt: now,
      mediaType: 'video',
      localMediaPath: localPath,
      mediaDurationMs: durationMs,
      mediaWidth: width,
      mediaHeight: height,
      isViewOnce: true,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );
    onOptimisticMessage?.call(optimistic);

    await _enqueueAndFlush(user.id, pending);
  }

  bool _localFileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> retryMessage(Message message) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final epoch = _purgeEpoch;

    // A dead cache must not stop Retry reaching an unsaved send (M1).
    var outbox = const <PendingSend>[];
    try {
      outbox = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(user.id, relationshipId: relationshipId);
    } catch (error) {
      ChatLog.e('retry could not read the outbox', error);
    }
    if (!mounted || _purgedSince(epoch)) return;
    PendingSend? pending;
    for (final item in outbox) {
      if (item.clientMessageId == message.clientMessageId) {
        pending = item;
        break;
      }
    }
    if (pending == null) {
      // No queue row: a send whose outbox write failed (M1). Try the queue
      // again (the cache may be back), else one more direct attempt.
      final unsaved = _unsavedSends[message.clientMessageId];
      if (unsaved == null) return;
      final preparesVideo =
          unsaved.requiresPreparation && unsaved.mediaType == 'video';
      _updateOptimisticMessage(
        message.clientMessageId,
        (entry) => entry.copyWith(
          status: MessageStatus.sending,
          isPreparing: preparesVideo,
          compressProgress: preparesVideo ? 0 : null,
        ),
      );
      await _enqueueAndFlush(
        user.id,
        unsaved.copyWith(
          state: PendingSendState.queued,
          nextAttemptAt: null,
          lastErrorCategory: null,
          // The person asked again: a fresh budget of re-uploads (N3).
          mediaReuploads: 0,
        ),
      );
      return;
    }

    final needsUpload = _needsUpload(pending);
    state = state.copyWith(
      messages:
          state.messages
              .map(
                (entry) =>
                    _isLocalBubbleFor(entry, message.clientMessageId)
                        ? entry.copyWith(
                          status: MessageStatus.sending,
                          // A ring at 0 (and its cancel) only when there is
                          // an upload to run; a row whose bytes are already
                          // up has only its insert left, which no cancel
                          // stops.
                          uploadProgress: needsUpload ? 0.0 : null,
                        )
                        : entry,
              )
              .toList(),
    );

    final queued = pending.copyWith(
      state: PendingSendState.queued,
      nextAttemptAt: null,
      lastErrorCategory: null,
      // The person asked again: a fresh budget of re-uploads.
      mediaReuploads: 0,
    );
    if (queued.requiresPreparation) {
      _updateOptimisticMessage(
        queued.clientMessageId,
        (entry) => entry.copyWith(
          status: MessageStatus.sending,
          isPreparing: queued.mediaType == 'video',
          compressProgress: queued.mediaType == 'video' ? 0 : null,
        ),
      );
      // The row decides what preparation does (I3), so it must say queued.
      await ref.read(chatCacheServiceProvider).putOutbox(user.id, queued);
      if (_purgedSince(epoch)) return;
      await _prepareAndAttemptSend(queued);
    } else {
      // Back into the queue, then the whole queue in order: a tap on the
      // second of two waiting messages must not send it before the first.
      await ref.read(chatCacheServiceProvider).putOutbox(user.id, queued);
      await flushOutbox(force: true);
    }
  }

  Future<void> removeFailedMessage(Message message) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Look up the outbox entry before removing it so a video's thumbnail
    // temp file (tracked only on PendingSend, not on Message — see
    // retryMessage's identical lookup above) can also be cleaned up here.
    final epoch = _purgeEpoch;
    final outbox = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(user.id, relationshipId: relationshipId);
    PendingSend? pending;
    for (final item in outbox) {
      if (item.clientMessageId == message.clientMessageId) {
        pending = item;
        break;
      }
    }

    await ref
        .read(chatCacheServiceProvider)
        .removeOutbox(user.id, relationshipId, message.clientMessageId);
    _unsavedSends.remove(message.clientMessageId);
    // A preparation-stage path is the user's raw picker source, not a staging
    // artifact owned by chat. Never delete it when dismissing a failed row.
    if (pending?.requiresPreparation != true) {
      await _deleteStagedMedia(message.localMediaPath);
    }
    // A preparation-stage image whose source chat itself staged is also
    // gone for good once the person removes the failed row (#27).
    await ChatImagePicker.discard(pending?.localMediaPath);
    await ChatImagePicker.discard(message.localMediaPath);
    await _deleteStagedMedia(pending?.localThumbnailPath);

    // Purged meanwhile: writing `remaining` would put the purged history
    // back into the cache.
    if (!mounted || _purgedSince(epoch)) return;
    final remaining =
        state.messages
            .where((entry) => entry.clientMessageId != message.clientMessageId)
            .toList();
    state = state.copyWith(messages: remaining);

    // loadMessages/_catchUpFromCursor persist the FULL state.messages list
    // (including any still-failed/optimistic local entries) to the message
    // cache on every sync. Without also re-writing here, a failed message
    // removed from state above stays in that on-disk cache from whichever
    // earlier write captured it — and _init()'s readMessages() on the next
    // cold start restores it right back, even though the outbox entry (the
    // thing that actually drove the retry/remove UI) is already gone.
    _persistHistory(user.id, remaining);
  }

  Future<void> deleteMessage(Message message) async {
    await _repository.deleteMessage(message.id);
    // Disposed during the server call: `state` must not be read (N2).
    if (!mounted) return;
    final mediaKeys = _mediaKeysOf({
      message.id,
      message.clientMessageId,
    }, [message]);
    state = state.copyWith(
      messages:
          state.messages
              .map(
                (entry) =>
                    entry.id == message.id
                        ? entry.copyWith(deletedAt: DateTime.now(), content: '')
                        : entry,
              )
              .toList(),
    );
    // Its cached voice/video bytes go too, and its photo/poster entries
    // (ChatMessageRemovals).
    ref.read(chatMessageRemovalsProvider).announce({
      message.id,
      message.clientMessageId,
    }, mediaKeys: mediaKeys);
    _refreshStarredIfAny({message.id});
  }

  /// An open Starred list shows a starred row's text: refetch it when one
  /// was edited, deleted or changed by a sync (star/unstar do the same).
  void _refreshStarredIfAny(Iterable<String> ids) {
    final starred = state.starredMessageIds;
    if (starred.isEmpty) return;
    if (ids.any(starred.contains)) ref.invalidate(starredMessagesProvider);
  }

  Future<void> editMessage(Message message, String newContent) async {
    await _repository.editMessage(
      messageId: message.id,
      newContent: newContent,
    );
    if (!mounted) return;
    _refreshStarredIfAny({message.id});
    state = state.copyWith(
      messages:
          state.messages
              .map(
                (entry) =>
                    entry.id == message.id
                        ? entry.copyWith(
                          content: newContent,
                          editedAt: DateTime.now(),
                        )
                        : entry,
              )
              .toList(),
    );
  }

  Future<void> starMessage(String messageId) async {
    await _repository.starMessage(messageId);
    if (!mounted) return;
    state = state.copyWith(
      starredMessageIds: {...state.starredMessageIds, messageId},
    );
    ref.invalidate(starredMessagesProvider);
  }

  Future<void> unstarMessage(String messageId) async {
    await _repository.unstarMessage(messageId);
    if (!mounted) return;
    state = state.copyWith(
      starredMessageIds:
          state.starredMessageIds.where((id) => id != messageId).toSet(),
    );
    ref.invalidate(starredMessagesProvider);
  }

  Future<void> pinMessage(Message message) async {
    await _repository.pinMessage(
      relationshipId: message.relationshipId,
      messageId: message.id,
    );
    if (!mounted) return;
    final pins = await _repository.getPinnedMessages(message.relationshipId);
    if (!mounted) return;
    state = state.copyWith(pinnedMessages: pins);
  }

  Future<void> unpinMessage(Message message) async {
    await _repository.unpinMessage(
      relationshipId: message.relationshipId,
      messageId: message.id,
    );
    if (!mounted) return;
    final pins = await _repository.getPinnedMessages(message.relationshipId);
    if (!mounted) return;
    state = state.copyWith(pinnedMessages: pins);
  }

  Future<void> reactToMessage(Message message, String emoji) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    String? previousEmoji;
    Message? currentMessage;
    for (final entry in state.messages) {
      if (entry.id == message.id) {
        currentMessage = entry;
        break;
      }
    }
    for (final entry
        in (currentMessage?.reactions ?? message.reactions).entries) {
      if (entry.value.contains(user.id)) {
        previousEmoji = entry.key;
        break;
      }
    }
    state = state.copyWith(
      messages:
          state.messages
              .map(
                (entry) =>
                    entry.id == message.id
                        ? entry.copyWith(
                          reactions: _withReaction(
                            entry.reactions,
                            user.id,
                            emoji,
                          ),
                        )
                        : entry,
              )
              .toList(),
    );

    try {
      await _repository.addReaction(
        relationshipId: message.relationshipId,
        messageId: message.id,
        emoji: emoji,
      );
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          messages:
              state.messages.map((entry) {
                if (entry.id != message.id) return entry;
                final withoutFailedReaction = _withoutReaction(
                  entry.reactions,
                  user.id,
                );
                return entry.copyWith(
                  reactions:
                      previousEmoji == null
                          ? withoutFailedReaction
                          : _withReaction(
                            withoutFailedReaction,
                            user.id,
                            previousEmoji,
                          ),
                );
              }).toList(),
        );
      }
      rethrow;
    }
  }

  Future<void> removeReactionFrom(Message message) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    await _repository.removeReaction(message.id);
    if (!mounted) return;
    state = state.copyWith(
      messages:
          state.messages
              .map(
                (entry) =>
                    entry.id == message.id
                        ? entry.copyWith(
                          reactions: _withoutReaction(entry.reactions, user.id),
                        )
                        : entry,
              )
              .toList(),
    );
  }

  /// Removes [userId] from every emoji bucket first (a reaction is
  /// one-per-user, so switching emoji must clear the old bucket, not just
  /// add to the new one), then adds it to [emoji]'s bucket. Empty buckets
  /// are dropped so a pill never renders with a zero count.
  Map<String, Set<String>> _withReaction(
    Map<String, Set<String>> reactions,
    String userId,
    String emoji,
  ) {
    final next = _withoutReaction(reactions, userId);
    final updated = Map<String, Set<String>>.from(next);
    updated[emoji] = {...(updated[emoji] ?? {}), userId};
    return updated;
  }

  Map<String, Set<String>> _withoutReaction(
    Map<String, Set<String>> reactions,
    String userId,
  ) {
    final updated = <String, Set<String>>{};
    for (final entry in reactions.entries) {
      final without = entry.value.where((id) => id != userId).toSet();
      if (without.isNotEmpty) updated[entry.key] = without;
    }
    return updated;
  }

  /// Best-effort pinned-messages refresh. A failure only means the pinned
  /// banner keeps its last known contents — it must never block the rest of
  /// chat from loading or from processing a realtime event. Returns whether
  /// the pins were read and applied.
  Future<bool> _refreshPinnedMessages() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return false;
    }
    final epoch = _purgeEpoch;
    try {
      final pins = await _bounded(
        _repository.getPinnedMessages(relationshipId),
      );
      // Purged while in flight: these pins belong to the closed state.
      if (!mounted || _purgedSince(epoch)) return false;
      state = state.copyWith(pinnedMessages: pins);
      return true;
    } catch (_) {
      // Ignored by design — see doc comment.
      return false;
    }
  }

  /// Best-effort starred-messages seed. A failure only means Star/Unstar
  /// labels may be momentarily wrong until the next successful call — it
  /// must never block the rest of chat from loading. Unlike pins,
  /// getStarredMessages() is not relationship-scoped (stars are a private,
  /// cross-relationship bookmark list), so this seeds the full set of the
  /// current user's starred message ids, not just this chat's.
  Future<void> _refreshStarredMessageIds() async {
    try {
      final starred = await _repository.getStarredMessages();
      if (!mounted) return;
      state = state.copyWith(
        starredMessageIds: starred.map((m) => m.id).toSet(),
      );
    } catch (_) {
      // Ignored by design — see doc comment.
    }
  }

  /// Sends what is waiting, oldest first (Spec 4.2).
  ///
  /// Stops at the first item ready to insert that is not yet due or that
  /// just failed, so nothing behind it can overtake it. Media preparation
  /// and upload are not queue steps (Design 3, as in WhatsApp): an item
  /// still to be prepared or uploaded is started here outside the pass when
  /// it is due, and never holds the items behind it; once its upload lands
  /// it joins the queue for its insert. Order among items *ready to insert*
  /// is what the two phones compare. [force] ignores backoff deadlines: used by
  /// every "the network is back" trigger (resubscribe, connectivity,
  /// resume, manual retry). After every pass the retry timer is armed for
  /// the queue head, so no item can ever wait without a timer (#3).
  Future<void> flushOutbox({bool force = false}) async {
    if (_retiring) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (!state.conversation.canSend) {
      // Spec 16: the queue stops, and the person is told (M-4). An archived
      // relationship's queue was purged with it: nothing is left to close.
      if (state.conversation.availability !=
          ConversationAvailability.archived) {
        await _failQueuedForInactiveRelationship(user.id);
      }
      return;
    }

    // Serialize flushing: init, the retry timer, realtime, connectivity and
    // manual retries can all call flushOutbox. One in-flight flush per
    // controller; a request made meanwhile runs once more afterwards.
    if (_isFlushing) {
      _flushRequestedWhileBusy = true;
      if (force) _forceRequestedWhileBusy = true;
      return;
    }
    _isFlushing = true;
    final epoch = _purgeEpoch;
    var outboxUnreadable = false;
    try {
      final queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(user.id, relationshipId: relationshipId);
      final now = DateTime.now();

      for (final item in queue) {
        // Purged mid-pass (account change, archive): the rest of this list
        // belongs to a queue that no longer exists, and must not be sent.
        if (!mounted || _purgedSince(epoch)) break;
        if (item.state == PendingSendState.failedPermanent) continue;
        // A concurrent send, a preparation or an upload may already own
        // this item; it does not block the ones behind it.
        if (_inFlightClientIds.contains(item.clientMessageId) ||
            _preparingClientIds.contains(item.clientMessageId) ||
            _uploadingClientIds.contains(item.clientMessageId)) {
          continue;
        }
        final due = item.nextAttemptAt;
        final isDue = force || due == null || !due.isAfter(now);
        // Not ready to insert yet: (re)start its local work or upload off
        // the pass when due, and move on — a slow or failed upload never
        // blocks or fails the items behind it.
        if (item.requiresPreparation) {
          if (isDue) unawaited(_prepareAndAttemptSend(item));
          continue;
        }
        if (_needsUpload(item)) {
          if (isDue) unawaited(_uploadOutsideQueue(item));
          continue;
        }
        if (!isDue) break;

        final acknowledged = await _attemptSend(item);
        // Disposed or purged during the attempt: nothing more may be read
        // or written for this queue from here.
        if (!mounted || _purgedSince(epoch)) break;
        if (!acknowledged) {
          // A transient failure ends the pass: the next item must not go
          // out before this one, and the timer below brings the pass back.
          // A permanent failure steps aside — it will never send, so it
          // must not hold the queue.
          final row = await _readOutboxRow(user.id, item.clientMessageId);
          if (row == null || row.state == PendingSendState.failedPermanent) {
            continue;
          }
          // Its stored key was refused at insert (stale intent): it is not
          // ready to insert any more. The fresh upload runs outside the
          // queue, like any upload, and the items behind it carry on.
          if (_needsUpload(row) && row.nextAttemptAt == null) {
            if (mounted && !_purgedSince(epoch)) {
              unawaited(_uploadOutsideQueue(row));
            }
            continue;
          }
          break;
        }
      }
    } catch (error) {
      ChatLog.e(
        'outbox flush failed rel=${ChatLog.shortId(relationshipId)}',
        error,
      );
      // The queue could not be read or walked: come back on a timer rather
      // than leave whatever waits there with none (M2) — armed below, once
      // per pass, on a backoff.
      outboxUnreadable = true;
    } finally {
      _isFlushing = false;
      if (mounted && !_purgedSince(epoch)) {
        if (!await _settleQueueAfterFlush(user.id)) outboxUnreadable = true;
        if (!outboxUnreadable) {
          _unreadableOutboxPasses = 0;
        } else if (!_purgedSince(epoch)) {
          _retryAfterUnreadableOutbox();
        }
      }
      // If a flush was requested while we were busy, run once more so a newly
      // enqueued item isn't stranded until the next trigger.
      if (_flushRequestedWhileBusy) {
        final again = _forceRequestedWhileBusy;
        _flushRequestedWhileBusy = false;
        _forceRequestedWhileBusy = false;
        if (mounted) unawaited(flushOutbox(force: again));
      }
    }
  }

  /// Arms the retry timer for [due] unless an earlier deadline is already
  /// armed. The old code cancelled and re-armed for the latest failure only,
  /// which stranded an earlier item whose own deadline was further out.
  void _armRetryTimer(DateTime due) {
    if (!mounted) return;
    final current = _retryDeadline;
    if (_retryTimer?.isActive == true &&
        current != null &&
        !due.isBefore(current)) {
      return;
    }
    _retryTimer?.cancel();
    _retryDeadline = due;
    // Never re-arm for "now": a pass that could not attempt the head (an
    // exception before the send, a cache read that failed) must not spin.
    // The floor sits well under the smallest backoff window (1 s).
    const floor = Duration(milliseconds: 500);
    final delay = due.difference(DateTime.now());
    _retryTimer = Timer(delay < floor ? floor : delay, () {
      _retryDeadline = null;
      unawaited(flushOutbox());
    });
  }

  /// How long the queue head waits when it has no deadline of its own after
  /// a pass (the pass could not reach it — an exception before its send).
  static const _headWithoutDeadlineDelay = Duration(seconds: 5);

  /// Consecutive passes that could not read the outbox (a dead local
  /// cache); reset by a pass that could.
  int _unreadableOutboxPasses = 0;

  /// Comes back to an outbox that could not be read on a doubling backoff —
  /// 5, 10, 20, 40, then every 64 s — rather than a fixed 5 s, which flushed
  /// a dead cache every 5 s for as long as the controller lived (M3).
  void _retryAfterUnreadableOutbox() {
    final doublings = min(_unreadableOutboxPasses, 4);
    _unreadableOutboxPasses++;
    final delay = _headWithoutDeadlineDelay * (1 << doublings);
    const cap = Duration(seconds: 64);
    _armRetryTimer(DateTime.now().add(delay > cap ? cap : delay));
  }

  /// After a pass: arm the timer for the FIFO head and make every bubble
  /// that is still waiting say so.
  ///
  /// The head is the first item ready to insert that is neither permanently
  /// failed nor in flight; nothing ready behind it can go before it, so its
  /// deadline is the queue's deadline. Items behind it go on the pass that
  /// sends it. A head with no deadline of its own was not reached by the
  /// pass and goes on a short timer, so nothing can wait at "queued" with no
  /// timer. An item still to be prepared or uploaded is not part of that
  /// order: its own deadline (a failed upload's backoff) also arms the
  /// timer, whichever comes first. Each waiting bubble flips from the
  /// optimistic "sending" to "queued" so the clock is honest while it waits.
  ///
  /// Returns false when the outbox could not be read; the caller arms the
  /// backoff for that ([_retryAfterUnreadableOutbox]).
  Future<bool> _settleQueueAfterFlush(String userId) async {
    final epoch = _purgeEpoch;
    try {
      final queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(userId, relationshipId: relationshipId);
      if (!mounted || _purgedSince(epoch)) return true;
      DateTime? headDue;
      DateTime? notReadyDue;
      var headFound = false;
      final waiting = <String>{};
      for (final item in queue) {
        if (item.state == PendingSendState.failedPermanent) continue;
        if (_inFlightClientIds.contains(item.clientMessageId) ||
            _preparingClientIds.contains(item.clientMessageId) ||
            _uploadingClientIds.contains(item.clientMessageId)) {
          continue;
        }
        waiting.add(item.clientMessageId);
        final due =
            item.nextAttemptAt ?? DateTime.now().add(_headWithoutDeadlineDelay);
        if (item.requiresPreparation || _needsUpload(item)) {
          if (notReadyDue == null || due.isBefore(notReadyDue)) {
            notReadyDue = due;
          }
          continue;
        }
        if (!headFound) {
          headFound = true;
          headDue = due;
        }
      }
      for (final due in [headDue, notReadyDue]) {
        if (due != null) _armRetryTimer(due);
      }
      if (waiting.isEmpty) return true;
      final needsFlip = state.messages.any(
        (m) =>
            waiting.contains(m.clientMessageId) &&
            m.id.startsWith('_local_') &&
            m.status == MessageStatus.sending,
      );
      if (!needsFlip) return true;
      state = state.copyWith(
        isSending: false,
        error: state.error,
        messages:
            state.messages
                .map(
                  (m) =>
                      waiting.contains(m.clientMessageId) &&
                              m.id.startsWith('_local_') &&
                              m.status == MessageStatus.sending
                          ? m.copyWith(status: MessageStatus.queued)
                          : m,
                )
                .toList(),
      );
      return true;
    } catch (error) {
      ChatLog.e('outbox settle failed', error);
      return false;
    }
  }

  /// One attempt at delivering [pending]. Returns true when the server has
  /// the row (fresh insert or 23505 reconcile); false when the attempt
  /// failed and [_handleSendFailure] has recorded it. Never throws.
  ///
  /// If a purge (account change, archive) lands while the attempt is in
  /// flight it writes nothing afterwards — not the outbox row, the history
  /// cache or state — and makes no further network call: the queue it
  /// belonged to no longer exists.
  Future<bool> _attemptSend(PendingSend pending) async {
    final user = ref.read(currentUserProvider);
    // Never write or send a row for a different account (I1).
    if (user == null || user.id != pending.senderId) return false;

    // An upload running outside the queue owns this item until it lands.
    if (_uploadingClientIds.contains(pending.clientMessageId)) return false;
    // Guard against the same logical message being sent twice concurrently
    // (e.g. a manual retry racing a flush). The DB unique constraint is the
    // hard backstop; this avoids the wasted attempt entirely.
    if (!_inFlightClientIds.add(pending.clientMessageId)) return false;

    final epoch = _purgeEpoch;
    var durablePending = pending;
    try {
      try {
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(
              user.id,
              pending.copyWith(state: PendingSendState.sending),
            );
        // Disposed (the provider is gone) or purged: no ref read may follow.
        if (!mounted || _purgedSince(epoch)) return false;

        // Uploads run outside the queue (Design 3), so a row reaching here
        // from the flush is already uploaded and this is the insert alone.
        // Only a send that bypassed the queue (its outbox write failed)
        // still has its file to upload.
        if (_needsUpload(durablePending)) {
          final uploaded = await _uploadMediaPhase(
            user.id,
            durablePending,
            epoch,
            onProgress: (row) => durablePending = row,
          );
          if (uploaded == null) return false;
          durablePending = uploaded;
        }
        final mediaKey = durablePending.uploadedMediaKey;
        final canonical = await _insertMessage(durablePending);
        // The server has it. Purged meanwhile: nothing local is left to
        // acknowledge, and nothing may be written back. Disposed: the row
        // stays queued and the next open's retry reconciles it (23505).
        if (!mounted || _purgedSince(epoch)) return true;

        // A streak's clip row hangs off the message that just landed, using
        // the storage key already resolved for the upload. Additive: every
        // other media type skips this entirely.
        await _attachStreakClipIfNeeded(durablePending, canonical, mediaKey);

        await _acknowledge(user.id, durablePending, canonical, epoch);
        // No conversations-list bump: the inbox channel delivers this very
        // INSERT and refreshes the list in place (a bump rebuilt the list
        // provider and re-ran this controller's header refresh).
        ChatLog.d(
          '[CHAT] send ok rel=${ChatLog.shortId(relationshipId)} '
          'cid=${ChatLog.shortId(pending.clientMessageId)}',
        );
        return true;
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          // Duplicate insert committed nothing (Spec 3.1): the row is
          // already on the server. The reconcile makes its own network
          // calls, so it owns its own failure handling (#4).
          return await _reconcileDuplicate(
            user.id,
            durablePending,
            error,
            epoch,
          );
        }
        if (_isStaleUploadRefusal(error, durablePending)) {
          // Our own committed insert, its answer lost, looks exactly like
          // this: reconcile first; only a row the server does not have is
          // re-uploaded (the flush starts that upload outside the queue).
          return await _reconcileOrReupload(
            user.id,
            durablePending,
            error,
            epoch,
          );
        }
        await _handleSendFailure(
          user.id,
          durablePending,
          ChatError.from(error),
          epoch: epoch,
        );
        return false;
      } on ChatUploadCancelled {
        await _settleCancelledSend(user.id, durablePending, epoch);
        return false;
      } catch (error) {
        await _handleSendFailure(
          user.id,
          durablePending,
          ChatError.from(error),
          epoch: epoch,
        );
        return false;
      }
    } catch (error) {
      // Last line of defence (a failure inside the failure handler itself):
      // nothing may leave a bubble on the clock with no retry armed.
      ChatLog.e(
        'send attempt escaped cid=${ChatLog.shortId(pending.clientMessageId)}',
        error,
      );
      await _parkForRetry(user.id, durablePending, epoch);
      return false;
    } finally {
      _inFlightClientIds.remove(pending.clientMessageId);
    }
  }

  /// Every type that carries a file. A type missing here uploads nothing,
  /// leaves the media key null, and its insert then fails
  /// messages_payload_present with no content either — which is exactly
  /// how streaks broke.
  static bool _isMediaSend(PendingSend pending) {
    final isMediaSend =
        (pending.mediaType == 'image' ||
            pending.mediaType == 'audio' ||
            pending.mediaType == 'video' ||
            pending.mediaType == 'streak') &&
        pending.localMediaPath != null &&
        pending.mediaMimeType != null;
    return isMediaSend;
  }

  /// Whether [pending]'s file still has to be uploaded before its insert —
  /// i.e. it is not yet ready to join the queue order (Design 3).
  static bool _needsUpload(PendingSend pending) =>
      _isMediaSend(pending) && pending.uploadedMediaKey == null;

  /// Uploads whatever [pending] still lacks — its file, and a video's
  /// poster — persisting each storage key as it lands (unless [persist] is
  /// false: no outbox to persist to) and reporting the row so far to
  /// [onProgress], so a later failure records the keys already won (M3).
  /// Returns the updated row, or null once a purge has landed since
  /// [epoch]. Throws when the file's upload fails; a poster failure is
  /// logged and non-fatal.
  Future<PendingSend?> _uploadMediaPhase(
    String userId,
    PendingSend pending,
    int epoch, {
    bool persist = true,
    void Function(PendingSend row)? onProgress,
  }) async {
    final repository = ref.read(chatRepositoryProvider);
    var durablePending = pending;
    if (_needsUpload(pending)) {
      final clientMessageId = pending.clientMessageId;
      // Registered before the intent request, which is raced against it,
      // so a tap on the ring while the slot is being requested settles at
      // once. Throws [ChatUploadCancelled]; every caller settles that
      // quietly.
      final cancelToken = ChatUploadCancelToken();
      _uploadCancelTokens[clientMessageId] = cancelToken;
      // Every attempt — first send, Retry, the retry timer, a reconnect, the
      // drainer, a cold start — sends from byte 0 and shows it.
      _beginUploadAttempt(clientMessageId);
      final ChatMediaUploadIntent intent;
      try {
        intent = await raceUploadCancel(
          _bounded(
            repository.createMediaUploadIntent(
              relationshipId: pending.relationshipId,
              mimeType: pending.mediaMimeType!,
              mediaType: pending.mediaType!,
            ),
          ),
          cancelToken,
        );
        await repository.uploadChatMedia(
          intent: intent,
          localPath: pending.localMediaPath!,
          mimeType: pending.mediaMimeType!,
          cancelToken: cancelToken,
          onProgress:
              (fraction) => _publishUploadProgress(clientMessageId, fraction),
        );
        // Once the bytes are up there is nothing left to stop: the insert
        // goes ahead whatever is tapped now.
      } finally {
        if (identical(_uploadCancelTokens[clientMessageId], cancelToken)) {
          _uploadCancelTokens.remove(clientMessageId);
        }
        // Landed, failed, stalled or cancelled: the attempt is over and so
        // is its ring (and its cancel button).
        _endUploadAttempt(clientMessageId);
      }
      // Disposed or purged while the bytes went up: nothing may be read or
      // written from here (callers treat null as "stop").
      if (!mounted || _purgedSince(epoch)) return null;
      durablePending = durablePending.copyWith(
        uploadedMediaKey: intent.storageKey,
      );
      onProgress?.call(durablePending);
      // The expensive upload is now durable independently of the message
      // insert. If that later write or the process fails, recovery reuses
      // this key instead of creating an orphan and uploading again.
      if (persist) {
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(userId, durablePending);
      }
    }

    // Video-only: a second intent/upload for the thumbnail, through the
    // ordinary image path (media_type: 'image'). Non-fatal on its own
    // failure — a successfully-uploaded 25MB video must not be lost over a
    // missing 40KB poster (see design spec's error table).
    if (pending.mediaType == 'video' &&
        pending.localThumbnailPath != null &&
        pending.thumbnailMimeType != null &&
        durablePending.uploadedThumbnailKey == null) {
      try {
        // Bounded like every other request here (I2): a black-holed poster
        // intent used to hold the row in "sending" — and, through
        // hasSendInFlight, the controller — forever. Not raced with a cancel
        // token: the video's bytes are already up, so there is nothing left
        // for a cancel to stop (its token was retired above) and a timeout
        // demotes to the poster-less send below.
        final thumbIntent = await _bounded(
          repository.createMediaUploadIntent(
            relationshipId: pending.relationshipId,
            mimeType: pending.thumbnailMimeType!,
            mediaType: 'image',
          ),
        );
        await repository.uploadChatMedia(
          intent: thumbIntent,
          localPath: pending.localThumbnailPath!,
          mimeType: pending.thumbnailMimeType!,
        );
        if (!mounted || _purgedSince(epoch)) return null;
        durablePending = durablePending.copyWith(
          uploadedThumbnailKey: thumbIntent.storageKey,
        );
        onProgress?.call(durablePending);
        if (persist) {
          await ref
              .read(chatCacheServiceProvider)
              .putOutbox(userId, durablePending);
        }
        ChatLog.d(
          '[CHAT] video poster uploaded '
          'key=${ChatLog.shortId(thumbIntent.storageKey)}',
        );
      } catch (error) {
        // Non-fatal for the SEND, but fatal for the POSTER: with no
        // thumbnail key the row has nothing for the bubble to resolve, so
        // the video renders as a blank tile forever, on every device and
        // across every reinstall.
        //
        // Deliberately uses ChatLog.diagnostic rather than ChatLog.e: this
        // failure is a server-side rejection (feature flag, MIME allowlist,
        // RLS) whose *reason* is the entire diagnostic value, and e()
        // shapes it away to a length. Shipping it shaped is what made this
        // bug survive three rounds of client-side fixes.
        ChatLog.diagnostic('video thumbnail upload failed', error);
      }
    }
    if (!mounted || _purgedSince(epoch)) return null;
    return durablePending;
  }

  /// Design 3 (WhatsApp): a media item's upload is not a queue step. It runs
  /// here, outside the serialized flush, so a text sent meanwhile goes out
  /// at once. When the upload lands the item is ready to insert and joins
  /// the queue in its enqueue position among items ready to insert. A
  /// failed upload records its backoff on the row ([_handleSendFailure]:
  /// network failures keep the clock, rejections fail it) and the flush
  /// restarts it when due; it never blocks or fails anything behind it.
  Future<void> _uploadOutsideQueue(PendingSend pending) async {
    // Reached after callers' awaits (the enqueue write, a preparation).
    if (!mounted) return;
    final user = ref.read(currentUserProvider);
    // Never upload or write a row for a different account (I1).
    if (user == null || user.id != pending.senderId) return;
    final clientMessageId = pending.clientMessageId;
    if (_inFlightClientIds.contains(clientMessageId) ||
        !_uploadingClientIds.add(clientMessageId)) {
      return;
    }
    final epoch = _purgeEpoch;
    var readyToInsert = false;
    try {
      readyToInsert = await _runUpload(user.id, clientMessageId, epoch);
    } finally {
      _uploadingClientIds.remove(clientMessageId);
    }
    if (readyToInsert && mounted && !_purgedSince(epoch)) {
      await flushOutbox();
    }
  }

  /// The body of [_uploadOutsideQueue]. Returns true when the row is now
  /// ready to insert. Never throws.
  Future<bool> _runUpload(
    String userId,
    String clientMessageId,
    int epoch,
  ) async {
    // The latest durable form of the row: a failure records it, so a key
    // that already landed is never overwritten and re-uploaded (M3).
    PendingSend? latest;
    try {
      try {
        // The caller's copy may be a stale flush snapshot (I3): the row
        // decides. Already uploaded, removed or failed — nothing to upload;
        // whoever uploaded it has queued its insert.
        final current = await _readOutboxRow(userId, clientMessageId);
        if (!mounted ||
            _purgedSince(epoch) ||
            current == null ||
            current.state == PendingSendState.failedPermanent ||
            !_needsUpload(current)) {
          return false;
        }
        latest = current;
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(
              userId,
              current.copyWith(state: PendingSendState.sending),
            );
        if (!mounted || _purgedSince(epoch)) return false;
        final uploaded = await _uploadMediaPhase(
          userId,
          current,
          epoch,
          onProgress: (row) => latest = row,
        );
        if (uploaded == null) return false;
        latest = uploaded;
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(
              userId,
              uploaded.copyWith(
                state: PendingSendState.queued,
                nextAttemptAt: null,
              ),
            );
        return !_purgedSince(epoch);
      } on ChatUploadCancelled {
        final row = latest;
        if (row != null) await _settleCancelledSend(userId, row, epoch);
        return false;
      } catch (error) {
        final row = latest;
        if (row == null) {
          // The row could not even be read: come back on the backoff.
          ChatLog.e('media upload could not read its row', error);
          if (!_purgedSince(epoch)) _retryAfterUnreadableOutbox();
          return false;
        }
        await _handleSendFailure(
          userId,
          row,
          ChatError.from(error),
          epoch: epoch,
        );
        return false;
      }
    } catch (error) {
      // A failure inside the failure handler itself: never leave the
      // bubble on the clock with no retry armed.
      ChatLog.e(
        'media upload escaped cid=${ChatLog.shortId(clientMessageId)}',
        error,
      );
      final row = latest;
      if (row != null) await _parkForRetry(userId, row, epoch);
      return false;
    }
  }

  /// The insert itself: one row, carrying the storage keys [pending] won.
  ///
  /// Bounded ([_bounded]): an insert the network black-holes used to hold
  /// the flush — and with it every trigger, which only found it busy —
  /// until the socket died. A timeout is transient, so the row parks on its
  /// backoff; if the abandoned insert did land, the retry's 23505 reconciles
  /// onto that row (client_message_id is unique), never a second message.
  Future<Message> _insertMessage(PendingSend pending) {
    final insert = ref
        .read(chatRepositoryProvider)
        .sendTextMessage(
          relationshipId: pending.relationshipId,
          senderId: pending.senderId,
          clientMessageId: pending.clientMessageId,
          content: pending.text,
          mediaKey: pending.uploadedMediaKey,
          mediaType: pending.mediaType,
          mediaDurationMs: pending.mediaDurationMs,
          waveform: pending.waveform,
          mediaThumbnailKey: pending.uploadedThumbnailKey,
          mediaWidth: pending.mediaWidth,
          mediaHeight: pending.mediaHeight,
          isViewOnce: pending.isViewOnce,
          streakViewsRemaining: pending.streakViewsRemaining,
          replyToMessageId: pending.replyToMessageId,
          quotedText: pending.quotedText,
        );
    return _bounded(insert);
  }

  /// This relationship's outbox row for [clientMessageId], or null.
  Future<PendingSend?> _readOutboxRow(
    String userId,
    String clientMessageId,
  ) async {
    final queue = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(userId, relationshipId: relationshipId);
    for (final item in queue) {
      if (item.clientMessageId == clientMessageId) return item;
    }
    return null;
  }

  /// The outbox could not be written (a dead local cache, M1). Nothing
  /// durable backs this message, so it gets one honest, direct attempt: on
  /// success it is acknowledged as usual; on any failure the bubble turns
  /// failed — never a clock with no queue row behind it — and Retry
  /// resends it from [_unsavedSends] (back into the queue if the cache has
  /// recovered).
  Future<void> _sendWithoutOutbox(String userId, PendingSend pending) async {
    if (!mounted || pending.senderId != userId) return;
    final clientMessageId = pending.clientMessageId;
    if (!_inFlightClientIds.add(clientMessageId)) return;
    final epoch = _purgeEpoch;
    var latest = pending;
    _unsavedSends[clientMessageId] = latest;
    if (pending.requiresPreparation) {
      // Raw media that was never prepared has nothing to upload yet, and
      // an insert now would land a row without its image: hold it, failed
      // and retryable, until the queue can take it.
      _inFlightClientIds.remove(clientMessageId);
      _holdUnsaved(pending, null);
      return;
    }
    try {
      final uploaded = await _uploadMediaPhase(
        userId,
        pending,
        epoch,
        persist: false,
        onProgress: (row) => latest = row,
      );
      if (uploaded == null) return;
      latest = uploaded;
      Message? canonical;
      var reuploads = 0;
      while (canonical == null) {
        try {
          canonical = await _insertMessage(latest);
        } on PostgrestException catch (error) {
          if (_isStaleUploadRefusal(error, latest) &&
              reuploads < maxMediaReuploads) {
            // Purged or disposed during the insert: nothing may be put back
            // into the unsaved sends, and no intent requested (N2).
            if (!mounted || _purgedSince(epoch)) return;
            // Our own committed insert, its answer lost, is refused the same
            // way: reconcile onto it under the stored key. A failed lookup
            // escapes to the catch below: held, keys kept, no re-upload.
            final own = await _bounded(
              ref
                  .read(chatRepositoryProvider)
                  .findMessageByClientId(
                    senderId: latest.senderId,
                    clientMessageId: clientMessageId,
                  ),
            );
            if (!mounted || _purgedSince(epoch)) return;
            if (own != null) {
              canonical = own;
              continue;
            }
            // Its keys were refused at insert (stale intent): upload again
            // under a fresh intent, then insert again.
            reuploads++;
            ChatLog.diagnostic(
              'stale media key refused at insert; re-uploading '
              'n=$reuploads cid=${ChatLog.shortId(clientMessageId)}',
              error,
            );
            latest = latest.copyWith(
              uploadedMediaKey: null,
              uploadedThumbnailKey: null,
            );
            _unsavedSends[clientMessageId] = latest;
            final again = await _uploadMediaPhase(
              userId,
              latest,
              epoch,
              persist: false,
              onProgress: (row) => latest = row,
            );
            if (again == null) return;
            latest = again;
            continue;
          }
          if (error.code != '23505') rethrow;
          final found = await _bounded(
            ref
                .read(chatRepositoryProvider)
                .findMessageByClientId(
                  senderId: latest.senderId,
                  clientMessageId: clientMessageId,
                ),
          );
          if (found == null) rethrow;
          canonical = found;
        }
      }
      if (!mounted || _purgedSince(epoch)) return;
      await _attachStreakClipIfNeeded(
        latest,
        canonical,
        latest.uploadedMediaKey,
      );
      _unsavedSends.remove(clientMessageId);
      await _acknowledge(
        userId,
        latest,
        canonical,
        epoch,
        fromOutbox: false,
      );
    } on ChatUploadCancelled {
      // Purged meanwhile: the purge cleared the unsaved sends and deleted
      // their media; nothing may be put back.
      if (_purgedSince(epoch)) return;
      // No queue row to park: the in-memory copy is what Retry resends.
      _unsavedSends[clientMessageId] = latest;
      if (!mounted) return;
      _markCancelled(clientMessageId);
    } catch (error) {
      if (_purgedSince(epoch) || !mounted) return;
      final failure = _forThisChat(ChatError.from(error));
      ChatLog.e(
        'direct send failed cat=${failure.category.name} '
        'id=${failure.correlationId} cid=${ChatLog.shortId(clientMessageId)}',
        failure.cause,
      );
      _holdUnsaved(latest, failure);
    } finally {
      _inFlightClientIds.remove(clientMessageId);
    }
  }

  /// A send with no queue row behind it (dead local cache): keep the one
  /// copy Retry can resend from, and turn the bubble failed — removable and
  /// retryable — rather than leave a clock or a spinner nothing will ever
  /// resolve (M1).
  void _holdUnsaved(PendingSend pending, ChatError? failure) {
    _unsavedSends[pending.clientMessageId] = pending;
    if (!mounted) return;
    if (_deliveredOnScreen(pending.clientMessageId)) {
      // It arrived (a catch-up merged it while the answer was lost): Retry
      // has nothing to resend.
      _unsavedSends.remove(pending.clientMessageId);
      state = state.copyWith(isSending: false, error: state.error);
      return;
    }
    state = state.copyWith(
      isSending: false,
      error:
          failure != null && failure.isPermanent
              ? failure
                  .forMedia(pending.mediaType, mimeType: pending.mediaMimeType)
                  .toUserMessage()
              : ChatError(ChatErrorCategory.unknown).toUserMessage(),
      messages:
          state.messages
              .map(
                (message) =>
                    _isLocalBubbleFor(message, pending.clientMessageId)
                        ? message.copyWith(
                          status: MessageStatus.failed,
                          isPreparing: false,
                        )
                        : message,
              )
              .toList(),
    );
  }

  /// The success path shared by a fresh insert and a 23505 reconcile:
  /// outbox row gone, optimistic bubble swapped for the canonical row,
  /// cache written, staged media promoted. Writes nothing once a purge has
  /// landed since [epoch].
  Future<void> _acknowledge(
    String userId,
    PendingSend durablePending,
    Message canonical,
    int epoch, {
    bool fromOutbox = true,
  }) async {
    // Disposed: the row stays queued; the next open's insert answers 23505
    // and the reconcile acknowledges it there.
    if (!mounted || _purgedSince(epoch)) return;
    if (fromOutbox) {
      await ref
          .read(chatCacheServiceProvider)
          .removeOutbox(
            userId,
            durablePending.relationshipId,
            durablePending.clientMessageId,
          );
    }

    if (!mounted || _purgedSince(epoch)) return;
    // Acknowledge immediately while the canonical row still points at the
    // exact local bytes the optimistic row was painting. Cache promotion
    // and staging cleanup happen after this state transition, so neither
    // disk I/O nor a missing signed URL can produce a blank acknowledgement
    // frame or keep the busy overlay spinning after the server replied.
    final resolved = _canonicalWithLocalHandoff(durablePending, canonical);
    state = state.copyWith(
      isSending: false,
      error: null,
      messages: _replaceOptimistic(resolved),
    );
    // Persisted here, not only on the next sync. loadMessages and
    // refreshMessages were the only writers, so a just-sent message lived
    // in memory alone: popping the screen dropped it, the warm-cache
    // restore on return did not have it, and it reappeared seconds later
    // when the server fetch landed.
    final canonicalCacheWrite = ref
        .read(chatCacheServiceProvider)
        .writeMessages(userId, durablePending.relationshipId, state.messages);
    // Enqueue the canonical snapshot first, then promote local bytes. The
    // settlement pass persists its stable cache paths before deleting the
    // staging files, so a process restart cannot restore a dead path.
    unawaited(
      _settleAcknowledgedMedia(
        userId,
        durablePending,
        canonical,
        after: canonicalCacheWrite,
        epoch: epoch,
      ),
    );
  }

  /// Handles a 23505: fetch the canonical row and treat the violation as
  /// success-with-fetch. Every network call in here is its own failure
  /// domain — a throw inside a `catch` clause is not caught by sibling
  /// clauses, and that is exactly how a bubble froze at "sending" while the
  /// partner already had the message (#4). Returns true when acknowledged.
  Future<bool> _reconcileDuplicate(
    String userId,
    PendingSend durablePending,
    PostgrestException duplicate,
    int epoch,
  ) async {
    final Message? canonical;
    try {
      canonical = await _bounded(
        ref
            .read(chatRepositoryProvider)
            .findMessageByClientId(
              senderId: durablePending.senderId,
              clientMessageId: durablePending.clientMessageId,
            ),
      );
    } catch (error) {
      await _handleSendFailure(
        userId,
        durablePending,
        ChatError.from(error),
        epoch: epoch,
      );
      return false;
    }
    if (!mounted || _purgedSince(epoch)) return canonical != null;
    if (canonical == null) {
      // The server says duplicate but will not show us the row (not yet
      // visible). Treat as transient; the next attempt reconciles.
      await _handleSendFailure(
        userId,
        durablePending,
        ChatError.from(duplicate),
        epoch: epoch,
      );
      return false;
    }
    return _settleReconciled(userId, durablePending, canonical, epoch);
  }

  /// The server already has [durablePending]'s row ([canonical]): finish
  /// what the lost answer left undone — a streak's clip, attached under the
  /// row's STORED key, the one the server row carries — and acknowledge.
  Future<bool> _settleReconciled(
    String userId,
    PendingSend durablePending,
    Message canonical,
    int epoch,
  ) async {
    try {
      await _attachStreakClipIfNeeded(
        durablePending,
        canonical,
        durablePending.uploadedMediaKey,
      );
    } catch (attachError) {
      // The message exists but its streak clip still does not. Keep the
      // outbox entry so the next retry can finish that second write.
      await _handleSendFailure(
        userId,
        durablePending,
        ChatError.from(attachError),
        epoch: epoch,
      );
      return false;
    }
    await _acknowledge(userId, durablePending, canonical, epoch);
    return true;
  }

  /// When even the failure handler failed (cache unavailable, for instance):
  /// the bubble goes back to the clock and a short timer brings the queue
  /// back, so the message is never stuck at "sending".
  Future<void> _parkForRetry(
    String userId,
    PendingSend pending,
    int epoch,
  ) async {
    if (!mounted || _purgedSince(epoch) || pending.senderId != userId) return;
    final due = DateTime.now().add(const Duration(seconds: 5));
    try {
      await ref
          .read(chatCacheServiceProvider)
          .putOutbox(
            userId,
            pending.copyWith(state: PendingSendState.queued, nextAttemptAt: due),
          );
    } catch (_) {
      // The in-memory bubble and the timer below still carry the retry.
    }
    if (!mounted || _purgedSince(epoch)) return;
    state = state.copyWith(
      isSending: false,
      messages:
          state.messages
              .map(
                (message) =>
                    _isLocalBubbleFor(message, pending.clientMessageId)
                        ? message.copyWith(status: MessageStatus.queued)
                        : message,
              )
              .toList(),
    );
    _armRetryTimer(due);
  }

  Future<void> _attachStreakClipIfNeeded(
    PendingSend pending,
    Message canonical,
    String? mediaKey,
  ) async {
    if (pending.mediaType != 'streak' || mediaKey == null) return;
    // This runs on both the normal insert and 23505 reconciliation path. A
    // message insert and clip insert are separate server writes; repeating
    // the same idempotent attachment is how recovery completes a crash or
    // network failure between them.
    final isPhoto = pending.mediaMimeType?.startsWith('image/') ?? false;
    // Bounded like the insert; a timeout retries the idempotent attach.
    await _bounded(
      ref
          .read(streakRepositoryProvider)
          .attachClip(
            messageId: canonical.id,
            mediaUrl: mediaKey,
            durationMs: pending.mediaDurationMs ?? 0,
            mediaKind: isPhoto ? StreakClipKind.photo : StreakClipKind.video,
          ),
    );
  }

  Future<String?> _promotePosterToCache(
    PendingSend pending,
    Message canonical, {
    required int epoch,
  }) async {
    if (pending.isViewOnce) return null;
    // Runs after awaits: the chat may have closed (its providers are gone)
    // or been purged since.
    if (!mounted || _purgedSince(epoch)) return null;
    final key = canonical.mediaThumbnailKey;
    final localPath = pending.localThumbnailPath;
    if (key == null || localPath == null) return null;

    // Seed the SAME stable cache entry that signed poster URLs use before
    // deleting staging. This turns optimistic -> canonical into local
    // FileImage -> local FileImage, with no blank provider frame between.
    return ref
        .read(chatPosterPrewarmerProvider)
        .cacheLocalPoster(key: key, localPath: localPath);
  }

  Message _canonicalWithLocalHandoff(PendingSend pending, Message canonical) {
    if (_isPrivateEphemeralSend(pending)) return canonical;
    return canonical.copyWith(
      localMediaPath: pending.localMediaPath,
      localThumbnailPath: pending.localThumbnailPath,
    );
  }

  /// Moves staging files into stable, storage-keyed cache entries after the
  /// canonical bubble has already been published. Staging is deleted only
  /// after a durable local replacement exists; on failure it remains the
  /// current screen's fallback. View-once media and streaks are deliberate
  /// exceptions: privacy requires prompt deletion and no durable promotion.
  Future<void> _settleAcknowledgedMedia(
    String userId,
    PendingSend pending,
    Message canonical, {
    required Future<void> after,
    required int epoch,
  }) async {
    try {
      await after;
    } catch (error) {
      // Local cache is an accelerator, never a prerequisite for a successful
      // server send. Retain staging if its canonical snapshot could not be
      // persisted; a later server refresh still recovers the message.
      ChatLog.e('canonical message cache write failed (non-fatal)', error);
      return;
    }
    if (_isPrivateEphemeralSend(pending) || _purgedSince(epoch)) {
      // Purged: the history this would be written into is gone, and the
      // purge could not clean staging for a row already out of the queue.
      await _deleteStagedMedia(pending.localMediaPath);
      await _deleteStagedMedia(pending.localThumbnailPath);
      return;
    }

    // Closed while the canonical snapshot was written: providers are gone.
    // Staging stays; the cached canonical row still points at it.
    if (!mounted) return;

    String? cachedMediaPath;
    final mediaKey = canonical.mediaKey;
    final localMediaPath = pending.localMediaPath;
    if (mediaKey != null && localMediaPath != null) {
      cachedMediaPath = await ref
          .read(chatPosterPrewarmerProvider)
          .cacheLocalFile(key: mediaKey, localPath: localMediaPath);
    }

    final cachedPosterPath = await _promotePosterToCache(
      pending,
      canonical,
      epoch: epoch,
    );
    if (!mounted ||
        _purgedSince(epoch) ||
        (cachedMediaPath == null && cachedPosterPath == null)) {
      return;
    }
    final index = state.messages.indexWhere(
      (message) => message.id == canonical.id,
    );
    if (index == -1) return;
    final messages = List<Message>.from(state.messages);
    messages[index] = messages[index].copyWith(
      localMediaPath: cachedMediaPath,
      localThumbnailPath: cachedPosterPath,
    );
    state = state.copyWith(messages: messages);
    // This write is the ownership handoff: only once the encrypted message
    // cache points at the promoted files is it safe to remove the staging
    // copies. Await it to prevent a kill/reopen window with a dead local path.
    try {
      await ref
          .read(chatCacheServiceProvider)
          .writeMessages(userId, pending.relationshipId, messages);
    } catch (error) {
      ChatLog.e('settled media cache write failed (non-fatal)', error);
      return;
    }
    if (cachedMediaPath != null) {
      await _deleteStagedMedia(localMediaPath);
    }
    if (canonical.mediaThumbnailKey != null && cachedPosterPath != null) {
      await _deleteStagedMedia(pending.localThumbnailPath);
    }
  }

  bool _isPrivateEphemeralSend(PendingSend pending) =>
      pending.isViewOnce || pending.mediaType == 'streak';

  /// Records a failed attempt: the outbox row's next deadline (or its
  /// permanent failure), the bubble's state and the retry timer. Writes
  /// nothing once a purge has landed since [epoch] (default: now).
  Future<void> _handleSendFailure(
    String userId,
    PendingSend pending,
    ChatError failure, {
    int? epoch,
  }) async {
    final guard = epoch ?? _purgeEpoch;
    // Disposed: `state` and the provider are gone; the row keeps its last
    // durable state and the next open's flush retries it.
    if (!mounted || _purgedSince(guard) || pending.senderId != userId) return;
    final error = _forThisChat(failure);
    final attempts = pending.attempts + 1;
    // Only a server-side failure of unknown shape can exhaust the automatic
    // attempts. A network-class failure (offline, unavailable, rate-limited)
    // never turns a message red on its own: it keeps the clock, at the
    // capped backoff, until the connection returns (#2).
    final countsTowardCap = error.category == ChatErrorCategory.unknown;
    final capped = countsTowardCap && attempts >= _maxAutomaticSendAttempts;
    final permanent = error.isPermanent || capped;

    ChatLog.e(
      'send failed cat=${error.category.name} id=${error.correlationId} '
      'attempt=$attempts permanent=$permanent '
      'cid=${ChatLog.shortId(pending.clientMessageId)}',
      error.cause,
    );

    // ChatLog.e shapes the cause to a length so message bodies cannot leak,
    // which leaves an infrastructure failure — an RLS denial, a CHECK
    // violation, a disabled feature flag, a storage rejection — logged as
    // `<len=34>` and indistinguishable from any other error. The user sees
    // a banner and the console says nothing usable.
    //
    // These two carry no user text: PostgrestException and StorageException
    // describe the REQUEST (keys, constraints, policies), so they are safe
    // to print intact and are usually the entire diagnostic value.
    final cause = error.cause;
    if (cause is PostgrestException || cause is StorageException) {
      ChatLog.diagnostic(
        'send failed cid=${ChatLog.shortId(pending.clientMessageId)} '
        'media=${pending.mediaType ?? 'text'}',
        cause,
      );
    }

    // Bounded exponential backoff with equal jitter (Spec 4.2, 7.2): half the
    // window is fixed, half is randomized so many clients flushing after an
    // outage do not retry in lockstep. Window caps at 2^6 = 64s.
    final windowSeconds = 1 << attempts.clamp(1, 6);
    final backoffMillis =
        (windowSeconds * 500) + _backoffJitter.nextInt(windowSeconds * 500 + 1);

    final updatedPending = pending.copyWith(
      attempts: attempts,
      lastErrorCategory: error.queueCode,
      nextAttemptAt:
          permanent
              ? null
              : DateTime.now().add(Duration(milliseconds: backoffMillis)),
      state:
          permanent
              ? PendingSendState.failedPermanent
              : PendingSendState.queued,
    );

    try {
      await ref.read(chatCacheServiceProvider).putOutbox(userId, updatedPending);
    } catch (cacheError) {
      ChatLog.e('outbox write failed after a send failure', cacheError);
    }
    if (_purgedSince(guard)) return;

    if (!permanent && updatedPending.nextAttemptAt != null) {
      _armRetryTimer(updatedPending.nextAttemptAt!);
    }

    if (!mounted) return;
    if (!permanent && _deliveredOnScreen(pending.clientMessageId)) {
      // The partner already has it: a realtime catch-up merged the row
      // while this attempt's answer was lost. No banner and no clock; the
      // retry armed above reconciles the queue row through 23505.
      state = state.copyWith(isSending: false, error: state.error);
      return;
    }
    state = state.copyWith(
      isSending: false,
      error:
          (capped ? error.afterAttemptCap() : error)
              .forMedia(pending.mediaType, mimeType: pending.mediaMimeType)
              .toUserMessage(),
      messages:
          state.messages
              .map(
                (message) =>
                    _isLocalBubbleFor(message, pending.clientMessageId)
                        ? message.copyWith(
                          status:
                              permanent
                                  ? MessageStatus.failed
                                  : MessageStatus.queued,
                        )
                        : message,
              )
              .toList(),
    );
  }

  /// Whether the insert refused [pending]'s stored keys as stale (see
  /// [ChatError.isStaleMediaUploadRefusal]). Only a row that carries a key
  /// can be helped by a fresh upload.
  static bool _isStaleUploadRefusal(Object error, PendingSend pending) =>
      ChatError.isStaleMediaUploadRefusal(error) &&
      (pending.uploadedMediaKey != null ||
          pending.uploadedThumbnailKey != null);

  /// A stale-key refusal is not always a late insert. One that COMMITTED
  /// while its answer was lost (the insert's bound) used its intent, and the
  /// trigger — BEFORE INSERT, ahead of the client_message_id unique index —
  /// answers the retry with "intent is invalid or expired", never 23505. So
  /// look for our own row first:
  /// - found: reconcile exactly as a 23505, under the STORED key (a streak's
  ///   clip must reference the object the row carries; a fresh key's unused
  ///   intent would have the cleanup delete it);
  /// - not found: the keys really are stale — re-upload ([_requeueForReupload]);
  /// - the lookup fails: retryable as it stands — keys kept, no re-upload
  ///   budget spent, never a blind re-upload.
  Future<bool> _reconcileOrReupload(
    String userId,
    PendingSend pending,
    PostgrestException refusal,
    int epoch,
  ) async {
    final Message? existing;
    try {
      existing = await _bounded(
        ref
            .read(chatRepositoryProvider)
            .findMessageByClientId(
              senderId: pending.senderId,
              clientMessageId: pending.clientMessageId,
            ),
      );
    } catch (error) {
      await _handleSendFailure(
        userId,
        pending,
        ChatError.from(error),
        epoch: epoch,
      );
      return false;
    }
    if (!mounted || _purgedSince(epoch)) return existing != null;
    if (existing != null) {
      ChatLog.d(
        '[CHAT] stale refusal was our own committed insert; reconciled '
        'cid=${ChatLog.shortId(pending.clientMessageId)}',
      );
      return _settleReconciled(userId, pending, existing, epoch);
    }
    await _requeueForReupload(userId, pending, refusal, epoch);
    return false;
  }

  /// The server refused [pending]'s stored keys at insert: the upload intent
  /// (15 minutes) expired before the insert came, or the object is gone.
  /// The same key can never pass, so the row goes back to needing its
  /// upload — keys cleared (a video's poster too: its intent is as old),
  /// due at once — and the caller starts the fresh upload (new intent, byte
  /// 0) outside the queue. Bounded by [maxMediaReuploads] per Retry, so a
  /// server that keeps refusing settles the row as a media rejection rather
  /// than looping; the keys stay cleared so Retry starts fresh too.
  Future<void> _requeueForReupload(
    String userId,
    PendingSend pending,
    Object refusal,
    int epoch,
  ) async {
    if (!mounted || _purgedSince(epoch) || pending.senderId != userId) return;
    final reuploads = pending.mediaReuploads + 1;
    final cleared = pending.copyWith(
      uploadedMediaKey: null,
      uploadedThumbnailKey: null,
      mediaReuploads: reuploads,
    );
    ChatLog.diagnostic(
      'stale media key refused at insert; re-upload n=$reuploads '
      'cid=${ChatLog.shortId(pending.clientMessageId)}',
      refusal,
    );
    if (reuploads > maxMediaReuploads) {
      await _handleSendFailure(
        userId,
        cleared,
        ChatError(
          ChatErrorCategory.mediaRejected,
          cause: refusal,
          mediaType: pending.mediaType,
        ),
        epoch: epoch,
      );
      return;
    }
    try {
      await ref
          .read(chatCacheServiceProvider)
          .putOutbox(
            userId,
            cleared.copyWith(
              state: PendingSendState.queued,
              nextAttemptAt: null,
            ),
          );
    } catch (error) {
      // The row keeps its stale key and its state; the retry timer brings
      // it back to the same refusal, which lands here again.
      ChatLog.e('outbox write failed before a re-upload', error);
      if (!_purgedSince(epoch)) _retryAfterUnreadableOutbox();
    }
  }

  /// The person stopped an upload: the row becomes a failed bubble they can
  /// retry or remove. Parked as failedPermanent (category 'cancelled') so no
  /// flush, outbox drain or restart resumes it — only Retry does, under a
  /// fresh upload intent (the abandoned one is never stored on the row) —
  /// and no banner: they asked for this. Not an attempt: the cap is
  /// untouched. Writes nothing once a purge has landed since [epoch].
  Future<void> _settleCancelledSend(
    String userId,
    PendingSend pending,
    int epoch,
  ) async {
    _lastPublishedUploadProgress.remove(pending.clientMessageId);
    _lastPublishedUploadAt.remove(pending.clientMessageId);
    if (!mounted || _purgedSince(epoch) || pending.senderId != userId) return;
    final cache = ref.read(chatCacheServiceProvider);
    try {
      await cache.putOutbox(
        userId,
        pending.copyWith(
          state: PendingSendState.failedPermanent,
          lastErrorCategory: 'cancelled',
          nextAttemptAt: null,
        ),
      );
    } catch (error) {
      // The row could not be parked: take it out of the queue instead, so
      // nothing resumes a send the person stopped. Retry still works from
      // the in-memory copy. Not once a purge landed during the write: it
      // cleared both, and nothing may be put back.
      ChatLog.e('outbox write failed after a cancel', error);
      if (_purgedSince(epoch)) return;
      _unsavedSends[pending.clientMessageId] = pending;
      try {
        await cache.removeOutbox(
          userId,
          pending.relationshipId,
          pending.clientMessageId,
        );
      } catch (removeError) {
        ChatLog.e('outbox remove failed after a cancel', removeError);
      }
    }
    if (_purgedSince(epoch) || !mounted) return;
    _markCancelled(pending.clientMessageId);
  }

  /// The cancelled bubble turns failed (Retry / Remove), with no banner.
  void _markCancelled(String clientMessageId) {
    if (!mounted) return;
    state = state.copyWith(
      isSending: false,
      error: state.error,
      messages:
          state.messages
              .map(
                (message) =>
                    _isLocalBubbleFor(message, clientMessageId)
                        ? message.copyWith(status: MessageStatus.failed)
                        : message,
              )
              .toList(),
    );
  }

  /// Stops the in-flight upload of [message], if there is one. Once the
  /// bytes are up and only the row insert remains there is nothing to stop:
  /// the send completes.
  void cancelSend(Message message) {
    _uploadCancelTokens[message.clientMessageId]?.cancel();
  }

  /// At most ~50 bubble rebuilds per upload: skip steps under 2% except
  /// the final one.
  @visibleForTesting
  bool debugShouldPublishUploadProgress(
    String clientMessageId,
    double fraction,
  ) {
    if (fraction >= 1.0) {
      // The final value always lands, whatever the throttle says.
      _lastPublishedUploadProgress.remove(clientMessageId);
      _lastPublishedUploadAt.remove(clientMessageId);
      return true;
    }
    final last = _lastPublishedUploadProgress[clientMessageId] ?? -1.0;
    if (fraction - last < 0.02) return false;
    final now = clock.now();
    final at = _lastPublishedUploadAt[clientMessageId];
    if (at != null && now.difference(at) < _uploadProgressMinInterval) {
      return false;
    }
    _lastPublishedUploadProgress[clientMessageId] = fraction;
    _lastPublishedUploadAt[clientMessageId] = now;
    return true;
  }

  void _publishUploadProgress(String clientMessageId, double fraction) {
    if (!debugShouldPublishUploadProgress(clientMessageId, fraction)) return;
    _updateOptimisticMessage(
      clientMessageId,
      (message) => message.copyWith(uploadProgress: fraction),
    );
  }

  /// An upload attempt starts: its ring starts at zero, and a row waiting
  /// on its backoff (queued, the clock) says sending while bytes move —
  /// Wave 1a's honest clock shows only while nothing is uploading. A
  /// non-null progress below 1 is what tells the bubble an upload is under
  /// way, so its centre can offer the cancel. A failure puts the clock back
  /// ([_handleSendFailure]); a flush that cannot insert yet does too
  /// ([_settleQueueAfterFlush]).
  void _beginUploadAttempt(String clientMessageId) {
    _lastPublishedUploadProgress.remove(clientMessageId);
    _lastPublishedUploadAt.remove(clientMessageId);
    if (!mounted) return;
    final needsUpdate = state.messages.any(
      (message) =>
          _isLocalBubbleFor(message, clientMessageId) &&
          (message.uploadProgress != 0 ||
              message.status == MessageStatus.queued),
    );
    if (!needsUpdate) return;
    _updateOptimisticMessage(
      clientMessageId,
      (message) => message.copyWith(
        uploadProgress: 0.0,
        status:
            message.status == MessageStatus.queued
                ? MessageStatus.sending
                : null,
      ),
    );
  }

  /// The attempt is over (landed, failed, stalled, cancelled): no ring, no
  /// cancel button, until the next one starts.
  void _endUploadAttempt(String clientMessageId) {
    _lastPublishedUploadProgress.remove(clientMessageId);
    _lastPublishedUploadAt.remove(clientMessageId);
    if (!mounted) return;
    final hasProgress = state.messages.any(
      (message) =>
          _isLocalBubbleFor(message, clientMessageId) &&
          message.uploadProgress != null,
    );
    if (!hasProgress) return;
    _updateOptimisticMessage(
      clientMessageId,
      (message) => message.copyWith(uploadProgress: null),
    );
  }

  /// A purge (account change, relationship purge) stops every upload in
  /// flight: the bytes would go up under the old session to an object
  /// nothing will reference. Safe because every settle is purge-guarded.
  void _cancelInFlightUploads() {
    final tokens = _uploadCancelTokens.values.toList();
    _uploadCancelTokens.clear();
    _lastPublishedUploadProgress.clear();
    _lastPublishedUploadAt.clear();
    for (final token in tokens) {
      token.cancel();
    }
  }

  /// An RLS insert denial while the relationship has gone read-only is a
  /// pause/ending, not lost access: say so, and do not offer Retry.
  ChatError _forThisChat(ChatError error) {
    if (error.category != ChatErrorCategory.unauthenticated ||
        state.conversation.canSend) {
      return error;
    }
    return ChatError(
      ChatErrorCategory.relationshipInactive,
      correlationId: error.correlationId,
      cause: error.cause,
    );
  }

  /// Spec 16 "relationship ends while queued": the queue stops and the
  /// person is told. The server insert policy requires status = 'active',
  /// so these rows can never send; left as they were they came back as
  /// clock bubbles on every restart with no way to remove them (M-4).
  Future<void> _failQueuedForInactiveRelationship(String userId) async {
    final epoch = _purgeEpoch;
    final List<PendingSend> queue;
    try {
      queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(userId, relationshipId: relationshipId);
    } catch (_) {
      return;
    }
    final stuck =
        queue
            .where((p) => p.state != PendingSendState.failedPermanent)
            .toList();
    if (stuck.isEmpty) return;
    for (final item in stuck) {
      if (_purgedSince(epoch)) return;
      try {
        await ref
            .read(chatCacheServiceProvider)
            .putOutbox(
              userId,
              item.copyWith(
                state: PendingSendState.failedPermanent,
                nextAttemptAt: null,
                lastErrorCategory: ChatErrorCategory.relationshipInactive.name,
              ),
            );
      } catch (error) {
        ChatLog.e('outbox write failed while closing the queue', error);
      }
    }
    if (_purgedSince(epoch)) return;
    _retryTimer?.cancel();
    _retryDeadline = null;
    if (!mounted) return;
    // A row the server already has (its answer was lost, a catch-up merged
    // it) is delivered, not unsent: it is neither counted nor marked.
    final unsent = [
      for (final p in stuck)
        if (!_deliveredOnScreen(p.clientMessageId)) p,
    ];
    if (unsent.isEmpty) {
      state = state.copyWith(isSending: false, error: state.error);
      return;
    }
    final ids = {for (final p in unsent) p.clientMessageId};
    state = state.copyWith(
      isSending: false,
      error:
          unsent.length == 1
              ? "Your unsent message can't be delivered — this chat is "
                  'read-only now. You can remove it.'
              : "Your ${unsent.length} unsent messages can't be delivered — "
                  'this chat is read-only now. You can remove them.',
      messages:
          state.messages
              .map(
                (message) =>
                    ids.contains(message.clientMessageId) &&
                            message.id.startsWith('_local_')
                        ? message.copyWith(
                          status: MessageStatus.failed,
                          isPreparing: false,
                        )
                        : message,
              )
              .toList(),
    );
  }

  Future<void> _markPartnerMessagesDelivered() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    final pendingIds =
        state.messages
            .where(
              (message) =>
                  !message.isMine &&
                  message.deliveredAt == null &&
                  !message.id.startsWith('_local_'),
            )
            .map((message) => message.id)
            .toList();
    if (pendingIds.isEmpty) return;
    await _bounded(ref.read(chatRepositoryProvider).markDelivered(pendingIds));
  }

  Future<void> markAsRead() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    // Read is meaningful only while the user is actually viewing the
    // foregrounded conversation (Spec 6.4). Receipt failures do not block
    // display and are retried idempotently on the next visible sync.
    if (!_isViewActive) return;
    final pending = state.messages
        .where(
          (message) =>
              !message.isMine &&
              message.readAt == null &&
              !_markedReadIds.contains(message.id),
        )
        .map((message) => message.id)
        .toList();
    if (pending.isEmpty) return;
    try {
      await ref
          .read(chatRepositoryProvider)
          .markConversationRead(relationshipId);
      _markedReadIds
        ..addAll(pending)
        ..retainAll(state.messages.map((message) => message.id).toSet());
      // While receipts are off the read changes no messages row, so no
      // realtime event refreshes the conversations list and the unread
      // badge would stay stale (Spec 1a). The client cannot tell on from
      // off here (mark_conversation_read answers the same either way), so
      // ask inside the list's coalescing window: with receipts on, the
      // read's own UPDATE frame lands in the same window and the two are
      // one fetch. In place: no rebuild, no inbox resubscribe. A list
      // nobody has built yet fetches fresh when it is.
      if (ref.exists(conversationsProvider)) {
        ref.read(conversationsProvider.notifier).refreshSoon();
      }
    } catch (_) {
      // Idempotent; a later visible sync retries.
    }
  }

  void markAsReadDebounced() {
    if (!_isViewActive) return;
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(markAsRead());
    });
  }

  /// Newest-first ordering with a stable `id` tie-breaker so two messages that
  /// share a `created_at` keep a deterministic order matching the server's
  /// `(created_at DESC, id DESC)` query order (Spec 6.2, 16).
  /// Newest-first by (sortAt, id), matching the server's own ordering.
  ///
  /// sortAt, not createdAt. The server pages on (sort_at, id) and a game
  /// card is moved to the bottom by bumping sort_at when someone answers
  /// -- but the client re-sorted every merge by createdAt, which put the
  /// card straight back where it was first sent. The card changed sides
  /// correctly and then rendered above its own trail markers, which is
  /// the opposite of the intended reading order.
  ///
  /// For every ordinary message sortAt equals createdAt, so nothing else
  /// moves.
  static int _bySortThenId(Message a, Message b) {
    final byTime = b.presentationSortAt.compareTo(a.presentationSortAt);
    if (byTime != 0) return byTime;
    return b.id.compareTo(a.id);
  }

  /// Keyset "older than": (sortAt, id) below the cursor, the same order the
  /// server pages on.
  static bool isOlderThanCursor(Message m, ChatMessageCursor c) =>
      m.sortAt.isBefore(c.sortAt) ||
      (m.sortAt.isAtSameMomentAs(c.sortAt) && m.id.compareTo(c.id) < 0);

  /// Makes a fetched page authoritative for the span it covered.
  ///
  /// The cache was only ever merged into, never trimmed, so a row deleted
  /// on the server (a wipe before testing, a revoked import, a cascade)
  /// stayed on every phone until sign-out and new messages rendered under
  /// it (#6). The span is: everything at or above the page's oldest row
  /// (a first page), or everything between [before] and that oldest row
  /// (an older page); a page shorter than the limit is [exhaustive] and
  /// owns everything below it as well. Canonical rows in the span that the
  /// page did not return are dropped. `_local_` rows belong to the outbox
  /// and are never touched here. When [knownBefore] is given (the canonical
  /// ids held when the request LEFT), only those may be dropped: a row that
  /// arrived while the request was in flight — a send acknowledged, a
  /// catch-up merged — postdates the server's snapshot and is kept.
  @visibleForTesting
  static List<Message> reconcileWindow(
    List<Message> current,
    List<Message> fresh, {
    ChatMessageCursor? before,
    required bool exhaustive,
    Set<String>? knownBefore,
  }) {
    final freshIds = <String>{for (final m in fresh) m.id};
    // fresh is newest-first; its last row is the oldest the page covered.
    final floor =
        fresh.isEmpty || exhaustive
            ? null
            : ChatMessageCursor(sortAt: fresh.last.sortAt, id: fresh.last.id);

    bool inSpan(Message m) {
      if (before != null && !isOlderThanCursor(m, before)) return false;
      if (floor == null) return true;
      return !isOlderThanCursor(m, floor);
    }

    return [
      for (final m in current)
        if (m.id.startsWith('_local_') ||
            freshIds.contains(m.id) ||
            (knownBefore != null && !knownBefore.contains(m.id)) ||
            !inSpan(m))
          m,
    ];
  }

  /// Keeps only rows that patch something already loaded or fall inside the
  /// loaded span. An unknown row older than everything loaded would render
  /// glued to the bottom with a hole above it; paging back fetches it in
  /// order. With the whole history loaded there is no hole to make.
  List<Message> _onlyLoadedSpan(List<Message> rows) {
    final known = <String>{for (final m in state.messages) m.id};
    Message? oldest;
    for (final m in state.messages) {
      if (m.id.startsWith('_local_')) continue;
      if (oldest == null ||
          isOlderThanCursor(
            m,
            ChatMessageCursor(sortAt: oldest.sortAt, id: oldest.id),
          )) {
        oldest = m;
      }
    }
    // Whole history loaded: there is no hole to make. Only a landed server
    // page can say so — before one, hasMore is just the initial default.
    if (_serverPageLanded && !state.hasMore) return rows;
    // Nothing canonical loaded yet: nothing to patch, and an added row could
    // not be placed; the first page brings it.
    if (oldest == null) return const [];
    final floor = ChatMessageCursor(sortAt: oldest.sortAt, id: oldest.id);
    return [
      for (final m in rows)
        if (known.contains(m.id) || !isOlderThanCursor(m, floor)) m,
    ];
  }

  /// Re-reads the named rows from the server and patches them in place,
  /// wherever they sit in history — an edit, a deletion, a reaction or a
  /// receipt on a message outside the newest page used to be invisible
  /// until the row aged out of the cache (#7). Ids the server does not
  /// return are gone and are removed locally.
  Future<void> refreshMessagesByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final epoch = _purgeEpoch;
    // One request per id chunk, then the reactions read that hydrates them:
    // one bound for all of them failed a big touched set on a slow link (M5).
    final chunks =
        (ids.length + maxMessageIdsPerRequest - 1) ~/ maxMessageIdsPerRequest;
    final fresh = await _bounded(
      ref
          .read(chatRepositoryProvider)
          .getMessagesByIds(relationshipId, ids.toList()),
      requests: chunks + 1,
    );
    if (!mounted || epoch != _purgeEpoch) return;
    final returned = <String>{for (final m in fresh) m.id};
    final gone = <String>{
      for (final id in ids)
        if (!returned.contains(id)) id,
    };
    // Every row named here that went away, loaded or not (see
    // ChatMessageRemovals): by server id, plus the client id where known.
    final removed = <String>{
      for (final m in fresh)
        if (m.isDeleted) ...[m.id, m.clientMessageId],
      ...gone,
      for (final m in state.messages)
        if (gone.contains(m.id)) m.clientMessageId,
    };
    // Read off the loaded rows BEFORE the merge: a tombstone has no keys.
    final removedMedia = _mediaKeysOf(removed);
    var merged = _mergeMessages(_onlyLoadedSpan(fresh));
    if (gone.isNotEmpty) {
      merged = merged.where((m) => !gone.contains(m.id)).toList();
    }
    state = state.copyWith(messages: merged, lastSyncedAt: DateTime.now());
    _persistHistory(user.id);
    ref
        .read(chatMessageRemovalsProvider)
        .announce(removed, mediaKeys: removedMedia);
    _refreshStarredIfAny({...returned, ...gone});
  }

  /// How far behind the newest held server timestamp the changes-since read
  /// starts. Postgres `now()` is transaction START time: a transaction that
  /// began before, but committed after, the newest change this phone saw
  /// carries a smaller `updated_at` and a bare cursor would skip it forever.
  /// Re-reading this window is idempotent (merge by id, incoming wins) and
  /// costs at most a page; a miss would cost a lost edit or receipt.
  static const changesSinceOverlap = Duration(seconds: 30);

  /// At most this many changes-since reads per sync (each returns up to
  /// [ChatRepository.changedSinceMaxPages] pages). A longer backlog resumes
  /// from the persisted cursor on the next sync.
  static const _maxChangesSinceReads = 5;

  /// Bumped whenever this relationship's local state is purged (archive,
  /// account change). Every await-then-write path — first page, older
  /// pages, catch-up, by-id refresh, changes-since sync, cursor seed —
  /// captures it before its request and writes nothing (state, history or
  /// cursor) if a purge landed while the request was in flight. Otherwise
  /// it would write a just-wiped relationship's rows, or the previous
  /// account's, back into the cache.
  int _purgeEpoch = 0;

  /// Whether a purge landed since [epoch] was captured (see [_purgeEpoch]).
  bool _purgedSince(int epoch) => epoch != _purgeEpoch;

  /// Pulls every row whose server `updated_at` is at or after the sync
  /// cursor, less [changesSinceOverlap], and continues while a read was cut
  /// at the repository's page cap. The cursor is server-sourced only (see
  /// [_syncCursor]); while no server page has seeded it this is a no-op —
  /// the first page is the sync.
  ///
  /// Each call starts at the cursor's timestamp less the overlap, with no
  /// id, so late-committing transactions are re-read. Continuations resume
  /// strictly after the exact (updated_at, id) of the last row received:
  /// one transaction (a partner reading 300 unread messages) stamps every
  /// row with the SAME updated_at. Once a read ends still at or before the
  /// cursor this call started from, the next read jumps to that cursor: the
  /// overlap is re-read at most once per call, so a backlog of thousands of
  /// rows on one timestamp cannot eat every call's budget and stall it.
  ///
  /// All reads are applied in memory, then history is written once, then
  /// the cursor is persisted — never ahead of the rows it covers.
  Future<void> syncChangesSinceCursor() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final epoch = _purgeEpoch;
    await _restoreSyncCursor(user.id);
    if (!mounted || epoch != _purgeEpoch) return;
    final startAt = _syncCursor;
    final startId = _syncCursorId;
    if (startAt == null) return;

    final repository = ref.read(chatRepositoryProvider);
    final limit = ref.read(chatConfigProvider).messagePageSize;
    final cap = limit * ChatRepository.changedSinceMaxPages;
    var since = startAt.subtract(changesSinceOverlap);
    String? afterId;
    Message? newest;
    var applied = false;

    // Rows first, cursor second: a cursor persisted ahead of the rows it
    // covers would skip them forever after a crash. A failed write throws
    // and leaves the cursor where it was.
    Future<void> commit() async {
      if (!mounted || epoch != _purgeEpoch) return;
      if (applied) {
        await ref
            .read(chatCacheServiceProvider)
            .writeMessages(user.id, relationshipId, state.messages);
        if (!mounted || epoch != _purgeEpoch) return;
      }
      // Rows filtered out by _onlyLoadedSpan are older than everything
      // loaded; paging back fetches their current state, so the cursor may
      // pass them.
      final reached = newest;
      if (reached != null) {
        await _advanceSyncCursor(
          user.id,
          reached.serverUpdatedAt,
          reached.id,
          epoch,
        );
      }
    }

    for (var read = 0; read < _maxChangesSinceReads; read++) {
      final List<Message> changed;
      try {
        changed = await _bounded(
          repository.getMessagesChangedSince(
            relationshipId,
            since: since,
            afterId: afterId,
            limit: limit,
          ),
          // Its pages, then hydrating the rows.
          requests: ChatRepository.changedSinceMaxPages + 1,
        );
      } catch (error, stackTrace) {
        // A later read failing must not throw away the reads before it, or
        // a persistently failing continuation would block progress forever.
        await commit();
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!mounted || epoch != _purgeEpoch) return;
      if (changed.isEmpty) break;
      // Starred rows the Starred list shows, loaded or not.
      _refreshStarredIfAny(changed.map((m) => m.id));
      // Deleted while this device was away, loaded or not: announced like
      // a realtime delete (stops its note, drops its cached bytes).
      final deletedIds = {
        for (final m in changed)
          if (m.isDeleted) ...[m.id, m.clientMessageId],
      };
      ref
          .read(chatMessageRemovalsProvider)
          .announce(deletedIds, mediaKeys: _mediaKeysOf(deletedIds));
      final applicable = _onlyLoadedSpan(changed);
      if (applicable.isNotEmpty) {
        state = state.copyWith(
          messages: _mergeMessages(applicable),
          lastSyncedAt: DateTime.now(),
        );
        applied = true;
      }
      // The keyset-newest row received: results are (updated_at, id)
      // ordered, but take the max rather than trust the order.
      Message? last;
      for (final m in changed) {
        final t = m.serverUpdatedAt;
        if (t == null) continue;
        if (last == null ||
            _isAfterKeyset(t, m.id, last.serverUpdatedAt!, last.id)) {
          last = m;
        }
      }
      if (last == null) break;
      final lastAt = last.serverUpdatedAt!;
      if (newest == null ||
          _isAfterKeyset(lastAt, last.id, newest.serverUpdatedAt!, newest.id)) {
        newest = last;
      }
      // Shorter than the cap: the repository ran out of changes.
      if (changed.length < cap) break;
      // Cannot advance (defensive; a keyset read always moves forward).
      if (!_isAfterKeyset(lastAt, last.id, since, afterId)) break;
      if (_isAfterKeyset(lastAt, last.id, startAt, startId)) {
        since = lastAt;
        afterId = last.id;
      } else {
        // Still inside the overlap: everything up to the call-start cursor
        // was applied by an earlier call. Skip to it.
        since = startAt;
        afterId = startId;
      }
    }

    await commit();
  }

  /// (at, id) strictly after (otherAt, otherId) in (updated_at, id) order;
  /// a null id sorts before every id at the same timestamp.
  static bool _isAfterKeyset(
    DateTime at,
    String? id,
    DateTime otherAt,
    String? otherId,
  ) {
    if (at.isAfter(otherAt)) return true;
    if (!at.isAtSameMomentAs(otherAt)) return false;
    if (id == null) return false;
    return otherId == null || id.compareTo(otherId) > 0;
  }

  Future<void> _restoreSyncCursor(String userId) async {
    if (_syncCursorRestored) return;
    final epoch = _purgeEpoch;
    final persisted = await ref
        .read(chatCacheServiceProvider)
        .readSyncCursor(userId, relationshipId);
    if (epoch != _purgeEpoch) return;
    _syncCursorRestored = true;
    if (persisted == null) return;
    final current = _syncCursor;
    if (current == null ||
        _isAfterKeyset(persisted.at, persisted.id, current, _syncCursorId)) {
      _syncCursor = persisted.at;
      _syncCursorId = persisted.id;
    }
  }

  /// Moves the cursor forward (never back) to a server (updated_at, id) and
  /// persists it — unless a purge landed since [epoch] was captured.
  Future<void> _advanceSyncCursor(
    String userId,
    DateTime? serverTime,
    String? id,
    int epoch,
  ) async {
    if (serverTime == null || epoch != _purgeEpoch) return;
    final current = _syncCursor;
    if (current != null &&
        !_isAfterKeyset(serverTime, id, current, _syncCursorId)) {
      return;
    }
    _syncCursor = serverTime;
    _syncCursorId = id;
    await ref
        .read(chatCacheServiceProvider)
        .writeSyncCursor(userId, relationshipId, serverTime, id: id);
  }

  /// Seeds the cursor from a first page when nothing has set it yet (a
  /// fresh install, or a cache from before the cursor existed). The page's
  /// rows carry their server `updated_at` (M7), so the seed is the page's
  /// newest server change — never after the moment the page was read, so
  /// the first sync over-reads rather than misses (created_at/sort_at
  /// remain as a fallback for a row read without it). Never ADVANCES an
  /// existing cursor: a first page says nothing about changes to older
  /// cached rows.
  ///
  /// [epoch] is the one the first page captured BEFORE its request: a purge
  /// while that page was in flight must stop the seed too.
  Future<void> _seedSyncCursor(
    String userId,
    List<Message> page,
    int epoch,
  ) async {
    try {
      if (epoch != _purgeEpoch) return;
      await _restoreSyncCursor(userId);
      if (!mounted || epoch != _purgeEpoch || _syncCursor != null) return;
      DateTime? seed;
      for (final m in page) {
        for (final t in <DateTime?>[m.serverUpdatedAt, m.createdAt, m.sortAt]) {
          if (t != null && (seed == null || t.isAfter(seed))) seed = t;
        }
      }
      // No id: a seed is a timestamp lower bound, not a row this phone
      // received from a changes-since read.
      await _advanceSyncCursor(userId, seed, null, epoch);
    } catch (error) {
      ChatLog.e('sync cursor seed failed (non-fatal)', error);
    }
  }

  /// Merges freshly-fetched server rows into the current view.
  ///
  /// On an id collision the INCOMING row wins. Both callers ([loadMessages]
  /// and [_catchUpFromCursor]) pass server-canonical, fully-hydrated rows, so
  /// they carry server-owned state — reactions, edits, deletions — that the
  /// copy already in memory may predate. Letting the existing entry win
  /// instead silently discarded all of it: on cold start `_init` seeds state
  /// from the on-disk cache, so every cached row shadowed its hydrated
  /// counterpart and reactions never survived a restart — then the stripped
  /// list was written straight back to the cache, re-persisting the loss.
  ///
  /// [Message.localMediaPath] is the one field the server cannot know (it
  /// points at the sender's on-device file), so it is carried forward from
  /// the existing entry rather than being nulled out by the incoming row.
  ///
  /// Important finding I3: that carry-forward must NOT happen when the
  /// incoming row shows the message just became ephemeral-expired
  /// (isEphemeralVideoExpired = isViewOnce && viewedAt != null — note this
  /// is independent of media_url/localMediaPath, so a naive carry-forward
  /// would otherwise leave the sender's on-device capture file referenced,
  /// and thus recoverable, even after the server has revoked the video for
  /// everyone). When a message transitions un-expired -> expired during
  /// this merge — whether the "existing" copy is the settled canonical row
  /// (normal case: sender's own earlier view, or a later revocation) or
  /// still the pre-swap OPTIMISTIC `_local_` row (the race where a
  /// realtime refresh's _mergeMessages runs before _attemptSend's own
  /// _replaceOptimistic has swapped the optimistic row out — the
  /// optimistic row is keyed by `_local_...` and canonical rows are keyed
  /// by their server id, so they never collide in `byId` and the
  /// optimistic row's localMediaPath would otherwise survive this method's
  /// final de-dup-by-clientMessageId step completely untouched) — the
  /// local file is deleted (fire-and-forget; deletion failures are already
  /// swallowed by _deleteStagedMedia's own best-effort try/catch).
  /// Client ids of our own rows that were still optimistic when a genuine
  /// arrival landed (see [_mergeMessages]): their canonical copy takes server
  /// order rather than keeping the optimistic device-time slot. Entries leave
  /// when that copy lands.
  final Set<String> _serverOrderAtAck = <String>{};

  List<Message> _mergeMessages(List<Message> incoming) {
    // clientMessageId -> local path of any in-memory row (optimistic or
    // canonical) that is about to be superseded by an incoming row that
    // has become ephemeral-expired, so the eventual de-dup step below
    // never silently drops a still-referenced on-device file.
    final staleLocalPathsByClientId = <String, String>{};

    // Server order wins on the next genuine arrival (see _isGenuineArrival).
    final genuineArrival = _isGenuineArrival(incoming);

    final byId = <String, Message>{};
    final byClientMessageId = <String, Message>{};
    for (final held in state.messages) {
      final message =
          genuineArrival &&
                  !held.isGame &&
                  held.presentationSortAt != held.sortAt
              ? held.copyWith(presentationSortAt: held.sortAt)
              : held;
      byId[message.id] = message;
      byClientMessageId[message.clientMessageId] = message;
    }
    for (final message in incoming) {
      final existing = byId[message.id];
      final existingByClient = byClientMessageId[message.clientMessageId];
      final presentationSource = existing ?? existingByClient;
      // Our own row landing canonical while a genuine arrival is (or was)
      // in view takes server order instead of its optimistic device slot.
      final takesServerOrder =
          existing == null &&
          !message.id.startsWith('_local_') &&
          _serverOrderAtAck.remove(message.clientMessageId);
      final hydrated =
          !message.isGame && presentationSource != null && !takesServerOrder
              ? message.copyWith(
                presentationSortAt: presentationSource.presentationSortAt,
              )
              : message;
      final justExpired =
          message.isEphemeralVideoExpired &&
          existing?.isEphemeralVideoExpired != true;
      if (justExpired) {
        // The incoming canonical row is server-hydrated and never carries a
        // local path (Message.fromRow has no localMediaPath source), so
        // storing `message` as-is already drops it — no copyWith needed
        // (copyWith's `??` semantics mean `localMediaPath: null` would be a
        // no-op if `existing`'s value were passed through some other way).
        final staleLocalPath = existing?.localMediaPath;
        if (staleLocalPath != null) {
          unawaited(_deleteStagedMedia(staleLocalPath));
        }
        byId[message.id] = hydrated;
        // Also cover the still-optimistic-row race described above: the
        // pre-swap `_local_...` row for this same clientMessageId (if any)
        // is untouched by the byId-keyed logic above (different id), so
        // record its local path here and sweep it in the de-dup pass
        // below, which is what actually discards that row.
        for (final candidate in state.messages) {
          if (candidate.id.startsWith('_local_') &&
              candidate.clientMessageId == message.clientMessageId &&
              candidate.localMediaPath != null) {
            staleLocalPathsByClientId[message.clientMessageId] =
                candidate.localMediaPath!;
          }
        }
        continue;
      }
      byId[message.id] =
          existing?.localMediaPath != null && hydrated.localMediaPath == null
              ? hydrated.copyWith(localMediaPath: existing!.localMediaPath)
              : hydrated;
    }

    final merged = byId.values.toList()..sort(_bySortThenId);

    final canonicalByClientId = <String, Message>{};
    for (final message in merged) {
      if (!message.id.startsWith('_local_')) {
        canonicalByClientId[message.clientMessageId] = message;
      }
    }

    return merged.where((message) {
      if (!message.id.startsWith('_local_')) return true;
      final isSuperseded = canonicalByClientId.containsKey(
        message.clientMessageId,
      );
      if (isSuperseded) {
        final stalePath = staleLocalPathsByClientId[message.clientMessageId];
        if (stalePath != null) {
          unawaited(_deleteStagedMedia(stalePath));
        }
      }
      return !isSuperseded;
    }).toList();
  }

  /// Server order wins on the next GENUINE arrival (1a ruling 2, Task 9):
  /// an acked own row keeps its device-time slot (no jump on send), but
  /// once a message we did not already hold lands, every held non-game row
  /// snaps back to its server sortAt, so a clock running ahead cannot keep
  /// our bubble newer than a reply sent after it. Not an arrival: our own
  /// send's canonical row (its clientMessageId is held), an update to a
  /// held row (edit, reaction, receipt), or an older history page (below
  /// everything held — reordering then would move rows with nothing new
  /// to show for it). The screen anchors the row being read, so a snap
  /// while scrolled up does not move it.
  ///
  /// The floor is the oldest SERVER-BACKED held row: an optimistic row's
  /// sortAt is its device stamp, which in a brand-new chat would make a
  /// reply sent after ours look older than everything held. A row still
  /// optimistic at the arrival has no server time to snap to yet: its
  /// canonical copy takes server order when it lands (in this merge, or
  /// at its ack via [_serverOrderAtAck]), so on an arrival this records
  /// those rows there.
  bool _isGenuineArrival(List<Message> incoming) {
    final heldIds = <String>{};
    final heldClientIds = <String>{};
    DateTime? oldestHeld;
    for (final message in state.messages) {
      heldIds.add(message.id);
      heldClientIds.add(message.clientMessageId);
      if (message.id.startsWith('_local_')) continue;
      if (oldestHeld == null || message.sortAt.isBefore(oldestHeld)) {
        oldestHeld = message.sortAt;
      }
    }
    final genuineArrival =
        state.messages.isNotEmpty &&
        incoming.any(
          (message) =>
              !message.id.startsWith('_local_') &&
              !heldIds.contains(message.id) &&
              !heldClientIds.contains(message.clientMessageId) &&
              (oldestHeld == null || !message.sortAt.isBefore(oldestHeld)),
        );
    if (genuineArrival) {
      for (final held in state.messages) {
        if (held.id.startsWith('_local_') && !held.isGame) {
          _serverOrderAtAck.add(held.clientMessageId);
        }
      }
    }
    return genuineArrival;
  }

  List<Message> _replaceOptimistic(Message canonical) {
    final messages = List<Message>.from(state.messages);

    // Replace the optimistic row in place so the just-sent bubble does not jump
    // position when its status ticks sending -> sent (WhatsApp-style stability).
    // The optimistic row used local device time; the canonical carries server
    // time, but re-sorting here would visibly move the user's own message, so
    // we keep its slot. Server order takes over on the next genuine arrival:
    // _mergeMessages then snaps every held row's slot back to its sortAt —
    // and if one already landed while this row was pending, the ack itself
    // takes server order (_serverOrderAtAck).
    final optimisticIndex = messages.indexWhere(
      (message) =>
          message.clientMessageId == canonical.clientMessageId &&
          message.id.startsWith('_local_'),
    );

    if (optimisticIndex != -1) {
      // Drop any stray duplicate of the canonical id, then swap in place.
      messages.removeWhere(
        (message) =>
            !message.id.startsWith('_local_') && message.id == canonical.id,
      );
      final idx = messages.indexWhere(
        (message) =>
            message.clientMessageId == canonical.clientMessageId &&
            message.id.startsWith('_local_'),
      );
      if (_serverOrderAtAck.remove(canonical.clientMessageId)) {
        // A genuine arrival landed while this was pending: server order.
        messages[idx] = canonical;
        messages.sort(_bySortThenId);
        return messages;
      }
      messages[idx] = canonical.copyWith(
        presentationSortAt: messages[idx].presentationSortAt,
      );
      return messages;
    }

    // No optimistic row, and the canonical row is already held (a realtime
    // catch-up merged it before this answer): the incoming row wins, so a
    // stale local state on the held copy (queued, failed) is corrected, in
    // the held row's slot. Receipts only move forward — the held copy may
    // have been read after this answer was built.
    final existingIndex = messages.indexWhere(
      (message) => message.id == canonical.id,
    );
    if (existingIndex != -1) {
      final existing = messages[existingIndex];
      // copyWith keeps a field it is passed null for: the incoming row's own
      // local paths win, else the held copy's (never for an expired
      // view-once video, whose file must not be referenced again).
      var resolved = canonical.copyWith(
        presentationSortAt: existing.presentationSortAt,
        localMediaPath:
            canonical.isEphemeralVideoExpired ? null : existing.localMediaPath,
        localThumbnailPath: existing.localThumbnailPath,
      );
      if (canonical.localMediaPath != null ||
          canonical.localThumbnailPath != null) {
        resolved = resolved.copyWith(
          localMediaPath: canonical.localMediaPath,
          localThumbnailPath: canonical.localThumbnailPath,
        );
      }
      final heldIsFurther =
          (existing.readAt != null && canonical.readAt == null) ||
          (existing.deliveredAt != null && canonical.deliveredAt == null);
      if (heldIsFurther && canonical.isMine) {
        resolved = resolved.copyWith(
          deliveredAt: existing.deliveredAt,
          readAt: existing.readAt,
          status:
              (existing.readAt ?? canonical.readAt) != null
                  ? MessageStatus.read
                  : MessageStatus.delivered,
        );
      }
      messages[existingIndex] = resolved;
      return messages;
    }

    // No optimistic row (e.g. reconciliation after process death): merge and
    // sort so the recovered row lands in the right place.
    messages.add(canonical);
    messages.sort(_bySortThenId);
    return messages;
  }

  /// The outbox is authoritative for anything still local. A cached
  /// `_local_` row is a snapshot of a bubble at some earlier sync: it may say
  /// "sending" for a message the queue knows has failed (restored that way,
  /// it offered neither retry nor remove), or belong to a message the queue
  /// no longer has at all (sent, then superseded; or removed). A canonical
  /// cached row wins over a restored pending row with the same client id:
  /// the server already has it, and the stale outbox row reconciles through
  /// 23505 on the next flush.
  List<Message> _mergeInitialMessages(
    List<Message> cached,
    List<Message> restoredPending,
  ) {
    final byClientMessageId = <String, Message>{};
    for (final message in cached) {
      if (message.id.startsWith('_local_')) continue;
      byClientMessageId[message.clientMessageId] = message;
    }
    for (final message in restoredPending) {
      byClientMessageId.putIfAbsent(message.clientMessageId, () => message);
    }
    return byClientMessageId.values.toList()..sort(_bySortThenId);
  }

  /// Rebuilds the bubbles of what is still queued. A row whose message is
  /// already canonical in the cache ([acknowledged]) is dropped instead —
  /// the server has it; a failed one would otherwise linger forever (M4).
  /// Except a streak still in play: its clip is a second write the row
  /// still carries, and its 23505 reconcile re-attaches it idempotently. A
  /// permanently failed streak row will never retry, so it is dropped too.
  Future<List<Message>> _restorePendingMessages(
    String userId, {
    Set<String> acknowledged = const {},
  }) async {
    final all = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(userId, relationshipId: relationshipId);
    final queue = <PendingSend>[];
    for (final pending in all) {
      if (acknowledged.contains(pending.clientMessageId) &&
          (pending.mediaType != 'streak' ||
              pending.state == PendingSendState.failedPermanent)) {
        try {
          await ref
              .read(chatCacheServiceProvider)
              .removeOutbox(userId, relationshipId, pending.clientMessageId);
        } catch (error) {
          ChatLog.e('dropping an acknowledged outbox row failed', error);
        }
        continue;
      }
      queue.add(pending);
    }

    return queue.map((pending) {
      return Message.optimistic(
        id: '_local_${pending.clientMessageId}',
        clientMessageId: pending.clientMessageId,
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        content: pending.text,
        createdAt: pending.createdAt,
        mediaType: pending.mediaType,
        localMediaPath: pending.localMediaPath,
        mediaDurationMs: pending.mediaDurationMs,
        waveform: pending.waveform,
        mediaWidth: pending.mediaWidth,
        mediaHeight: pending.mediaHeight,
        isViewOnce: pending.isViewOnce,
        streakViewsRemaining: pending.streakViewsRemaining,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
        isPreparing:
            pending.requiresPreparation &&
            pending.mediaType == 'video' &&
            pending.state != PendingSendState.failedPermanent,
        compressProgress:
            pending.requiresPreparation && pending.mediaType == 'video'
                ? 0
                : null,
        localThumbnailPath: pending.localThumbnailPath,
      ).copyWith(
        status: switch (pending.state) {
          PendingSendState.failedPermanent => MessageStatus.failed,
          PendingSendState.sending => MessageStatus.sending,
          PendingSendState.queued => MessageStatus.queued,
        },
      );
    }).toList();
  }

  /// The queue rows a purge is about to delete, read only to clean up their
  /// staged media. An unreadable queue must never stop the purge or the
  /// state reset after it (a privacy action): the media is left orphaned.
  Future<List<PendingSend>> _outboxForPurge(String userId) async {
    try {
      return await ref
          .read(chatCacheServiceProvider)
          .readOutbox(userId, relationshipId: relationshipId);
    } catch (error) {
      ChatLog.e('outbox unreadable before a purge; purging anyway', error);
      return const [];
    }
  }

  /// The storage keys (media and poster) of the rows named by [ids] (client
  /// or server id) among the loaded messages and [also] — what the image
  /// cache holds them under (I3).
  Set<String> _mediaKeysOf(
    Set<String> ids, [
    Iterable<Message> also = const [],
  ]) {
    if (ids.isEmpty) return const {};
    return {
      for (final m in [...state.messages, ...also])
        if (ids.contains(m.id) || ids.contains(m.clientMessageId)) ...[
          if (m.mediaKey?.isNotEmpty ?? false) m.mediaKey!,
          if (m.mediaThumbnailKey?.isNotEmpty ?? false) m.mediaThumbnailKey!,
        ],
    };
  }

  /// Every photo/poster key this relationship's history names, loaded or
  /// only cached for [userId] — read BEFORE the purge deletes the cached
  /// history. Never throws: an unreadable cache leaves the loaded rows'.
  Future<Set<String>> _mediaKeysForPurge(String userId) async {
    var cached = const <Message>[];
    try {
      cached = await ref
          .read(chatCacheServiceProvider)
          .readMessages(userId, relationshipId)
          .timeout(const Duration(seconds: 3));
    } catch (error) {
      ChatLog.diagnostic('history unreadable before a purge (non-fatal)', error);
    }
    return {
      for (final m in [...state.messages, ...cached]) ...[
        if (m.mediaKey?.isNotEmpty ?? false) m.mediaKey!,
        if (m.mediaThumbnailKey?.isNotEmpty ?? false) m.mediaThumbnailKey!,
      ],
    };
  }

  /// This relationship's voice/video bytes in ChatMediaCache go with its
  /// purged history (#28), and the photos/posters in the image cache under
  /// [imageKeys] (I3). Never throws: a purge is a privacy action and the
  /// steps after it must run.
  Future<void> _purgeCachedMedia(Set<String> imageKeys) async {
    try {
      await ref
          .read(chatMediaCacheProvider)
          .removeForRelationship(relationshipId);
    } catch (error) {
      ChatLog.diagnostic('media cache purge failed (non-fatal)', error);
    }
    try {
      await ref.read(chatImageCacheProvider).removeKeys(imageKeys);
    } catch (error) {
      ChatLog.diagnostic('image cache purge failed (non-fatal)', error);
    }
  }

  Future<void> _purgeRelationshipLocalState() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    // Any sync or seed in flight must not re-persist what is purged here.
    _purgeEpoch++;
    _cancelInFlightUploads();
    // Sends with no queue row (dead cache) hold staged media too: it goes
    // with them, like the queue rows' below.
    final unsaved = _unsavedSends.values.toList();
    _unsavedSends.clear();
    _syncCursor = null;
    _syncCursorId = null;
    // The receive/move ledger goes with the rows. The baseline is dropped
    // too, so nothing that comes back afterwards is announced as new: the
    // archived chat has no "open" to re-seed it from.
    _seenPartnerIds.clear();
    _lastPartnerMessageId = null;
    _gameCardSortAt.clear();
    _hasSeededPartnerBaseline = false;
    final pending = await _outboxForPurge(user.id);
    final imageKeys = await _mediaKeysForPurge(user.id);
    await ref
        .read(chatCacheServiceProvider)
        .purgeRelationship(user.id, relationshipId);
    await _purgeCachedMedia(imageKeys);
    for (final item in [...pending, ...unsaved]) {
      if (!item.requiresPreparation) {
        await _deleteStagedMedia(item.localMediaPath);
      } else {
        // Only a source ChatImagePicker staged; never a user's own file.
        await ChatImagePicker.discard(item.localMediaPath);
      }
      await _deleteStagedMedia(item.localThumbnailPath);
    }
  }

  /// Test-only: whether the receive/move feedback ledger is empty (cleared
  /// on a relationship purge).
  @visibleForTesting
  bool get debugReceiveLedgerIsEmpty =>
      _seenPartnerIds.isEmpty &&
      _lastPartnerMessageId == null &&
      _gameCardSortAt.isEmpty;

  /// Test-only: whether Retry holds an in-memory copy of [clientMessageId]
  /// (a send with no queue row behind it).
  @visibleForTesting
  bool debugHasUnsavedSend(String clientMessageId) =>
      _unsavedSends.containsKey(clientMessageId);

  /// Test-only: holds [pending] as a send with no queue row (dead cache),
  /// the state a cancel's cache-failure fallback leaves.
  @visibleForTesting
  void debugHoldUnsavedSend(PendingSend pending) =>
      _unsavedSends[pending.clientMessageId] = pending;

  @visibleForTesting
  Future<void> debugHandleAccountChange(String previousUserId) =>
      _handleAccountChange(previousUserId);

  /// The header refresh without [_refreshConversationSafely]'s catch, so a
  /// test sees anything it throws.
  @visibleForTesting
  Future<void> debugRefreshConversation() => _refreshConversation();

  /// Test-only seam for constructing a specific in-memory
  /// state.messages precondition (e.g. a settled canonical row that still
  /// carries a localMediaPath, or a not-yet-swapped optimistic `_local_`
  /// row) without driving the full send pipeline, which has its own
  /// cleanup side effects that would mask what _mergeMessages itself is
  /// responsible for. See chat_state_send_ephemeral_video_message_test.dart
  /// (Important finding I3 regression tests).
  @visibleForTesting
  void debugSetMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  /// Test-only: the deadline the retry timer is armed for (null: no timer).
  @visibleForTesting
  DateTime? get debugRetryDeadline =>
      _retryTimer?.isActive == true ? _retryDeadline : null;

  /// Test-only: the conversation as a refresh would set it, without a
  /// network round-trip (e.g. to race a send against a pause).
  @visibleForTesting
  void debugSetConversation(Conversation conversation) {
    state = state.copyWith(conversation: conversation);
  }

  /// Whether this controller waits for a sign-in to be rebuilt (see the
  /// account listener in the constructor).
  bool _awaitingSignIn = false;

  /// Set while an account change replaces this controller (see
  /// [_handleAccountChange]); it sends nothing more.
  bool _retiring = false;

  /// Rebuilds this relationship's controller for the account signed in now:
  /// a fresh open (cache, first page, subscribe) under the new account. A
  /// listening screen or drainer gets the new controller at once; otherwise
  /// the next read builds it. This one is disposed.
  void _reopenForNewAccount() {
    if (!mounted) return;
    _awaitingSignIn = false;
    ref.invalidateSelf();
  }

  /// [reopen] is set by the account listener: after the purge the
  /// controller is rebuilt for whoever is signed in now, or once someone
  /// signs in. The test seam purges in place.
  Future<void> _handleAccountChange(
    String previousUserId, {
    bool reopen = false,
  }) async {
    // The previous account's cache is purged below; a sync or seed in
    // flight for it must not write anything back.
    _purgeEpoch++;
    _cancelInFlightUploads();
    // Being replaced: the new account's queue is sent by the controller
    // built for it (a drainer waking this one meanwhile must not send it
    // from here too).
    if (reopen) _retiring = true;
    // Sends with no queue row (dead cache) hold staged media too: it goes
    // with them, like the queue rows' below.
    final unsaved = _unsavedSends.values.toList();
    _unsavedSends.clear();
    _syncCursor = null;
    _syncCursorId = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    final pending = await _outboxForPurge(previousUserId);
    final imageKeys = await _mediaKeysForPurge(previousUserId);
    await ref
        .read(chatCacheServiceProvider)
        .purgeRelationship(previousUserId, relationshipId);
    await _purgeCachedMedia(imageKeys);
    for (final item in [...pending, ...unsaved]) {
      if (!item.requiresPreparation) {
        await _deleteStagedMedia(item.localMediaPath);
      } else {
        // Only a source ChatImagePicker staged; never a user's own file.
        await ChatImagePicker.discard(item.localMediaPath);
      }
      await _deleteStagedMedia(item.localThumbnailPath);
    }
    if (mounted) {
      state = state.copyWith(
        messages: const [],
        conversation: state.conversation.copyWith(
          availability: ConversationAvailability.archived,
        ),
        error: 'This conversation is no longer available for this account.',
      );
    }
    if (!reopen || !mounted) return;
    if (ref.read(currentUserProvider) == null) {
      _awaitingSignIn = true;
    } else {
      _reopenForNewAccount();
    }
  }

  Future<void> _deleteStagedMedia(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort local privacy cleanup; server cleanup is independent.
    }
  }

  @override
  void dispose() {
    // Clear presence so a later message pushes normally once the user has left.
    // Uses the cached repository (dispose must not read from the container).
    if (_isViewActive) {
      unawaited(_repository.setPresence(null));
    }
    _realtimeSubscription?.cancel();
    // Release the shared Realtime channel + streams for this relationship now
    // that no subscription reads from it, so channels don't accumulate across
    // a session (must run after the subscription cancel above).
    unawaited(_repository.releaseChannel(relationshipId));
    _refreshDebounce?.cancel();
    _touchedRetryTimer?.cancel();
    _readDebounce?.cancel();
    _retryTimer?.cancel();
    _retryDeadline = null;
    // Without this the heartbeat outlives the screen, reporting the user
    // as present in a chat they have closed -- which would both show the
    // partner a false indicator and suppress their push notifications.
    _presenceHeartbeat?.cancel();
    // An evicted controller's upload stops here (N3) instead of burning the
    // link beside the re-upload the next open starts. Its settle is a no-op
    // once unmounted, so the outbox row stays resumable.
    _cancelInFlightUploads();
    super.dispose();
  }
}

/// Outcome of paging toward a jump target
/// ([ChatController.ensureMessageLoaded]).
enum JumpTargetResult {
  /// The target row is in state.messages.
  loaded,

  /// The server has no such visible row, or history was paged past its
  /// position without meeting it.
  notFound,

  /// The lookup or a page fetch failed (offline, timed out): nothing is
  /// known about the target.
  exhausted,

  /// The target exists, but paging hit the page cap before reaching it.
  tooFarBack,

  /// A newer jump, a touch on the list or leaving the screen cancelled this
  /// one ([ChatController.cancelJump]).
  cancelled,
}

class ChatState {
  final Conversation conversation;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSending;
  final bool hasMore;
  final List<Message> messages;
  final String? error;
  final DateTime? lastSyncedAt;

  /// A page of the newest messages has come from the server this visit:
  /// the first page, or a forward catch-up filling the gap after the
  /// newest held row. Until then the list may be only the local cache.
  /// Not set by row refreshes (realtime updates, changes-since), which
  /// touch only rows already held — so a cache plus a refreshed reaction
  /// never reads as "the server's newest messages are here" (#32b).
  final bool firstPageLanded;

  /// The open's own read of the first page did not land it (offline, timed
  /// out): when [firstPageLanded] turns true it came from a later read, and
  /// that page can hold rows sent after the chat opened.
  final bool firstPageLate;
  final Set<String> starredMessageIds;
  final List<Message> pinnedMessages;

  /// The load copy of a failed non-silent first-page load (a cold open or
  /// a Retry). Unlike [error], which the next state write clears by design,
  /// this persists until a first page loads or the person retries: a failed
  /// cold open was otherwise wiped within milliseconds by the header, pins
  /// and stars writes that follow it, and showed no error at all.
  final String? loadFailure;

  /// What the conversation banner shows as its error: a fresh [error]
  /// first, else a first load that has not succeeded yet — but not once the
  /// chat is archived (its own state says why it is empty), and not while
  /// offline with messages waiting, where "N messages queued" is what the
  /// person needs to read.
  String? bannerErrorFor({required bool isOnline}) {
    if (error != null) return error;
    if (conversation.isArchived) return null;
    if (!isOnline && messages.any((m) => m.isMine && m.isQueued)) return null;
    return loadFailure;
  }

  const ChatState({
    required this.conversation,
    required this.isLoading,
    required this.isLoadingMore,
    required this.isSending,
    required this.hasMore,
    required this.messages,
    this.error,
    this.lastSyncedAt,
    this.firstPageLanded = false,
    this.firstPageLate = false,
    this.starredMessageIds = const {},
    this.pinnedMessages = const [],
    this.loadFailure,
  });

  factory ChatState.initial(Conversation conversation) {
    return ChatState(
      conversation: conversation,
      isLoading: true,
      isLoadingMore: false,
      isSending: false,
      hasMore: false,
      messages: const [],
      lastSyncedAt: null,
      starredMessageIds: const {},
      pinnedMessages: const [],
    );
  }

  ChatState copyWith({
    Conversation? conversation,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSending,
    bool? hasMore,
    List<Message>? messages,
    String? error,
    DateTime? lastSyncedAt,
    bool? firstPageLanded,
    bool? firstPageLate,
    Set<String>? starredMessageIds,
    List<Message>? pinnedMessages,
    String? loadFailure,
    bool clearLoadFailure = false,
  }) {
    return ChatState(
      conversation: conversation ?? this.conversation,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSending: isSending ?? this.isSending,
      hasMore: hasMore ?? this.hasMore,
      messages: messages ?? this.messages,
      error: error,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      firstPageLanded: firstPageLanded ?? this.firstPageLanded,
      firstPageLate: firstPageLate ?? this.firstPageLate,
      starredMessageIds: starredMessageIds ?? this.starredMessageIds,
      pinnedMessages: pinnedMessages ?? this.pinnedMessages,
      loadFailure:
          clearLoadFailure ? null : (loadFailure ?? this.loadFailure),
    );
  }
}
