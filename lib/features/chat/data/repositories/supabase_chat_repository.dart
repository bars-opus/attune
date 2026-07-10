import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseChatRepositoryProvider = Provider<ChatRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseChatRepository(supabase);
});

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._supabase);

  final SupabaseClient _supabase;
  final Map<String, RealtimeChannel> _channels = {};

  // Short-lived signed-URL cache keyed by object key. Signed URLs live for
  // [_signedUrlTtl]; we reuse them within a safety margin so a page of images
  // does not re-sign the same object on every fetch (Spec 8.2, rate limits in
  // Section 14). Never persisted — memory only, cleared on dispose.
  static const _signedUrlTtl = Duration(seconds: 600);
  static const _signedUrlSafetyMargin = Duration(seconds: 60);
  final Map<String, ({String url, DateTime expiresAt})> _signedUrlCache = {};

  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,source';

  User get _currentUser {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('User must be authenticated to use chat.');
    }
    return user;
  }

  @override
  Future<List<Conversation>> getConversations() async {
    final user = _currentUser;
    final relationships = await _supabase
        .from('relationships')
        .select('id,user_a,user_b,status,chat_archived_at,created_at,ended_at')
        .or('user_a.eq.${user.id},user_b.eq.${user.id}')
        .isFilter('chat_archived_at', null)
        .order('created_at', ascending: false);

    if (relationships.isEmpty) return const [];

    final partnerIds =
        relationships
            .map((row) {
              final userA = row['user_a'] as String;
              final userB = row['user_b'] as String?;
              if (userA == user.id) return userB;
              return userA;
            })
            .whereType<String>()
            .toSet()
            .toList();

    final usersById = await _loadUsersById(partnerIds);
    final conversations = <Conversation>[];

    for (final relationship in relationships) {
      final relationshipId = relationship['id'] as String;
      final partnerId = _partnerIdFor(relationship, user.id);
      if (partnerId == null) continue;

      final partner = usersById[partnerId];
      final lastMessage = await _fetchLastMessage(relationshipId, user.id);
      final unreadCount = await _fetchUnreadCount(relationshipId, user.id);
      final status = relationship['status'] as String;
      final archivedAt = relationship['chat_archived_at'];
      final availability =
          archivedAt != null
              ? ConversationAvailability.archived
              : (status == 'active'
                  ? ConversationAvailability.active
                  : ConversationAvailability.readOnly);

      conversations.add(
        Conversation(
          id: relationshipId,
          relationshipId: relationshipId,
          partnerId: partnerId,
          name: (partner?['display_name'] as String?) ?? 'Partner',
          avatarUrl: partner?['avatar_url'] as String?,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
          updatedAt: lastMessage?.createdAt ?? DateTime.now(),
          relationshipStatus: status,
          availability: availability,
        ),
      );
    }

    return conversations;
  }

  @override
  Future<Conversation?> getPrimaryConversation() async {
    final conversations = await getConversations();
    if (conversations.isEmpty) return null;

    conversations.sort((a, b) {
      final aRank = a.canSend ? 0 : 1;
      final bRank = b.canSend ? 0 : 1;
      if (aRank != bRank) return aRank.compareTo(bRank);
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return conversations.first;
  }

  @override
  Future<Conversation?> getConversation(String relationshipId) async {
    final conversations = await getConversations();
    for (final conversation in conversations) {
      if (conversation.relationshipId == relationshipId) {
        return conversation;
      }
    }
    return null;
  }

  @override
  Future<String?> getRelationshipIdForPartner(String partnerUserId) async {
    final user = _currentUser;
    final direct =
        await _supabase
            .from('relationships')
            .select('id,chat_archived_at')
            .or(
              'and(user_a.eq.${user.id},user_b.eq.$partnerUserId),and(user_a.eq.$partnerUserId,user_b.eq.${user.id})',
            )
            .isFilter('chat_archived_at', null)
            .maybeSingle();

    return direct == null ? null : direct['id'] as String;
  }

  @override
  Future<List<Message>> getMessages(
    String relationshipId, {
    ChatMessageCursor? before,
    int limit = 50,
  }) async {
    final user = _currentUser;
    final rows =
        before == null
            ? await _supabase
                .from('messages')
                .select(_messageColumns)
                .eq('relationship_id', relationshipId)
                .order('created_at', ascending: false)
                .order('id', ascending: false)
                .limit(limit)
            : await _supabase
                .from('messages')
                .select(_messageColumns)
                .eq('relationship_id', relationshipId)
                .or(
                  'created_at.lt.${before.createdAt.toUtc().toIso8601String()},'
                  'and(created_at.eq.${before.createdAt.toUtc().toIso8601String()},id.lt.${before.id})',
                )
                .order('created_at', ascending: false)
                .order('id', ascending: false)
                .limit(limit);

    return _hydrateMessages(rows, user.id);
  }

  @override
  Future<List<Message>> getMessagesAfter(
    String relationshipId, {
    ChatMessageCursor? after,
    int limit = 50,
  }) async {
    final user = _currentUser;
    final collected = <Map<String, dynamic>>[];
    ChatMessageCursor? cursor = after;

    // Page forward until the gap is exhausted so a reconnect after many missed
    // messages restores every row, not just the first page (Spec 6.1, 16).
    while (true) {
      final rows =
          cursor == null
              ? await _supabase
                  .from('messages')
                  .select(_messageColumns)
                  .eq('relationship_id', relationshipId)
                  .order('created_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit)
              : await _supabase
                  .from('messages')
                  .select(_messageColumns)
                  .eq('relationship_id', relationshipId)
                  .or(
                    'created_at.gt.${cursor.createdAt.toUtc().toIso8601String()},'
                    'and(created_at.eq.${cursor.createdAt.toUtc().toIso8601String()},id.gt.${cursor.id})',
                  )
                  .order('created_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit);

      if (rows.isEmpty) break;
      collected.addAll(rows);
      if (rows.length < limit) break;
      final last = rows.last;
      cursor = ChatMessageCursor(
        createdAt: DateTime.parse(last['created_at'] as String),
        id: last['id'] as String,
      );
    }

    return _hydrateMessages(collected, user.id);
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
    final user = _currentUser;
    if (senderId != user.id) {
      throw const PostgrestException(
        message: 'Authenticated sender mismatch.',
        code: '42501',
      );
    }
    final row =
        await _supabase
            .from('messages')
            .insert({
              'relationship_id': relationshipId,
              'sender_id': user.id,
              'client_message_id': clientMessageId,
              'content': content,
              'media_url': mediaKey,
              'media_type': mediaType,
            })
            .select(_messageColumns)
            .single();

    return _hydrateMessage(row, user.id);
  }

  @override
  Future<Message?> findMessageByClientId({
    required String senderId,
    required String clientMessageId,
  }) async {
    final user = _currentUser;
    final row =
        await _supabase
            .from('messages')
            .select(_messageColumns)
            .eq('sender_id', senderId)
            .eq('client_message_id', clientMessageId)
            .maybeSingle();

    if (row == null) return null;
    return _hydrateMessage(row, user.id);
  }

  @override
  Future<ChatMediaUploadIntent> createImageUploadIntent({
    required String relationshipId,
    required String mimeType,
  }) async {
    final response = await _supabase.rpc(
      'create_chat_media_upload_intent',
      params: {'p_relationship_id': relationshipId, 'p_mime_type': mimeType},
    );
    final row =
        response is List
            ? Map<String, dynamic>.from(response.first as Map)
            : Map<String, dynamic>.from(response as Map);

    return ChatMediaUploadIntent(
      intentId: row['intent_id'] as String,
      storageKey: row['storage_key'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
      bucket: row['bucket'] as String,
    );
  }

  @override
  Future<void> uploadChatImage({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
  }) async {
    await _supabase.storage
        .from(intent.bucket)
        .upload(
          intent.storageKey,
          File(localPath),
          fileOptions: FileOptions(upsert: false, contentType: mimeType),
        );
  }

  @override
  Future<String?> createSignedMediaUrl(String mediaKey) async {
    final cached = _signedUrlCache[mediaKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    try {
      final url = await _supabase.storage
          .from('message-media')
          .createSignedUrl(mediaKey, _signedUrlTtl.inSeconds);
      _signedUrlCache[mediaKey] = (
        url: url,
        expiresAt: DateTime.now().add(_signedUrlTtl - _signedUrlSafetyMargin),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<void> watchConversationEvents(String relationshipId) {
    final controller = StreamController<void>.broadcast();
    final existing = _channels.remove(relationshipId);
    if (existing != null) {
      _supabase.removeChannel(existing);
    }

    final channel =
        _supabase
            .channel('chat:$relationshipId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'relationship_id',
                value: relationshipId,
              ),
              callback: (_) => controller.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'relationships',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: relationshipId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();

    _channels[relationshipId] = channel;
    controller.onCancel = () {
      final current = _channels.remove(relationshipId);
      if (current != null) {
        _supabase.removeChannel(current);
      }
    };
    return controller.stream;
  }

  @override
  Future<void> markDelivered(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await _supabase.rpc(
      'mark_delivered',
      params: {'p_message_ids': messageIds},
    );
  }

  @override
  Future<void> markConversationRead(String relationshipId) async {
    await _supabase.rpc(
      'mark_conversation_read',
      params: {'p_relationship_id': relationshipId},
    );
  }

  @override
  Future<void> setPresence(String? relationshipId) async {
    try {
      await _supabase.rpc(
        'set_chat_presence',
        params: {'p_relationship_id': relationshipId},
      );
    } catch (_) {
      // Presence is best-effort; a failure only means a possibly-redundant push.
    }
  }

  @override
  Future<bool> canAccessRelationship(String relationshipId) async {
    final row =
        await _supabase
            .from('relationships')
            .select('id,chat_archived_at')
            .eq('id', relationshipId)
            .isFilter('chat_archived_at', null)
            .maybeSingle();
    return row != null;
  }

  @override
  Future<void> dispose() async {
    for (final channel in _channels.values) {
      await _supabase.removeChannel(channel);
    }
    _channels.clear();
    _signedUrlCache.clear();
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersById(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final rows = await _supabase
        .from('users')
        .select('id,display_name,avatar_url')
        .inFilter('id', userIds);
    return {
      for (final row in rows)
        row['id'] as String: Map<String, dynamic>.from(row),
    };
  }

  Future<Message?> _fetchLastMessage(
    String relationshipId,
    String currentUserId,
  ) async {
    final rows = await _supabase
        .from('messages')
        .select(_messageColumns)
        .eq('relationship_id', relationshipId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return _hydrateMessage(rows.first, currentUserId);
  }

  Future<int> _fetchUnreadCount(
    String relationshipId,
    String currentUserId,
  ) async {
    final rows = await _supabase
        .from('messages')
        .select('id')
        .eq('relationship_id', relationshipId)
        .neq('sender_id', currentUserId)
        .isFilter('read_at', null);
    return rows.length;
  }

  String? _partnerIdFor(
    Map<String, dynamic> relationship,
    String currentUserId,
  ) {
    final userA = relationship['user_a'] as String;
    final userB = relationship['user_b'] as String?;
    if (userA == currentUserId) return userB;
    return userA;
  }

  Future<Message> _hydrateMessage(
    Map<String, dynamic> row,
    String currentUserId,
  ) async {
    final results = await _hydrateMessages([row], currentUserId);
    return results.first;
  }

  /// Maps rows to messages, resolving signed image URLs in parallel rather than
  /// awaiting one round-trip per row (Spec Ghana-network performance, Section
  /// 14 rate limits). Non-image rows resolve instantly; the signed-URL cache
  /// collapses repeat objects across a page.
  Future<List<Message>> _hydrateMessages(
    List<Map<String, dynamic>> rows,
    String currentUserId,
  ) async {
    return Future.wait(
      rows.map((row) async {
        final base = Message.fromRow(row, currentUserId: currentUserId);
        if (base.mediaKey == null || base.mediaType != 'image') {
          return base;
        }
        final signedUrl = await createSignedMediaUrl(
          base.mediaThumbnailKey ?? base.mediaKey!,
        );
        return base.copyWith(signedMediaUrl: signedUrl);
      }),
    );
  }
}
