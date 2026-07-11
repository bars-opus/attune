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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      'source': 'native',
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
    final all = serverMessages.values
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
    final all = serverMessages.values
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
    return conversationOverride ?? activeConversation(relationshipId);
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
  }

  // --- Unused-by-M1 surface: minimal implementations. ---
  @override
  Future<List<Conversation>> getConversations() async => const [];
  @override
  Future<Conversation?> getPrimaryConversation() async => null;
  @override
  Future<String?> getRelationshipIdForPartner(String partnerUserId) async =>
      null;
  @override
  Future<ChatMediaUploadIntent> createImageUploadIntent({
    required String relationshipId,
    required String mimeType,
  }) async =>
      ChatMediaUploadIntent(
        intentId: 'intent',
        storageKey: 'chat-media/test.jpg',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        bucket: 'message-media',
      );
  @override
  Future<void> uploadChatImage({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
  }) async {}
  @override
  Future<String?> createSignedMediaUrl(String mediaKey) async => null;
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
  final cache = ChatCacheService.forTesting(
    backend: stub.createBackend(),
  );
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
      chatCacheServiceProvider.overrideWithValue(cache),
      currentUserProvider.overrideWithValue(testUser(userId)),
      ...extraOverrides,
    ],
  );
  return container;
}
