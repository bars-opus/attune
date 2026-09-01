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
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ref.watch(supabaseChatRepositoryProvider);
});

/// Resolves a signed URL for a chat media storage key on demand — used by
/// MessageBubble's image slot when a cached (locally-restored) message
/// renders before ChatController's own hydration pass has re-signed its
/// URL. Keyed on mediaKey (not the message id), so switching conversations
/// or messages with the same key reuses SupabaseChatRepository's own
/// signed-URL cache rather than re-requesting on every rebuild.
final signedMediaUrlProvider = FutureProvider.family<String?, String>((
  ref,
  mediaKey,
) {
  return ref.watch(chatRepositoryProvider).createSignedMediaUrl(mediaKey);
});

/// Warms video posters into the disk cache ahead of their tiles. Kept at
/// app scope (not per-conversation) so its already-attempted set survives
/// navigating between chats.
final chatPosterPrewarmerProvider = Provider<ChatPosterPrewarmer>((ref) {
  return ChatPosterPrewarmer(repository: ref.watch(chatRepositoryProvider));
});

final conversationsRefreshProvider = StateProvider<int>((ref) => 0);

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

  @override
  Future<List<Conversation>> build() async {
    ref.watch(conversationsRefreshProvider);
    final repository = ref.watch(chatRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    if (user == null) return const [];

    final cache = ref.read(chatCacheServiceProvider);

    if (!_servedCache) {
      _servedCache = true;
      final cached = await cache.readConversations(user.id);
      if (cached.isNotEmpty) {
        _refreshInBackground(repository, cache, user.id);
        return cached;
      }
    }

    try {
      final conversations = await repository.getConversations();
      unawaited(cache.writeConversations(user.id, conversations));
      return conversations;
    } catch (_) {
      return await cache.readConversations(user.id);
    }
  }

  /// Fetches behind an already-painted cached list. Never surfaces an
  /// AsyncLoading (that would flash the cache away) and swallows failure —
  /// the user keeps reading the cached list until a later refresh succeeds.
  Future<void> _refreshInBackground(
    ChatRepository repository,
    ChatCacheService cache,
    String userId,
  ) async {
    try {
      final conversations = await repository.getConversations();
      state = AsyncData(conversations);
      unawaited(cache.writeConversations(userId, conversations));
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
      final keepAlive = ref.read(chatConfigProvider).controllerKeepAlive;
      Timer? evictionTimer;

      ref.onCancel(() => evictionTimer = Timer(keepAlive, link.close));
      ref.onResume(() => evictionTimer?.cancel());
      ref.onDispose(() => evictionTimer?.cancel());

      return ChatController(ref, conversation);
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
  static final _backoffJitter = Random();
  ChatController(this.ref, this.initialConversation)
    : super(ChatState.initial(initialConversation)) {
    // Cache the repository so dispose-time cleanup never reads a provider from
    // an already-disposed container.
    _repository = ref.read(chatRepositoryProvider);
    ref.listen(currentUserProvider, (previous, next) {
      if (previous?.id != null && previous?.id != next?.id) {
        unawaited(_handleAccountChange(previous!.id));
      }
    });
    // Chat identity (name/photo) is edited elsewhere — the identity sheet
    // on PulseTab — and signals the change by bumping this counter. The
    // header reads state.conversation, which otherwise only refreshes on
    // _init or a realtime event, so an avatar/name edit didn't show here
    // until the screen was left and re-entered.
    ref.listen(conversationsRefreshProvider, (previous, next) {
      if (previous != next) unawaited(_refreshConversation());
    });
    _init();
  }

  final Ref ref;
  final Conversation initialConversation;
  late final ChatRepository _repository;
  StreamSubscription<void>? _realtimeSubscription;
  Timer? _refreshDebounce;
  Timer? _readDebounce;
  Timer? _presenceHeartbeat;
  Timer? _retryTimer;

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

  /// Serializes outbox flushing so overlapping triggers cannot double-send the
  /// same queued item. [_inFlightClientIds] tracks items currently being sent
  /// (including single-message sends) so a concurrent flush skips them.
  bool _isFlushing = false;
  bool _flushRequestedWhileBusy = false;
  final Set<String> _inFlightClientIds = {};

  String get relationshipId => state.conversation.relationshipId;

  Future<void> _init() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final cached = await ref
        .read(chatCacheServiceProvider)
        .readMessages(user.id, relationshipId);
    final restoredPending = await _restorePendingMessages(user.id);
    final restoredMessages = _mergeInitialMessages(cached, restoredPending);
    final hasWarmCache = restoredMessages.isNotEmpty;
    if (hasWarmCache && mounted) {
      // Cache-manager metadata is asynchronous. Discover local poster paths
      // before these rows become paintable so video tiles can start with a
      // FileImage instead of necessarily showing one placeholder frame.
      await ref
          .read(chatPosterPrewarmerProvider)
          .discoverCached(restoredMessages);
      if (!mounted) return;
      state = state.copyWith(messages: restoredMessages);
      // Start fetching posters the moment history is on screen, rather than
      // when each tile mounts a frame or two later. The cached rows carry
      // mediaThumbnailKey, which is all the prewarmer needs, so this is the
      // earliest possible point — and it is the one that matters on restart.
      unawaited(_prewarmPosters(restoredMessages));
    }

    await _refreshConversation();
    // With a warm cache the user already sees their history, so refresh
    // silently — no loading spinner and no "Syncing" banner flash. Only a
    // cold open (empty cache) shows the initial loading state.
    await loadMessages(silent: hasWarmCache);
    // Seed the baseline after the first load so initial history (warm cache
    // or cold fetch) never triggers the receive haptic; only messages that
    // arrive after this point can be "new" (Task 10).
    _lastPartnerMessageId =
        state.messages
            .where((m) => !m.isMine && !m.id.startsWith('_local_'))
            .fold<Message?>(
              null,
              (best, m) =>
                  best == null || m.createdAt.isAfter(best.createdAt)
                      ? m
                      : best,
            )
            ?.id;
    _hasSeededPartnerBaseline = true;
    await _refreshPinnedMessages();
    await _refreshStarredMessageIds();
    _subscribeToRealtime();
    await _markPartnerMessagesDelivered();
    // Read is only recorded once the screen reports the conversation is
    // visible and foregrounded (Spec 6.4); do not mark read here.
    unawaited(flushOutbox());
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
    _presenceHeartbeat = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        if (!_isViewActive) return;
        unawaited(
          ref.read(chatRepositoryProvider).setPresence(relationshipId),
        );
      },
    );
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
  }

  Future<void> _refreshConversation() async {
    final repository = ref.read(chatRepositoryProvider);
    final updated = await repository.getConversation(relationshipId);
    if (!mounted) return;

    if (updated == null) {
      await _purgeRelationshipLocalState();
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
    if (updated.availability == ConversationAvailability.archived) {
      await _purgeRelationshipLocalState();
      state = state.copyWith(messages: const []);
    }
  }

  void _subscribeToRealtime() {
    final repository = ref.read(chatRepositoryProvider);
    ChatLog.d(
      '[CHAT] realtime subscribe rel=${ChatLog.shortId(relationshipId)}',
    );
    _realtimeSubscription = repository
        .watchConversationEvents(relationshipId)
        .listen((_) {
          _refreshDebounce?.cancel();
          _refreshDebounce = Timer(
            ref.read(chatConfigProvider).realtimeRefreshDebounce,
            () async {
              await _refreshConversation();
              // Forward cursor catch-up first so rows beyond the newest visible
              // page are never dropped (Spec 6.1, 6.2), then refresh the
              // visible window for receipt (delivered/read) UPDATEs which do not
              // create new rows.
              await _catchUpFromCursor();
              await loadMessages(silent: true);
              await _markPartnerMessagesDelivered();
              // Pin INSERT/DELETEs share this conversation-events stream
              // (same underlying channel), so the banner stays live when the
              // partner pins or unpins.
              await _refreshPinnedMessages();
              // If the user is actively viewing this conversation, newly
              // arrived partner messages are seen immediately (Spec 6.4).
              if (_isViewActive) markAsReadDebounced();
              ref.read(conversationsRefreshProvider.notifier).state++;
            },
          );
        });
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final repository = ref.read(chatRepositoryProvider);
      final messages = await repository.getMessages(
        relationshipId,
        limit: ref.read(chatConfigProvider).messagePageSize,
      );

      if (!mounted) return;
      // A freshly-fetched row must not become paintable until any poster
      // already stored on this device has been registered for synchronous
      // first-frame lookup. This is local cache metadata only: no signing or
      // network download is awaited here. Without it, the newest video paints
      // one placeholder frame after reopening even though its poster bytes
      // are already on disk.
      await ref.read(chatPosterPrewarmerProvider).discoverCached(messages);
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        messages: _mergeMessages(messages),
        hasMore:
            messages.length >= ref.read(chatConfigProvider).messagePageSize,
        lastSyncedAt: DateTime.now(),
      );
      unawaited(
        ref
            .read(chatCacheServiceProvider)
            .writeMessages(user.id, relationshipId, state.messages),
      );
      unawaited(_prewarmPosters(state.messages));
      _maybeReceiveHaptic();
    } catch (error) {
      final mapped = ChatError.from(error);
      ChatLog.e(
        'load messages failed cat=${mapped.category.name} '
        'id=${mapped.correlationId} rel=${ChatLog.shortId(relationshipId)}',
        mapped.cause,
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        // On a silent (realtime/reconnect) refresh, keep the cached view rather
        // than flashing an error banner over live content.
        error: silent ? state.error : mapped.toUserMessage(),
      );
    }
  }

  /// Fetches every canonical row newer than the newest one we already hold and
  /// merges it in. Used on realtime events and reconnect so a gap larger than
  /// one page is fully restored (Spec 6.1, 6.2, 16). Falls back silently on
  /// error; the subsequent [loadMessages] refresh still runs.
  Future<void> _catchUpFromCursor() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    ChatMessageCursor? cursor;
    for (final message in state.messages) {
      if (message.id.startsWith('_local_')) continue;
      // state.messages is newest-first; the first canonical row is the newest.
      cursor = ChatMessageCursor(sortAt: message.sortAt, id: message.id);
      break;
    }

    try {
      final repository = ref.read(chatRepositoryProvider);
      final fresh = await repository.getMessagesAfter(
        relationshipId,
        after: cursor,
        limit: ref.read(chatConfigProvider).messagePageSize,
      );
      if (!mounted || fresh.isEmpty) return;
      state = state.copyWith(
        messages: _mergeMessages(fresh),
        lastSyncedAt: DateTime.now(),
      );
      unawaited(
        ref
            .read(chatCacheServiceProvider)
            .writeMessages(user.id, relationshipId, state.messages),
      );
      unawaited(_prewarmPosters(state.messages));
      _maybeReceiveHaptic();
    } catch (_) {
      // Non-fatal; loadMessages() refresh follows.
    }
  }

  /// Fires a soft haptic exactly once when a genuinely new partner message
  /// has arrived while the view is active. Content-blind: keys off message
  /// id and [Message.isMine] only, never message content (Task 10). Not fired
  /// for the user's own messages, initial history, or while backgrounded.
  void _maybeReceiveHaptic() {
    final newestPartner = state.messages
        .where((m) => !m.isMine && !m.id.startsWith('_local_'))
        .fold<Message?>(
          null,
          (best, m) =>
              best == null || m.createdAt.isAfter(best.createdAt) ? m : best,
        );
    final id = newestPartner?.id;
    if (id == null) return;
    final isNew = _hasSeededPartnerBaseline && id != _lastPartnerMessageId;
    _lastPartnerMessageId = id;
    if (isNew && _isViewActive) {
      ref.read(hapticsProvider).selection();
      if (ref.read(messageSoundsEnabledProvider)) {
        ref.read(soundServiceProvider).play(ChatSound.receive);
      }
    }
  }

  Future<void> loadMoreMessages() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final repository = ref.read(chatRepositoryProvider);
      final older = await repository.getMessages(
        relationshipId,
        before: ChatMessageCursor(
          sortAt: state.messages.last.sortAt,
          id: state.messages.last.id,
        ),
        limit: ref.read(chatConfigProvider).messagePageSize,
      );

      if (!mounted) return;
      state = state.copyWith(
        isLoadingMore: false,
        messages: _appendOlderMessages(older),
        hasMore: older.length >= ref.read(chatConfigProvider).messagePageSize,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> sendMessage(
    String content, {
    String? replyToMessageId,
    String? quotedText,
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

    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

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

    await _attemptSend(pending);
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
  }) async {
    if (!state.conversation.canSend) return;
    if (!Message.isValidContent(caption, hasMedia: true)) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        state = state.copyWith(error: 'That image is no longer available.');
      }
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();

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

    final PreparedChatImage prepared;
    try {
      prepared = await const ChatImagePreparer().prepare(localPath);
    } on ChatImageRejected catch (rejected) {
      if (!mounted) return;
      state = state.copyWith(
        isSending: false,
        messages:
            state.messages
                .where((entry) => entry.clientMessageId != clientMessageId)
                .toList(),
        error: _imageRejectionMessage(rejected.code),
      );
      return;
    }
    if (!mounted) return;

    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: caption,
      localMediaPath: prepared.file.path,
      mediaMimeType: prepared.mimeType,
      mediaType: 'image',
      createdAt: now,
    );
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

    await _attemptSend(pending);
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
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
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
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

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

    await _attemptSend(pending);
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
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
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
      mediaMimeType: 'video/mp4',
      mediaType: 'streak',
      mediaDurationMs: durationMs,
      streakViewsRemaining: viewsRemaining,
      createdAt: now,
    );
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

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
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );

    await _attemptSend(pending);
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
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }
    final thumbnailFile = File(thumbnailLocalPath);
    if (!await thumbnailFile.exists()) {
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
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

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

    await _attemptSend(pending);
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
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final trimWindowMs = (trimEnd - trimStart).inMilliseconds;

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

    // Updates the still-optimistic bubble in place by clientMessageId —
    // NOT _replaceOptimistic, which is specifically for the one-time
    // optimistic-to-canonical swap after a successful send. This can fire
    // many times (once per progress tick) before that swap ever happens.
    void updateOptimistic(Message Function(Message current) update) {
      if (!mounted) return;
      final messages = state.messages;
      final index = messages.indexWhere(
        (m) => m.id == optimisticId && m.clientMessageId == clientMessageId,
      );
      if (index == -1) return;
      final next = List<Message>.from(messages);
      next[index] = update(next[index]);
      state = state.copyWith(messages: next);
    }

    final PreparedChatVideo prepared;
    try {
      prepared = await const ChatVideoPreparer().prepare(
        localPath: localPath,
        trimStart: trimStart,
        trimEnd: trimEnd,
        onProgress: (value) {
          // video_compress reports 0-100 on its native progress channel;
          // normalize to LinearProgressIndicator's 0-1 contract, mirroring
          // VideoPrepareProgressDialog's own identical calculation.
          updateOptimistic(
            (m) => m.copyWith(compressProgress: (value / 100).clamp(0.0, 1.0)),
          );
        },
        // Fires as soon as the poster frame is extracted — before the
        // transcode, which is the slow part. Painting it on the optimistic
        // row here is what lets the bubble show the real frame immediately
        // with progress drawn over it (WhatsApp's behavior) instead of a
        // blank placeholder for the whole compression.
        onPosterReady: (posterPath) {
          updateOptimistic((m) => m.copyWith(localThumbnailPath: posterPath));
        },
      );
    } on ChatVideoRejected catch (rejected) {
      if (!mounted) return;
      state = state.copyWith(
        isSending: false,
        messages:
            state.messages
                .where((entry) => entry.clientMessageId != clientMessageId)
                .toList(),
        error: _videoRejectionMessage(rejected.code),
      );
      return;
    }
    if (!mounted) return;

    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: prepared.file.path,
      mediaMimeType: prepared.mimeType,
      mediaType: 'video',
      mediaDurationMs: prepared.durationMs,
      localThumbnailPath: prepared.thumbnailFile.path,
      thumbnailMimeType: prepared.thumbnailMimeType,
      mediaWidth: prepared.width,
      mediaHeight: prepared.height,
      createdAt: now,
    );
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

    updateOptimistic(
      (m) => m.copyWith(
        localMediaPath: prepared.file.path,
        // The on-device poster, so the bubble shows a real thumbnail the
        // instant compression finishes rather than a blank tile until the
        // upload + server round-trip produce a signed thumbnail URL.
        localThumbnailPath: prepared.thumbnailFile.path,
        mediaDurationMs: prepared.durationMs,
        mediaWidth: prepared.width,
        mediaHeight: prepared.height,
        isPreparing: false,
      ),
    );

    await _attemptSend(pending);
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
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }
    final thumbnailFile = File(thumbnailLocalPath);
    if (!await thumbnailFile.exists()) {
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
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

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

    await _attemptSend(pending);
  }

  Future<void> retryMessage(Message message) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

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
    if (pending == null) return;

    state = state.copyWith(
      messages:
          state.messages
              .map(
                (entry) =>
                    entry.clientMessageId == message.clientMessageId
                        ? entry.copyWith(status: MessageStatus.sending)
                        : entry,
              )
              .toList(),
    );

    await _attemptSend(
      pending.copyWith(state: PendingSendState.queued, nextAttemptAt: null),
    );
  }

  Future<void> removeFailedMessage(Message message) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Look up the outbox entry before removing it so a video's thumbnail
    // temp file (tracked only on PendingSend, not on Message — see
    // retryMessage's identical lookup above) can also be cleaned up here.
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
    await _deleteStagedMedia(message.localMediaPath);
    await _deleteStagedMedia(pending?.localThumbnailPath);

    if (!mounted) return;
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
    unawaited(
      ref
          .read(chatCacheServiceProvider)
          .writeMessages(user.id, relationshipId, remaining),
    );
  }

  Future<void> deleteMessage(Message message) async {
    await _repository.deleteMessage(message.id);
    if (!mounted) return;
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
  }

  Future<void> editMessage(Message message, String newContent) async {
    await _repository.editMessage(
      messageId: message.id,
      newContent: newContent,
    );
    if (!mounted) return;
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
  }

  Future<void> unstarMessage(String messageId) async {
    await _repository.unstarMessage(messageId);
    if (!mounted) return;
    state = state.copyWith(
      starredMessageIds:
          state.starredMessageIds.where((id) => id != messageId).toSet(),
    );
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

    await _repository.addReaction(
      relationshipId: message.relationshipId,
      messageId: message.id,
      emoji: emoji,
    );
    if (!mounted) return;
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
  /// chat from loading or from processing a realtime event.
  Future<void> _refreshPinnedMessages() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    try {
      final pins = await _repository.getPinnedMessages(relationshipId);
      if (!mounted) return;
      state = state.copyWith(pinnedMessages: pins);
    } catch (_) {
      // Ignored by design — see doc comment.
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

  Future<void> flushOutbox() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (!state.conversation.canSend) return;

    // Serialize flushing: init, the retry timer, and manual retries can all
    // call flushOutbox. Without this guard two runs could pick up the same
    // queued item and send it twice; the DB unique constraint would dedup the
    // second (23505) but the wasted round-trip and double media upload are
    // avoidable. One in-flight flush at a time per controller.
    if (_isFlushing) {
      _flushRequestedWhileBusy = true;
      return;
    }
    _isFlushing = true;
    try {
      final queue = await ref
          .read(chatCacheServiceProvider)
          .readOutbox(user.id, relationshipId: relationshipId);

      for (final item in queue) {
        if (item.state == PendingSendState.failedPermanent) {
          continue;
        }
        // A concurrent single-message send may already be flushing this item.
        if (_inFlightClientIds.contains(item.clientMessageId)) {
          continue;
        }
        final nextAttemptAt = item.nextAttemptAt;
        if (nextAttemptAt != null && nextAttemptAt.isAfter(DateTime.now())) {
          continue;
        }
        await _attemptSend(item);
      }
    } finally {
      _isFlushing = false;
      // If a flush was requested while we were busy, run once more so a newly
      // enqueued item isn't stranded until the next trigger.
      if (_flushRequestedWhileBusy) {
        _flushRequestedWhileBusy = false;
        unawaited(flushOutbox());
      }
    }
  }

  Future<void> _attemptSend(PendingSend pending) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Guard against the same logical message being sent twice concurrently
    // (e.g. a manual retry racing a flush). The DB unique constraint is the
    // hard backstop; this avoids the wasted attempt entirely.
    if (!_inFlightClientIds.add(pending.clientMessageId)) return;

    try {
      await ref
          .read(chatCacheServiceProvider)
          .putOutbox(
            user.id,
            pending.copyWith(state: PendingSendState.sending),
          );

      final repository = ref.read(chatRepositoryProvider);
      String? mediaKey;
      String? mediaThumbnailKey;
      // Every type that carries a file. A type missing here uploads
      // nothing, leaves mediaKey null, and its insert then fails
      // messages_payload_present with no content either — which is
      // exactly how streaks broke.
      final isMediaSend =
          (pending.mediaType == 'image' ||
              pending.mediaType == 'audio' ||
              pending.mediaType == 'video' ||
              pending.mediaType == 'streak') &&
          pending.localMediaPath != null &&
          pending.mediaMimeType != null;
      if (isMediaSend) {
        final intent = await repository.createMediaUploadIntent(
          relationshipId: pending.relationshipId,
          mimeType: pending.mediaMimeType!,
          mediaType: pending.mediaType!,
        );
        await repository.uploadChatMedia(
          intent: intent,
          localPath: pending.localMediaPath!,
          mimeType: pending.mediaMimeType!,
        );
        mediaKey = intent.storageKey;

        // Video-only: a second intent/upload for the thumbnail, through the
        // ordinary image path (media_type: 'image'). Non-fatal on its own
        // failure — a successfully-uploaded 25MB video must not be lost
        // over a missing 40KB poster (see design spec's error table). A
        // failure here is caught locally so it doesn't abort the whole
        // send via the outer try/catch.
        if (pending.mediaType == 'video' &&
            pending.localThumbnailPath != null &&
            pending.thumbnailMimeType != null) {
          try {
            final thumbIntent = await repository.createMediaUploadIntent(
              relationshipId: pending.relationshipId,
              mimeType: pending.thumbnailMimeType!,
              mediaType: 'image',
            );
            await repository.uploadChatMedia(
              intent: thumbIntent,
              localPath: pending.localThumbnailPath!,
              mimeType: pending.thumbnailMimeType!,
            );
            mediaThumbnailKey = thumbIntent.storageKey;
            ChatLog.d(
              '[CHAT] video poster uploaded '
              'key=${ChatLog.shortId(thumbIntent.storageKey)}',
            );
          } catch (error) {
            // Non-fatal for the SEND, but fatal for the POSTER: with no
            // thumbnail key the row has nothing for the bubble to resolve,
            // so the video renders as a blank tile forever, on every device
            // and across every reinstall.
            //
            // Deliberately uses ChatLog.diagnostic rather than ChatLog.e:
            // this failure is a server-side rejection (feature flag, MIME
            // allowlist, RLS) whose *reason* is the entire diagnostic value,
            // and e() shapes it away to a length. Shipping it shaped is what
            // made this bug survive three rounds of client-side fixes.
            ChatLog.diagnostic('video thumbnail upload failed', error);
          }
        }
      }
      final canonical = await repository.sendTextMessage(
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        clientMessageId: pending.clientMessageId,
        content: pending.text,
        mediaKey: mediaKey,
        mediaType: pending.mediaType,
        mediaDurationMs: pending.mediaDurationMs,
        waveform: pending.waveform,
        mediaThumbnailKey: mediaThumbnailKey,
        mediaWidth: pending.mediaWidth,
        mediaHeight: pending.mediaHeight,
        isViewOnce: pending.isViewOnce,
        streakViewsRemaining: pending.streakViewsRemaining,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      );

      // A streak's clip row hangs off the message that just landed, using
      // the storage key already resolved for the upload. Additive: every
      // other media type skips this entirely.
      if (pending.mediaType == 'streak' && mediaKey != null) {
        await ref
            .read(streakRepositoryProvider)
            .attachClip(
              messageId: canonical.id,
              mediaUrl: mediaKey,
              durationMs: pending.mediaDurationMs ?? 0,
            );
      }

      await ref
          .read(chatCacheServiceProvider)
          .removeOutbox(
            user.id,
            pending.relationshipId,
            pending.clientMessageId,
          );
      await _deleteStagedMedia(pending.localMediaPath);
      // Only reclaim the staged poster once the server actually has a copy.
      // If the thumbnail upload failed above, this file is the ONLY poster
      // that exists anywhere — deleting it here is what turned a recoverable
      // upload failure into a permanently blank tile.
      final posterLandedOnServer = canonical.mediaThumbnailKey != null;
      final cachedLocalPosterPath = await _promotePosterToCache(
        pending,
        canonical,
      );
      if (posterLandedOnServer &&
          (cachedLocalPosterPath != null || pending.isViewOnce)) {
        await _deleteStagedMedia(pending.localThumbnailPath);
      }

      if (!mounted) return;
      // Carry the local poster onto the canonical message when the server
      // has none, so the bubble still renders this device's own frame
      // instead of a grey box. Client-only field, so it never round-trips
      // to the DB — the other participant correctly sees no poster, which
      // is the honest reflection of what was actually uploaded.
      final resolved =
          pending.isViewOnce
              ? canonical
              : canonical.copyWith(
                // A successful cache seed provides a durable local file. If
                // either upload or seeding failed, keep staging as this
                // device's fallback instead of deleting its only immediate
                // frame.
                localThumbnailPath:
                    cachedLocalPosterPath ?? pending.localThumbnailPath,
              );
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
      unawaited(
        ref
            .read(chatCacheServiceProvider)
            .writeMessages(user.id, pending.relationshipId, state.messages),
      );
      ChatLog.d(
        '[CHAT] send ok rel=${ChatLog.shortId(relationshipId)} '
        'cid=${ChatLog.shortId(pending.clientMessageId)}',
      );
      ref.read(conversationsRefreshProvider.notifier).state++;
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        // Duplicate insert committed nothing (Spec 3.1); fetch the canonical
        // row and reconcile — treat the violation as success-with-fetch.
        final canonical = await ref
            .read(chatRepositoryProvider)
            .findMessageByClientId(
              senderId: pending.senderId,
              clientMessageId: pending.clientMessageId,
            );
        if (canonical != null) {
          await ref
              .read(chatCacheServiceProvider)
              .removeOutbox(
                user.id,
                pending.relationshipId,
                pending.clientMessageId,
              );
          await _deleteStagedMedia(pending.localMediaPath);
          final cachedLocalPosterPath = await _promotePosterToCache(
            pending,
            canonical,
          );
          if (cachedLocalPosterPath != null || pending.isViewOnce) {
            await _deleteStagedMedia(pending.localThumbnailPath);
          }
          if (!mounted) return;
          final resolved =
              pending.isViewOnce
                  ? canonical
                  : canonical.copyWith(
                    localThumbnailPath:
                        cachedLocalPosterPath ?? pending.localThumbnailPath,
                  );
          state = state.copyWith(
            isSending: false,
            messages: _replaceOptimistic(resolved),
          );
          // Same reason as the success path above: without this, a message
          // recovered from a duplicate insert is in memory only.
          unawaited(
            ref
                .read(chatCacheServiceProvider)
                .writeMessages(user.id, pending.relationshipId, state.messages),
          );
          return;
        }
      }
      await _handleSendFailure(user.id, pending, ChatError.from(error));
    } catch (error) {
      await _handleSendFailure(user.id, pending, ChatError.from(error));
    } finally {
      _inFlightClientIds.remove(pending.clientMessageId);
    }
  }

  Future<String?> _promotePosterToCache(
    PendingSend pending,
    Message canonical,
  ) async {
    if (pending.isViewOnce) return null;
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

  Future<void> _handleSendFailure(
    String userId,
    PendingSend pending,
    ChatError error,
  ) async {
    final attempts = pending.attempts + 1;
    final permanent =
        error.isPermanent || attempts >= _maxAutomaticSendAttempts;

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

    await ref.read(chatCacheServiceProvider).putOutbox(userId, updatedPending);

    _retryTimer?.cancel();
    if (!permanent && updatedPending.nextAttemptAt != null) {
      final delay = updatedPending.nextAttemptAt!.difference(DateTime.now());
      _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
        unawaited(flushOutbox());
      });
    }

    if (!mounted) return;
    state = state.copyWith(
      isSending: false,
      error: error.toUserMessage(),
      messages:
          state.messages
              .map(
                (message) =>
                    message.clientMessageId == pending.clientMessageId
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
    await ref.read(chatRepositoryProvider).markDelivered(pendingIds);
  }

  Future<void> markAsRead() async {
    if (state.conversation.availability == ConversationAvailability.archived) {
      return;
    }
    // Read is meaningful only while the user is actually viewing the
    // foregrounded conversation (Spec 6.4). Receipt failures do not block
    // display and are retried idempotently on the next visible sync.
    if (!_isViewActive) return;
    if (!state.messages.any(
      (message) => !message.isMine && message.readAt == null,
    )) {
      return;
    }
    try {
      await ref
          .read(chatRepositoryProvider)
          .markConversationRead(relationshipId);
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
  static int _byCreatedThenId(Message a, Message b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    if (byTime != 0) return byTime;
    return b.id.compareTo(a.id);
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
  List<Message> _mergeMessages(List<Message> incoming) {
    // clientMessageId -> local path of any in-memory row (optimistic or
    // canonical) that is about to be superseded by an incoming row that
    // has become ephemeral-expired, so the eventual de-dup step below
    // never silently drops a still-referenced on-device file.
    final staleLocalPathsByClientId = <String, String>{};

    final byId = <String, Message>{};
    for (final message in state.messages) {
      byId[message.id] = message;
    }
    for (final message in incoming) {
      final existing = byId[message.id];
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
        byId[message.id] = message;
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
          existing?.localMediaPath != null && message.localMediaPath == null
              ? message.copyWith(localMediaPath: existing!.localMediaPath)
              : message;
    }

    final merged = byId.values.toList()..sort(_byCreatedThenId);

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

  List<Message> _appendOlderMessages(List<Message> older) {
    final existingIds = state.messages.map((message) => message.id).toSet();
    final merged = [
      ...state.messages,
      ...older.where((message) => !existingIds.contains(message.id)),
    ];
    merged.sort(_byCreatedThenId);
    return merged;
  }

  List<Message> _replaceOptimistic(Message canonical) {
    final messages = List<Message>.from(state.messages);

    // Replace the optimistic row in place so the just-sent bubble does not jump
    // position when its status ticks sending -> sent (WhatsApp-style stability).
    // The optimistic row used local device time; the canonical carries server
    // time, but re-sorting here would visibly move the user's own message, so
    // we keep its slot. Cross-user ordering is reconciled on the next realtime
    // merge, which does sort.
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
      messages[idx] = canonical;
      return messages;
    }

    // No optimistic row (e.g. reconciliation after process death): merge and
    // sort so the recovered row lands in the right place.
    if (messages.any((message) => message.id == canonical.id)) {
      return messages;
    }
    messages.add(canonical);
    messages.sort(_byCreatedThenId);
    return messages;
  }

  List<Message> _mergeInitialMessages(
    List<Message> cached,
    List<Message> restoredPending,
  ) {
    final byClientMessageId = <String, Message>{};

    for (final message in [...cached, ...restoredPending]) {
      final existing = byClientMessageId[message.clientMessageId];
      if (existing == null) {
        byClientMessageId[message.clientMessageId] = message;
        continue;
      }
      if (!message.id.startsWith('_local_')) {
        byClientMessageId[message.clientMessageId] = message;
      }
    }

    final merged = byClientMessageId.values.toList()..sort(_byCreatedThenId);
    return merged;
  }

  Future<List<Message>> _restorePendingMessages(String userId) async {
    final queue = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(userId, relationshipId: relationshipId);

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
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      ).copyWith(
        status: switch (pending.state) {
          PendingSendState.failedPermanent => MessageStatus.failed,
          PendingSendState.sending => MessageStatus.sending,
          PendingSendState.queued => MessageStatus.queued,
        },
      );
    }).toList();
  }

  Future<void> _purgeRelationshipLocalState() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final pending = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(user.id, relationshipId: relationshipId);
    await ref
        .read(chatCacheServiceProvider)
        .purgeRelationship(user.id, relationshipId);
    for (final item in pending) {
      await _deleteStagedMedia(item.localMediaPath);
      await _deleteStagedMedia(item.localThumbnailPath);
    }
  }

  @visibleForTesting
  Future<void> debugHandleAccountChange(String previousUserId) =>
      _handleAccountChange(previousUserId);

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

  Future<void> _handleAccountChange(String previousUserId) async {
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    final pending = await ref
        .read(chatCacheServiceProvider)
        .readOutbox(previousUserId, relationshipId: relationshipId);
    await ref
        .read(chatCacheServiceProvider)
        .purgeRelationship(previousUserId, relationshipId);
    for (final item in pending) {
      await _deleteStagedMedia(item.localMediaPath);
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
    _readDebounce?.cancel();
    _retryTimer?.cancel();
    // Without this the heartbeat outlives the screen, reporting the user
    // as present in a chat they have closed -- which would both show the
    // partner a false indicator and suppress their push notifications.
    _presenceHeartbeat?.cancel();
    super.dispose();
  }
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
  final Set<String> starredMessageIds;
  final List<Message> pinnedMessages;

  const ChatState({
    required this.conversation,
    required this.isLoading,
    required this.isLoadingMore,
    required this.isSending,
    required this.hasMore,
    required this.messages,
    this.error,
    this.lastSyncedAt,
    this.starredMessageIds = const {},
    this.pinnedMessages = const [],
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
    Set<String>? starredMessageIds,
    List<Message>? pinnedMessages,
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
      starredMessageIds: starredMessageIds ?? this.starredMessageIds,
      pinnedMessages: pinnedMessages ?? this.pinnedMessages,
    );
  }
}
