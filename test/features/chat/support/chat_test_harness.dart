import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend_base.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend_stub.dart'
    as stub;
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps [child] in the [ScreenUtilInit] that chat widgets require.
///
/// Much of the chat UI sizes itself with flutter_screenutil's `.h`/`.w`
/// extensions. Those read late static fields that only [ScreenUtilInit]
/// assigns, so a widget test that pumps a bare MaterialApp throws
/// `LateInitializationError: Field '_splitScreenMode' has not been
/// initialized` the moment any such widget builds — which is what made a
/// large block of the chat suite fail regardless of the behaviour under
/// test.
///
/// Configured from [ScreenUtilConfig] rather than repeating its values, so
/// sizes computed under test are the sizes the app actually ships —
/// including `splitScreenMode`, the very field whose absence throws.
Widget withScreenUtil(Widget child) => ScreenUtilInit(
  designSize: ScreenUtilConfig.designSize,
  minTextAdapt: ScreenUtilConfig.minTextAdapt,
  splitScreenMode: ScreenUtilConfig.splitScreenMode,
  useInheritedMediaQuery: ScreenUtilConfig.useInheritedMediaQuery,
  fontSizeResolver: ScreenUtilConfig.resolveFontSize,
  builder: (_, __) => child,
  child: child,
);

