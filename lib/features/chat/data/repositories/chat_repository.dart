import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';

abstract class ChatRepository {
  Future<List<Conversation>> getConversations();
  Future<Conversation?> getPrimaryConversation();
  Future<Conversation?> getConversation(String relationshipId);
  Future<String?> getRelationshipIdForPartner(String partnerUserId);
  Future<List<Message>> getMessages(
    String relationshipId, {
    ChatMessageCursor? before,
    int limit = 50,
  });

  /// Forward keyset catch-up: canonical rows strictly newer than [after],
  /// oldest-first, for reconnect/missed-event recovery (Spec 6.1). When [after]
  /// is null, returns the newest [limit] rows. Pages until fewer than [limit]
  /// remain so a large gap is fully restored.
  Future<List<Message>> getMessagesAfter(
    String relationshipId, {
    ChatMessageCursor? after,
    int limit = 50,
  });
  Future<Message> sendTextMessage({
    required String relationshipId,
    required String senderId,
    required String clientMessageId,
    required String content,
    String? mediaKey,
    String? mediaType,
    String? replyToMessageId,
    String? quotedText,
  });
  Future<Message?> findMessageByClientId({
    required String senderId,
    required String clientMessageId,
  });
  Future<ChatMediaUploadIntent> createImageUploadIntent({
    required String relationshipId,
    required String mimeType,
  });
  Future<void> uploadChatImage({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
  });
  Future<String?> createSignedMediaUrl(String mediaKey);

  /// Sets this relationship's chat name (either partner may call this at
  /// any time the relationship is active). Validated server-side (1-30
  /// trimmed characters); see set_relationship_chat_name RPC.
  Future<void> setRelationshipChatName({
    required String relationshipId,
    required String chatName,
  });

  /// Requests a one-time upload slot for a new relationship avatar photo —
  /// mirrors [createImageUploadIntent]'s shape but scoped to the
  /// relationship-avatars bucket via a separate RPC/table pipeline (see
  /// docs/superpowers/specs/2026-08-11-couple-chat-identity-design.md).
  Future<RelationshipAvatarUploadIntent> createRelationshipAvatarUploadIntent({
    required String relationshipId,
    required String mimeType,
  });

  Future<void> uploadRelationshipAvatarImage({
    required RelationshipAvatarUploadIntent intent,
    required String localPath,
    required String mimeType,
  });

  /// Validates the uploaded object against [intentId] and applies it as the
  /// relationship's chat_avatar_url, enqueuing async thumbnail generation.
  Future<void> applyRelationshipAvatar({
    required String relationshipId,
    required String intentId,
  });

  Stream<void> watchConversationEvents(String relationshipId);
  Future<void> markDelivered(List<String> messageIds);
  Future<void> markConversationRead(String relationshipId);
  Future<bool> canAccessRelationship(String relationshipId);

  /// Current conversation streak (consecutive local days both partners
  /// messaged). 0 on error or when there is no streak.
  Future<int> fetchStreak(String relationshipId);

  /// Reports the conversation the user is actively viewing so the backend can
  /// suppress a redundant push (Spec 9.2). Pass null to clear presence when the
  /// view is backgrounded or left. Best-effort; failures never block chat.
  Future<void> setPresence(String? relationshipId);

  /// Broadcasts an ephemeral typing signal to the other member over Realtime
  /// (no DB write). Best-effort; failures never block messaging.
  void sendTyping(String relationshipId, {required bool typing});

  /// Ephemeral typing events from the partner on this relationship's channel.
  Stream<TypingEvent> watchTyping(String relationshipId);

  /// Releases the shared Realtime channel + streams for a relationship when its
  /// chat view is disposed, so channels don't accumulate across a session.
  Future<void> releaseChannel(String relationshipId);

  Future<void> dispose();
}

/// An ephemeral typing signal from a relationship member. Never persisted.
class TypingEvent {
  const TypingEvent(this.senderId, this.typing);
  final String senderId;
  final bool typing;
}

class ChatMessageCursor {
  final DateTime createdAt;
  final String id;

  const ChatMessageCursor({required this.createdAt, required this.id});
}

class ChatMediaUploadIntent {
  final String intentId;
  final String storageKey;
  final DateTime expiresAt;
  final String bucket;

  const ChatMediaUploadIntent({
    required this.intentId,
    required this.storageKey,
    required this.expiresAt,
    required this.bucket,
  });
}

class RelationshipAvatarUploadIntent {
  final String intentId;
  final String storageKey;
  final DateTime expiresAt;
  final String bucket;

  const RelationshipAvatarUploadIntent({
    required this.intentId,
    required this.storageKey,
    required this.expiresAt,
    required this.bucket,
  });
}
