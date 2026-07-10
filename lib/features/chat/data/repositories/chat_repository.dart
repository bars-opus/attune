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
  Stream<void> watchConversationEvents(String relationshipId);
  Future<void> markDelivered(List<String> messageIds);
  Future<void> markConversationRead(String relationshipId);
  Future<bool> canAccessRelationship(String relationshipId);

  /// Reports the conversation the user is actively viewing so the backend can
  /// suppress a redundant push (Spec 9.2). Pass null to clear presence when the
  /// view is backgrounded or left. Best-effort; failures never block chat.
  Future<void> setPresence(String? relationshipId);

  Future<void> dispose();
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