/// A hand-written, fully controllable fake [ChatRepository] for controller and
/// widget tests. It records calls and lets a test script the outcome of each
/// send (success, duplicate, or a specific failure) without any network.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({required this.currentUserId});

  final String currentUserId;

  /// Canonical rows the fake "server" holds, keyed by canonical id.
  final Map<String, Message> serverMessages = {};

  /// Recorded calls for assertions.
  final List<List<String>> markDeliveredCalls = [];
  final List<String> markReadCalls = [];
  final List<String?> presenceCalls = [];
  int sendCallCount = 0;

  /// When set, the next send throws this instead of succeeding. Cleared after
  /// one use so a retry can succeed.
  Object? nextSendError;

  /// Optional artificial latency on send so tests can observe the optimistic
  /// (sending) window before the server acknowledges.
  Duration sendDelay = Duration.zero;

  /// When true, a send raises a 23505 duplicate and the canonical row is
  /// already present under [duplicateClientMessageId].
  bool simulateDuplicate = false;
  String? duplicateClientMessageId;

  final _events = StreamController<void>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final List<({bool typing})> sentTyping = [];

  /// What [getConversation] returns on refresh. Defaults to an active
  /// conversation; set to a read-only/archived one to test those lifecycles.
  Conversation? conversationOverride;

  /// Value returned by [fetchStreak].
  int streakValue = 0;

  /// Pushes a realtime "something changed" signal to subscribers.
  void emitRealtime() => _events.add(null);

  /// Seeds a canonical row as if another member sent it.
  Message seedIncoming({
    required String id,
    required String relationshipId,
    required String senderId,
    required String content,
    required DateTime createdAt,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    final row = {
      'id': id,
      'relationship_id': relationshipId,
      'sender_id': senderId,
      'client_message_id': 'seed-$id',
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      'delivered_at': deliveredAt?.toUtc().toIso8601String(),
      'read_at': readAt?.toUtc().toIso8601String(),
      'media_url': null,
      'media_type': null,
      'source': 'native',
    };
    final message = Message.fromRow(row, currentUserId: currentUserId);
    serverMessages[id] = message;
    return message;
  }

  @override
  Future<Message> sendTextMessage({
    required String relationshipId,
    required String senderId,
    required String clientMessageId,
    required String content,
    String? mediaKey,
    String? mediaType,
    int? mediaDurationMs,
    List<int>? waveform,
    String? mediaThumbnailKey,
    int? mediaWidth,
    int? mediaHeight,
    String? replyToMessageId,
    String? quotedText,
    bool isViewOnce = false,
    bool isSystemNotice = false,
  }) async {
    sendCallCount++;
    if (sendDelay > Duration.zero) await Future<void>.delayed(sendDelay);

    if (simulateDuplicate) {
      throw const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
    }

    final error = nextSendError;
    if (error != null) {
      nextSendError = null;
      throw error;
    }

    final id = 'srv-$clientMessageId';
    final row = {
      'id': id,
      'relationship_id': relationshipId,
      'sender_id': senderId,
      'client_message_id': clientMessageId,
      'content': content,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'delivered_at': null,
      'read_at': null,
      'media_url': mediaKey,
      'media_type': mediaType,
      'media_duration_ms': mediaDurationMs,
      'media_waveform': waveform,
      'media_thumbnail_url': mediaThumbnailKey,
      'media_width': mediaWidth,
      'media_height': mediaHeight,
      'source': 'native',
      'reply_to_message_id': replyToMessageId,
      'quoted_text': quotedText,
      'is_view_once': isViewOnce,
      'is_system_notice': isSystemNotice,
    };
    final message = Message.fromRow(row, currentUserId: currentUserId);
    serverMessages[id] = message;
    return message;
  }

  @override
  Future<Message?> findMessageByClientId({
    required String senderId,
    required String clientMessageId,
  }) async {
    for (final message in serverMessages.values) {
      if (message.clientMessageId == clientMessageId &&
          message.senderId == senderId) {
        return message;
      }
    }
    if (simulateDuplicate && clientMessageId == duplicateClientMessageId) {
      final id = 'srv-$clientMessageId';
      final row = {
        'id': id,
        'relationship_id': 'rel',
        'sender_id': senderId,
        'client_message_id': clientMessageId,
        'content': 'dup',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'delivered_at': null,
        'read_at': null,
        'media_url': null,
        'media_type': null,
        'source': 'native',
      };
      return Message.fromRow(row, currentUserId: currentUserId);
    }
    return null;
  }

  @override
  Future<List<Message>> getMessages(
    String relationshipId, {
    ChatMessageCursor? before,
    int limit = 50,
  }) async {
    final all =
        serverMessages.values
            .where((m) => m.relationshipId == relationshipId)
            .toList()
          ..sort((a, b) {
            final t = b.createdAt.compareTo(a.createdAt);
            return t != 0 ? t : b.id.compareTo(a.id);
          });
    if (before == null) return all.take(limit).toList();
    return all
        .where((m) => m.createdAt.isBefore(before.createdAt))
        .take(limit)
        .toList();
  }

  @override
  Future<List<Message>> getMessagesAfter(
    String relationshipId, {
    ChatMessageCursor? after,
    int limit = 50,
  }) async {
    final all =
        serverMessages.values
            .where((m) => m.relationshipId == relationshipId)
            .toList()
          ..sort((a, b) {
            final t = a.createdAt.compareTo(b.createdAt);
            return t != 0 ? t : a.id.compareTo(b.id);
          });
    if (after == null) return all.take(limit).toList();
    return all.where((m) => m.createdAt.isAfter(after.createdAt)).toList();
  }

  @override
  Future<void> markDelivered(List<String> messageIds) async {
    markDeliveredCalls.add(messageIds);
  }

  @override
  Future<void> markConversationRead(String relationshipId) async {
    markReadCalls.add(relationshipId);
  }

  @override
  Future<void> setPresence(String? relationshipId) async {
    presenceCalls.add(relationshipId);
  }

  @override
  Stream<void> watchConversationEvents(String relationshipId) => _events.stream;

  @override
  void sendTyping(String relationshipId, {required bool typing}) {
    sentTyping.add((typing: typing));
  }

  @override
  Stream<TypingEvent> watchTyping(String relationshipId) =>
      _typingController.stream;

  /// Test helper: simulate the partner's typing event arriving.
  void emitPartnerTyping(String senderId, bool typing) {
    _typingController.add(TypingEvent(senderId, typing));
  }

  @override
  Future<Conversation?> getConversation(String relationshipId) async {
    // Always hand back a freshly-constructed instance (copyWith, never the
    // caller's own object) — the real SupabaseChatRepository.getConversation
    // always builds a new Conversation from a fresh row fetch, so returning
    // the caller's exact instance here would mask any bug that assumes
    // state.conversation stays identical() to the widget's original
    // conversation (chatControllerProvider is a .family keyed by object
    // identity, since Conversation has no == override).
    final base = conversationOverride ?? activeConversation(relationshipId);
    return base.copyWith();
  }

  @override
  Future<bool> canAccessRelationship(String relationshipId) async => true;

  @override
  Future<void> releaseChannel(String relationshipId) async {
    // No-op: the fake is per-test and shares one stream across the test's
    // lifetime; nothing to reclaim mid-session.
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    await _typingController.close();
    await _pinnedController.close();
  }

  // --- Unused-by-M1 surface: minimal implementations. ---
  @override
  Future<List<Conversation>> getConversations() async => const [];
  @override
  Future<Conversation?> getPrimaryConversation() async => null;
  @override
  Future<String?> getRelationshipIdForPartner(String partnerUserId) async =>
      null;

  /// Failure seam for [createMediaUploadIntent]/[uploadChatMedia], scripted
  /// by call number (1-indexed across BOTH methods combined, matching the
  /// order _attemptSend's two-intent video branch actually calls them in:
  /// call 1 = video's createMediaUploadIntent, call 2 = video's
  /// uploadChatMedia, call 3 = thumbnail's createMediaUploadIntent, call 4 =
  /// thumbnail's uploadChatMedia). Left at its default (empty map, always
  /// succeed) every other test using this harness is unaffected.
  final Map<int, Object> mediaCallFailures = {};
  int _mediaCallCount = 0;

  @override
  Future<ChatMediaUploadIntent> createMediaUploadIntent({
    required String relationshipId,
    required String mimeType,
    required String mediaType,
  }) async {
    _mediaCallCount++;
    final failure = mediaCallFailures[_mediaCallCount];
    if (failure != null) throw failure;
    return ChatMediaUploadIntent(
      intentId: 'intent',
      storageKey: 'chat-media/test.jpg',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      bucket: 'message-media',
    );
  }

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
  }) async {
    _mediaCallCount++;
    final failure = mediaCallFailures[_mediaCallCount];
    if (failure != null) throw failure;
  }

  @override
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    signedUrlRequests.add(mediaKey);
    // Null by default preserves the behaviour every existing test was
    // written against (no URL resolves); tests that need a real one opt in
    // via [signMediaUrls].
    if (!signMediaUrls) return null;
    return 'https://signed.test/$mediaKey?token=abc';
  }

  /// Storage keys passed to [createSignedMediaUrl], in call order.
  final List<String> signedUrlRequests = [];

  /// When true, [createSignedMediaUrl] returns a usable fake signed URL
  /// instead of null.
  bool signMediaUrls = false;

  /// Recorded messageIds passed to [markVideoViewed], in call order —
  /// includes calls that go on to throw via [markVideoViewedFailures].
  final List<String> markVideoViewedCalls = [];

  /// Queued errors for [markVideoViewed], consumed FIFO — one entry is
  /// popped and thrown per call while the queue is non-empty, then calls
  /// succeed normally. Lets a test script "fails once, then a retry
  /// succeeds" (or "fails every time") without network mocking.
  final List<Object> markVideoViewedFailures = [];

  @override
  Future<void> markVideoViewed({required String messageId}) async {
    markVideoViewedCalls.add(messageId);
    if (markVideoViewedFailures.isNotEmpty) {
      throw markVideoViewedFailures.removeAt(0);
    }
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(viewedAt: DateTime.now());
    }
  }

  @override
  Future<int> fetchStreak(String relationshipId) async => streakValue;

  /// Every call to [setRelationshipChatName], in call order.
  final List<({String relationshipId, String chatName})> setChatNameCalls = [];

  /// When set, [setRelationshipChatName] throws this instead of
  /// succeeding. The call is still recorded first, so a test can assert
  /// both that the write was attempted and that the failure surfaced.
  Object? setChatNameError;

  @override
  Future<void> setRelationshipChatName({
    required String relationshipId,
    required String chatName,
  }) async {
    setChatNameCalls.add((relationshipId: relationshipId, chatName: chatName));
    final error = setChatNameError;
    if (error != null) throw error;
  }

  @override
  Future<RelationshipAvatarUploadIntent> createRelationshipAvatarUploadIntent({
    required String relationshipId,
    required String mimeType,
  }) async => RelationshipAvatarUploadIntent(
    intentId: 'avatar-intent',
    storageKey: 'relationship-avatars/test.jpg',
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    bucket: 'relationship-avatars',
  );
  @override
  Future<void> uploadRelationshipAvatarImage({
    required RelationshipAvatarUploadIntent intent,
    required String localPath,
    required String mimeType,
  }) async {}
  @override
  Future<void> applyRelationshipAvatar({
    required String relationshipId,
    required String intentId,
  }) async {}

  /// Recorded calls for assertions on the star/pin/delete/edit surface.
  final List<String> deleteMessageCalls = [];
  final List<({String messageId, String newContent})> editMessageCalls = [];
  final Set<String> starredMessageIds = {};
  final Set<String> pinnedMessageIds = {};
  final _pinnedController = StreamController<void>.broadcast();

  /// messageId -> (userId -> emoji). Mirrors the real schema's
  /// PRIMARY KEY (message_id, user_id) shape: at most one emoji per user
  /// per message.
  final Map<String, Map<String, String>> reactionsByMessage = {};

  @override
  Future<void> deleteMessage(String messageId) async {
    deleteMessageCalls.add(messageId);
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(
        deletedAt: DateTime.now(),
        content: '',
      );
    }
  }

  @override
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    editMessageCalls.add((messageId: messageId, newContent: newContent));
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(
        content: newContent,
        editedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<List<MessageEditHistoryEntry>> getMessageEditHistory(
    String messageId,
  ) async => const [];

  @override
  Future<void> starMessage(String messageId) async {
    starredMessageIds.add(messageId);
  }

  @override
  Future<void> unstarMessage(String messageId) async {
    starredMessageIds.remove(messageId);
  }

  @override
  Future<void> addReaction({
    required String relationshipId,
    required String messageId,
    required String emoji,
  }) async {
    final byUser = reactionsByMessage.putIfAbsent(messageId, () => {});
    byUser[currentUserId] = emoji;
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(
        reactions: _reactionsMapFor(messageId),
      );
    }
  }

  @override
  Future<void> removeReaction(String messageId) async {
    reactionsByMessage[messageId]?.remove(currentUserId);
    final existing = serverMessages[messageId];
    if (existing != null) {
      serverMessages[messageId] = existing.copyWith(
        reactions: _reactionsMapFor(messageId),
      );
    }
  }

  Map<String, Set<String>> _reactionsMapFor(String messageId) {
    final byUser = reactionsByMessage[messageId] ?? const {};
    final byEmoji = <String, Set<String>>{};
    for (final entry in byUser.entries) {
      byEmoji.putIfAbsent(entry.value, () => {}).add(entry.key);
    }
    return byEmoji;
  }

  @override
  Future<List<Message>> getStarredMessages() async =>
      serverMessages.values
          .where((m) => starredMessageIds.contains(m.id))
          .toList();

  @override
  Future<List<Message>> getMediaMessages(
    String relationshipId, {
    required String mediaType,
  }) async {
    final matches =
        serverMessages.values
            .where(
              (m) =>
                  m.relationshipId == relationshipId &&
                  m.mediaType == mediaType &&
                  !m.isDeleted &&
                  !m.isViewOnce,
            )
            .toList();
    // Newest-first, matching SupabaseChatRepository's own
    // .order('created_at', ascending: false) — callers (chat media gallery,
    // the chat identity card's recent-photos strip) rely on this ordering
    // contract, not just on "these are the matching rows".
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  @override
  Future<List<Message>> searchMessages(
    String relationshipId, {
    required String query,
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];
    return serverMessages.values
        .where(
          (m) =>
              m.relationshipId == relationshipId &&
              !m.isDeleted &&
              m.content.toLowerCase().contains(trimmed),
        )
        .toList();
  }

  @override
  Future<void> pinMessage({
    required String relationshipId,
    required String messageId,
  }) async {
    pinnedMessageIds.add(messageId);
    _pinnedController.add(null);
  }

  @override
  Future<void> unpinMessage({
    required String relationshipId,
    required String messageId,
  }) async {
    pinnedMessageIds.remove(messageId);
    _pinnedController.add(null);
  }

  @override
  Future<List<Message>> getPinnedMessages(String relationshipId) async =>
      serverMessages.values
          .where(
            (m) =>
                m.relationshipId == relationshipId &&
                pinnedMessageIds.contains(m.id),
          )
          .toList();
}

