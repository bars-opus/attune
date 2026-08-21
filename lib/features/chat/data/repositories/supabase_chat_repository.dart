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

  // Per-relationship invalidation + typing streams sharing one channel.
  final Map<String, StreamController<void>> _eventControllers = {};
  final Map<String, StreamController<TypingEvent>> _typingControllers = {};

  // Short-lived signed-URL cache keyed by object key. Signed URLs live for
  // [_signedUrlTtl]; we reuse them within a safety margin so a page of images
  // does not re-sign the same object on every fetch (Spec 8.2, rate limits in
  // Section 14). Never persisted — memory only, cleared on dispose.
  static const _signedUrlTtl = Duration(seconds: 600);
  static const _signedUrlSafetyMargin = Duration(seconds: 60);
  final Map<String, ({String url, DateTime expiresAt})> _signedUrlCache = {};

  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,'
      'media_duration_ms,media_waveform,media_width,media_height,source,'
      'reply_to_message_id,quoted_text,deleted_at,edited_at,'
      'is_view_once,viewed_at,is_system_notice';

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
        .select(
          'id,user_a,user_b,status,chat_archived_at,created_at,ended_at,'
          'chat_name,chat_avatar_url,chat_avatar_thumbnail_url',
        )
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

      // Couple-chosen identity wins once set (see spec's Read path /
      // display section) — falls back to the partner's own profile until
      // then, exactly matching pre-feature behavior. Prefer the thumbnail
      // once the async job has produced one; the full-size key is still
      // shown in the gap between "photo set" and "thumbnail ready" rather
      // than nothing.
      final chatAvatarKey =
          (relationship['chat_avatar_thumbnail_url'] as String?) ??
          (relationship['chat_avatar_url'] as String?);
      final avatarUrl =
          chatAvatarKey != null
              ? await _createRelationshipAvatarSignedUrl(chatAvatarKey)
              : partner?['avatar_url'] as String?;

      conversations.add(
        Conversation(
          id: relationshipId,
          relationshipId: relationshipId,
          partnerId: partnerId,
          name:
              (relationship['chat_name'] as String?) ??
              (partner?['display_name'] as String?) ??
              'Partner',
          avatarUrl: avatarUrl,
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
              'media_duration_ms': mediaDurationMs,
              'media_waveform': waveform,
              'media_thumbnail_url': mediaThumbnailKey,
              'media_width': mediaWidth,
              'media_height': mediaHeight,
              'reply_to_message_id': replyToMessageId,
              'quoted_text': quotedText,
              'is_view_once': isViewOnce,
              'is_system_notice': isSystemNotice,
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
  Future<ChatMediaUploadIntent> createMediaUploadIntent({
    required String relationshipId,
    required String mimeType,
    required String mediaType,
  }) async {
    final response = await _supabase.rpc(
      'create_chat_media_upload_intent',
      params: {
        'p_relationship_id': relationshipId,
        'p_mime_type': mimeType,
        'p_media_type': mediaType,
      },
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
  Future<void> uploadChatMedia({
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
  Future<void> markVideoViewed({required String messageId}) async {
    await _supabase.rpc(
      'mark_video_viewed',
      params: {'p_message_id': messageId},
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

  /// Same cache/TTL as [createSignedMediaUrl] — storage keys are already
  /// globally unique (`relationship-avatars/{relationshipId}/...` vs
  /// `chat-media/...`), so sharing one cache map risks no collision.
  Future<String?> _createRelationshipAvatarSignedUrl(String storageKey) async {
    final cached = _signedUrlCache[storageKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    try {
      final url = await _supabase.storage
          .from('relationship-avatars')
          .createSignedUrl(storageKey, _signedUrlTtl.inSeconds);
      _signedUrlCache[storageKey] = (
        url: url,
        expiresAt: DateTime.now().add(_signedUrlTtl - _signedUrlSafetyMargin),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setRelationshipChatName({
    required String relationshipId,
    required String chatName,
  }) async {
    await _supabase.rpc(
      'set_relationship_chat_name',
      params: {'p_relationship_id': relationshipId, 'p_chat_name': chatName},
    );
  }

  @override
  Future<RelationshipAvatarUploadIntent> createRelationshipAvatarUploadIntent({
    required String relationshipId,
    required String mimeType,
  }) async {
    final response = await _supabase.rpc(
      'create_relationship_avatar_upload_intent',
      params: {'p_relationship_id': relationshipId, 'p_mime_type': mimeType},
    );
    final row =
        response is List
            ? Map<String, dynamic>.from(response.first as Map)
            : Map<String, dynamic>.from(response as Map);

    return RelationshipAvatarUploadIntent(
      intentId: row['intent_id'] as String,
      storageKey: row['storage_key'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
      bucket: row['bucket'] as String,
    );
  }

  @override
  Future<void> uploadRelationshipAvatarImage({
    required RelationshipAvatarUploadIntent intent,
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
  Future<void> applyRelationshipAvatar({
    required String relationshipId,
    required String intentId,
  }) async {
    await _supabase.rpc(
      'set_relationship_avatar',
      params: {'p_relationship_id': relationshipId, 'p_intent_id': intentId},
    );
  }

  /// Lazily creates and subscribes the single Realtime channel for
  /// [relationshipId], wiring both the postgres_changes handlers (message /
  /// relationship row invalidation) and the typing broadcast handler onto it.
  /// The channel is shared by [watchConversationEvents] and [watchTyping] and
  /// lives until [dispose()] — simpler than ref-counting two subscribers, and
  /// safe because callers cancel their stream subscriptions without needing
  /// the underlying channel torn down mid-session.
  RealtimeChannel _channelFor(String relationshipId) {
    final existing = _channels[relationshipId];
    if (existing != null) return existing;

    final events = _eventControllers.putIfAbsent(
      relationshipId,
      () => StreamController<void>.broadcast(),
    );
    final typing = _typingControllers.putIfAbsent(
      relationshipId,
      () => StreamController<TypingEvent>.broadcast(),
    );

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
              callback: (_) => events.add(null),
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
              callback: (_) => events.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'message_pins',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'relationship_id',
                value: relationshipId,
              ),
              callback: (_) => events.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'message_reactions',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'relationship_id',
                value: relationshipId,
              ),
              callback: (_) => events.add(null),
            )
            .onBroadcast(
              event: 'typing',
              callback: (payload) {
                // Supabase broadcast nests the sent data under a `payload` key on
                // the receiving side; be robust to both the nested and flat shape.
                final data =
                    (payload['payload'] is Map)
                        ? Map<String, dynamic>.from(payload['payload'] as Map)
                        : payload;
                final senderId = data['senderId'];
                final isTyping = data['typing'];
                if (senderId is String && isTyping is bool) {
                  typing.add(TypingEvent(senderId, isTyping));
                }
              },
            )
            .subscribe();

    _channels[relationshipId] = channel;
    return channel;
  }

  @override
  Stream<void> watchConversationEvents(String relationshipId) {
    _channelFor(relationshipId);
    return _eventControllers[relationshipId]!.stream;
  }

  @override
  Stream<TypingEvent> watchTyping(String relationshipId) {
    _channelFor(relationshipId);
    return _typingControllers[relationshipId]!.stream;
  }

  @override
  void sendTyping(String relationshipId, {required bool typing}) {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final channel = _channelFor(relationshipId);
    // Fire-and-forget; a broadcast failure must never block messaging.
    try {
      channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'senderId': user.id, 'typing': typing},
      );
    } catch (_) {
      // ignore — typing is best-effort
    }
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
  Future<int> fetchStreak(String relationshipId) async {
    try {
      final offset = DateTime.now().timeZoneOffset.inMinutes;
      final res = await _supabase.rpc(
        'chat_conversation_streak',
        params: {
          'p_relationship_id': relationshipId,
          'p_utc_offset_minutes': offset,
        },
      );
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
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
  Future<void> releaseChannel(String relationshipId) async {
    final channel = _channels.remove(relationshipId);
    if (channel != null) {
      await _supabase.removeChannel(channel);
    }
    final events = _eventControllers.remove(relationshipId);
    if (events != null) {
      await events.close();
    }
    final typing = _typingControllers.remove(relationshipId);
    if (typing != null) {
      await typing.close();
    }
  }

  @override
  Future<void> dispose() async {
    for (final channel in _channels.values) {
      await _supabase.removeChannel(channel);
    }
    _channels.clear();
    for (final c in _eventControllers.values) {
      await c.close();
    }
    _eventControllers.clear();
    for (final c in _typingControllers.values) {
      await c.close();
    }
    _typingControllers.clear();
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
    final messageIds = rows.map((row) => row['id'] as String).toList();
    final reactionsByMessageId = await _fetchReactionsFor(messageIds);

    return Future.wait(
      rows.map((row) async {
        var base = Message.fromRow(row, currentUserId: currentUserId);
        final reactions = reactionsByMessageId[base.id];
        if (reactions != null) {
          base = base.copyWith(reactions: reactions);
        }
        if (base.mediaKey == null ||
            (base.mediaType != 'image' &&
                base.mediaType != 'audio' &&
                base.mediaType != 'video')) {
          return base;
        }
        if (base.mediaType == 'video') {
          final results = await Future.wait([
            createSignedMediaUrl(base.mediaKey!),
            if (base.mediaThumbnailKey != null)
              createSignedMediaUrl(base.mediaThumbnailKey!),
          ]);
          return base.copyWith(
            signedMediaUrl: results[0],
            signedThumbnailUrl: results.length > 1 ? results[1] : null,
          );
        }
        final signedUrl = await createSignedMediaUrl(
          base.mediaThumbnailKey ?? base.mediaKey!,
        );
        return base.copyWith(signedMediaUrl: signedUrl);
      }),
    );
  }

  /// Batch-fetches reactions for a page of messages in ONE query (an `IN`
  /// filter over [messageIds]) rather than one query per message — a page
  /// is capped at chatConfigProvider's messagePageSize (50 by default), so
  /// this is a single round trip per page, not N.
  Future<Map<String, Map<String, Set<String>>>> _fetchReactionsFor(
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return const {};

    final rows = await _supabase
        .from('message_reactions')
        .select('message_id,user_id,emoji')
        .inFilter('message_id', messageIds);

    final result = <String, Map<String, Set<String>>>{};
    for (final row in rows) {
      final messageId = row['message_id'] as String;
      final userId = row['user_id'] as String;
      final emoji = row['emoji'] as String;
      final byEmoji = result.putIfAbsent(messageId, () => {});
      byEmoji.putIfAbsent(emoji, () => {}).add(userId);
    }
    return result;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    await _supabase.rpc('delete_message', params: {'p_message_id': messageId});
  }

  @override
  Future<void> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    await _supabase.rpc(
      'edit_message',
      params: {'p_message_id': messageId, 'p_new_content': newContent},
    );
  }

  @override
  Future<List<MessageEditHistoryEntry>> getMessageEditHistory(
    String messageId,
  ) async {
    final rows = await _supabase
        .from('message_edit_history')
        .select('previous_content,edited_at')
        .eq('message_id', messageId)
        .order('edited_at', ascending: true);

    return rows
        .map(
          (row) => MessageEditHistoryEntry(
            previousContent: row['previous_content'] as String,
            editedAt: DateTime.parse(row['edited_at'] as String).toLocal(),
          ),
        )
        .toList();
  }

  @override
  Future<void> starMessage(String messageId) async {
    final user = _currentUser;
    await _supabase.from('message_stars').upsert({
      'message_id': messageId,
      'user_id': user.id,
    });
  }

  @override
  Future<void> unstarMessage(String messageId) async {
    final user = _currentUser;
    await _supabase
        .from('message_stars')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', user.id);
  }

  @override
  Future<List<Message>> getStarredMessages() async {
    final user = _currentUser;
    final rows = await _supabase
        .from('message_stars')
        .select('starred_at,messages!inner($_messageColumns)')
        .eq('user_id', user.id)
        .order('starred_at', ascending: false);

    return rows
        .map(
          (row) => Message.fromRow(
            row['messages'] as Map<String, dynamic>,
            currentUserId: user.id,
          ),
        )
        .toList();
  }

  @override
  Future<List<Message>> getMediaMessages(
    String relationshipId, {
    required String mediaType,
  }) async {
    final user = _currentUser;
    final rows = await _supabase
        .from('messages')
        .select(_messageColumns)
        .eq('relationship_id', relationshipId)
        .eq('media_type', mediaType)
        // A deleted message's media is gone (see delete_message RPC's
        // tombstoning) — excluded here since a media grid has nowhere
        // sensible to show a tombstone the way a chat bubble does.
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .order('id', ascending: false);

    return rows
        .map((row) => Message.fromRow(row, currentUserId: user.id))
        .toList();
  }

  @override
  Future<List<Message>> searchMessages(
    String relationshipId, {
    required String query,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final user = _currentUser;
    // Escape ilike's own metacharacters (% and _) so a literal search for
    // e.g. "50% off" or "a_b" matches that exact text instead of being
    // interpreted as wildcards.
    final escaped = trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await _supabase
        .from('messages')
        .select(_messageColumns)
        .eq('relationship_id', relationshipId)
        .ilike('content', '%$escaped%')
        // A deleted message's content is gone (delete_message RPC clears
        // it) — excluded here since there is nothing to show/highlight in
        // a search result for a tombstoned message.
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .order('id', ascending: false);

    return rows
        .map((row) => Message.fromRow(row, currentUserId: user.id))
        .toList();
  }

  @override
  Future<void> pinMessage({
    required String relationshipId,
    required String messageId,
  }) async {
    await _supabase.rpc(
      'pin_message',
      params: {'p_relationship_id': relationshipId, 'p_message_id': messageId},
    );
  }

  @override
  Future<void> unpinMessage({
    required String relationshipId,
    required String messageId,
  }) async {
    await _supabase
        .from('message_pins')
        .delete()
        .eq('relationship_id', relationshipId)
        .eq('message_id', messageId);
  }

  @override
  Future<List<Message>> getPinnedMessages(String relationshipId) async {
    final user = _currentUser;
    final rows = await _supabase
        .from('message_pins')
        .select('pinned_at,messages!inner($_messageColumns)')
        .eq('relationship_id', relationshipId)
        .order('pinned_at', ascending: false);

    return rows
        .map(
          (row) => Message.fromRow(
            row['messages'] as Map<String, dynamic>,
            currentUserId: user.id,
          ),
        )
        .toList();
  }

  @override
  Future<void> addReaction({
    required String relationshipId,
    required String messageId,
    required String emoji,
  }) async {
    await _supabase.rpc(
      'react_to_message',
      params: {
        'p_relationship_id': relationshipId,
        'p_message_id': messageId,
        'p_emoji': emoji,
      },
    );
  }

  @override
  Future<void> removeReaction(String messageId) async {
    await _supabase.rpc('remove_reaction', params: {'p_message_id': messageId});
  }
}
