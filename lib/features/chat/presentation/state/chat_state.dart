import 'dart:async';
import 'dart:io';
import 'dart:math';
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
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ref.watch(supabaseChatRepositoryProvider);
});

final conversationsRefreshProvider = StateProvider<int>((ref) => 0);

final chatImageSharingEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.imageSharing,
  );
});

final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  ref.watch(conversationsRefreshProvider);
  final repository = ref.watch(chatRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  try {
    final conversations = await repository.getConversations();
    unawaited(
      ref
          .read(chatCacheServiceProvider)
          .writeConversations(user.id, conversations),
    );
    return conversations;
  } catch (_) {
    return await ref.read(chatCacheServiceProvider).readConversations(user.id);
  }
});

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
    _init();
  }

  final Ref ref;
  final Conversation initialConversation;
  late final ChatRepository _repository;
  StreamSubscription<void>? _realtimeSubscription;
  Timer? _refreshDebounce;
  Timer? _readDebounce;
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
      state = state.copyWith(messages: restoredMessages);
    }

    await _refreshConversation();
    // With a warm cache the user already sees their history, so refresh
    // silently — no loading spinner and no "Syncing" banner flash. Only a
    // cold open (empty cache) shows the initial loading state.
    await loadMessages(silent: hasWarmCache);
    // Seed the baseline after the first load so initial history (warm cache
    // or cold fetch) never triggers the receive haptic; only messages that
    // arrive after this point can be "new" (Task 10).
    _lastPartnerMessageId = state.messages
        .where((m) => !m.isMine && !m.id.startsWith('_local_'))
        .fold<Message?>(
          null,
          (best, m) =>
              best == null || m.createdAt.isAfter(best.createdAt) ? m : best,
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
      ref.read(chatRepositoryProvider).setPresence(active ? relationshipId : null),
    );
    if (active) {
      markAsReadDebounced();
    } else {
      _readDebounce?.cancel();
    }
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
      cursor = ChatMessageCursor(
        createdAt: message.createdAt,
        id: message.id,
      );
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
          createdAt: state.messages.last.createdAt,
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

  Future<void> sendImageMessage({
    required String localPath,
    required String mimeType,
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

    final size = await file.length();
    if (size > 800 * 1024) {
      if (mounted) {
        state = state.copyWith(
          error:
              'That image is too large for chat. Please choose a smaller image.',
        );
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
      mediaMimeType: mimeType,
      mediaType: 'image',
      createdAt: now,
    );
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

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

    await ref
        .read(chatCacheServiceProvider)
        .removeOutbox(user.id, relationshipId, message.clientMessageId);
    await _deleteStagedMedia(message.localMediaPath);

    if (!mounted) return;
    state = state.copyWith(
      messages:
          state.messages
              .where(
                (entry) => entry.clientMessageId != message.clientMessageId,
              )
              .toList(),
    );
  }

  Future<void> deleteMessage(Message message) async {
    await _repository.deleteMessage(message.id);
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages
          .map(
            (entry) => entry.id == message.id
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
      messages: state.messages
          .map(
            (entry) => entry.id == message.id
                ? entry.copyWith(content: newContent, editedAt: DateTime.now())
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
      starredMessageIds: state.starredMessageIds
          .where((id) => id != messageId)
          .toSet(),
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
      if (pending.mediaType == 'image' &&
          pending.localMediaPath != null &&
          pending.mediaMimeType != null) {
        final intent = await repository.createImageUploadIntent(
          relationshipId: pending.relationshipId,
          mimeType: pending.mediaMimeType!,
        );
        await repository.uploadChatImage(
          intent: intent,
          localPath: pending.localMediaPath!,
          mimeType: pending.mediaMimeType!,
        );
        mediaKey = intent.storageKey;
      }
      final canonical = await repository.sendTextMessage(
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        clientMessageId: pending.clientMessageId,
        content: pending.text,
        mediaKey: mediaKey,
        mediaType: pending.mediaType,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      );
      await ref
          .read(chatCacheServiceProvider)
          .removeOutbox(
            user.id,
            pending.relationshipId,
            pending.clientMessageId,
          );
      await _deleteStagedMedia(pending.localMediaPath);

      if (!mounted) return;
      state = state.copyWith(
        isSending: false,
        error: null,
        messages: _replaceOptimistic(canonical),
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
          if (!mounted) return;
          state = state.copyWith(
            isSending: false,
            messages: _replaceOptimistic(canonical),
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

    // Bounded exponential backoff with equal jitter (Spec 4.2, 7.2): half the
    // window is fixed, half is randomized so many clients flushing after an
    // outage do not retry in lockstep. Window caps at 2^6 = 64s.
    final windowSeconds = 1 << attempts.clamp(1, 6);
    final backoffMillis =
        (windowSeconds * 500) +
        _backoffJitter.nextInt(windowSeconds * 500 + 1);

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

  List<Message> _mergeMessages(List<Message> incoming) {
    final byId = <String, Message>{};
    for (final message in [...incoming, ...state.messages]) {
      byId[message.id] = message;
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
      return !canonicalByClientId.containsKey(message.clientMessageId);
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
    }
  }

  @visibleForTesting
  Future<void> debugHandleAccountChange(String previousUserId) =>
      _handleAccountChange(previousUserId);

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
      isLoading: false,
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