/// An in-memory cache backend for tests (no platform storage).
ChatCacheBackend memBackend() => stub.createBackend();

Conversation activeConversation(String relationshipId) => Conversation(
  id: relationshipId,
  relationshipId: relationshipId,
  partnerId: 'partner',
  name: 'Partner',
  updatedAt: DateTime.now(),
  relationshipStatus: 'active',
  availability: ConversationAvailability.active,
);

Conversation readOnlyConversation(String relationshipId) => Conversation(
  id: relationshipId,
  relationshipId: relationshipId,
  partnerId: 'partner',
  name: 'Partner',
  updatedAt: DateTime.now(),
  relationshipStatus: 'ended',
  availability: ConversationAvailability.readOnly,
);

User testUser(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

/// Builds a [ProviderContainer] wired to the fake repo, an in-memory cache, and
/// a fixed current user. Callers must dispose it.
ProviderContainer buildChatContainer({
  required FakeChatRepository repository,
  required String userId,
  List<Override> extraOverrides = const [],
}) {
  final cache = ChatCacheService.forTesting(backend: stub.createBackend());
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
      chatCacheServiceProvider.overrideWithValue(cache),
      currentUserProvider.overrideWithValue(testUser(userId)),
      // _MessageList reads chatExpressivenessProvider to modulate the
      // first-of-day shimmer and reconnect cascade. Override it with a fake
      // notifier (calm default, matching production's default) so tests
      // don't need an async SharedPreferences.getInstance() just to render.
      chatExpressivenessProvider.overrideWith(
        (ref) => ChatFeelPreferenceNotifier.forTesting(),
      ),
      ...extraOverrides,
    ],
  );
  return container;
}
