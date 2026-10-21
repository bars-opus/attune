import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/unread_count.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

final supabaseChatRepositoryProvider = Provider<ChatRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseChatRepository(supabase);
});

/// Most ids one [SupabaseChatRepository.getMessagesByIds] request carries.
/// An `in` filter travels in the URL; 100 uuids is about 3.7 KB, well under
/// gateway URL limits.
const maxMessageIdsPerRequest = 100;

/// Splits [ids] into request-sized chunks, first occurrence order, each id
/// once. No ids gives no chunks, so the caller makes no request.
@visibleForTesting
List<List<String>> chunkMessageIds(
  List<String> ids, {
  int size = maxMessageIdsPerRequest,
}) {
  final unique = ids.toSet().toList();
  return [
    for (var i = 0; i < unique.length; i += size)
      unique.sublist(i, i + size > unique.length ? unique.length : i + size),
  ];
}

/// The event a per-chat channel status emits: every `subscribed` is a
/// resync (the listener refetches what the socket missed); only the
/// channel's first one is marked initial (see [ChatRealtimeEvent.resync]).
@visibleForTesting
ChatRealtimeEvent? chatResyncEventFor(
  RealtimeSubscribeStatus status, {
  required bool joinedBefore,
}) {
  if (status != RealtimeSubscribeStatus.subscribed) return null;
  return ChatRealtimeEvent.resync(initial: !joinedBefore);
}

/// Each internal page of a changed-since read is bounded on its own, so a
/// slow link (every page slow, none hung) still completes a multi-page read.
const changedSincePageTimeout = Duration(seconds: 20);

/// Pages a changed-since read: up to [maxPages] pages of [limit] rows, each
/// continuing strictly after the exact (updated_at, id) of the last row the
/// previous page returned, stopping at a short page.
///
/// Every page is bounded by [pageTimeout]. A page that fails or times out
/// AFTER at least one page arrived ends the read with what arrived: the
/// result is then shorter than the cap, so the caller applies it and moves
/// its cursor to the last row received, and the next read continues from
/// there. Discarding those pages made a slow link fail every sync from the
/// same cursor forever. A first page that fails throws.
@visibleForTesting
Future<List<Map<String, dynamic>>> collectChangedSincePages({
  required Future<List<Map<String, dynamic>>> Function(
    String? lastUpdatedAt,
    String? lastId,
  )
  fetchPage,
  required String? startUpdatedAt,
  required String? startId,
  required int limit,
  required int maxPages,
  required Duration pageTimeout,
}) async {
  final collected = <Map<String, dynamic>>[];
  var lastUpdatedAt = startUpdatedAt;
  var lastId = startId;
  for (var page = 0; page < maxPages; page++) {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await fetchPage(lastUpdatedAt, lastId).timeout(pageTimeout);
    } catch (error) {
      if (collected.isEmpty) rethrow;
      ChatLog.e(
        'changed-since page ${page + 1} failed; keeping ${collected.length} '
        'rows',
        error,
      );
      break;
    }
    collected.addAll(rows);
    if (rows.length < limit) break;
    lastUpdatedAt = rows.last['updated_at'] as String;
    lastId = rows.last['id'] as String;
  }
  return collected;
}

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(
    this._supabase, {
    ChatMediaUploader? uploader,
    this.unreadCountTimeout = const Duration(seconds: 3),
  }) : _uploader = uploader;

  final SupabaseClient _supabase;

  /// Longest [getConversation] waits on the unread count before opening the
  /// chat without it (0: no divider) — a badge must never hold an open.
  final Duration unreadCountTimeout;
  final Map<String, RealtimeChannel> _channels = {};

  // Per-relationship invalidation + typing streams sharing one channel.
  final Map<String, StreamController<ChatRealtimeEvent>> _eventControllers =
      {};
  final Map<String, StreamController<TypingEvent>> _typingControllers = {};

  // Short-lived signed-URL cache keyed by object key. Signed URLs live for
  // [_signedUrlTtl]; we reuse them within a safety margin so a page of images
  // does not re-sign the same object on every fetch (Spec 8.2, rate limits in
  // Section 14). Never persisted — memory only, cleared on dispose.
  static const _signedUrlTtl = Duration(seconds: 600);
  static const _signedUrlSafetyMargin = Duration(seconds: 60);
  final Map<String, ({String url, DateTime expiresAt})> _signedUrlCache = {};

  /// `updated_at` (migration 20261019100000, which must be live before a
  /// build with this ships) rides every read, so a first page seeds the sync
  /// cursor from the exact server change time (final-review M7).
  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'sort_at,updated_at,game_session_id,'
      'delivered_at,read_receipt_at,media_url,media_thumbnail_url,media_type,'
      'media_duration_ms,media_waveform,media_width,media_height,source,'
      'reply_to_message_id,quoted_text,deleted_at,edited_at,'
      'is_view_once,viewed_at,is_system_notice,streak_views_remaining,'
      'story_item_id,message_origin,assistant_payload';

  /// Test-only: the columns every message read selects.
  @visibleForTesting
  static String get debugMessageColumns => _messageColumns;

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
        .select(_relationshipColumns)
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
      final lastMessage = await _fetchLastMessage(relationshipId, user.id);
      final unreadCount = await _fetchUnreadCount(relationshipId, user.id);
      conversations.add(
        await _conversationFromRow(
          relationship,
          partner: usersById[partnerId],
          partnerId: partnerId,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
        ),
      );
    }

    return conversations;
  }

  static const _relationshipColumns =
      'id,user_a,user_b,status,chat_archived_at,created_at,ended_at,'
      'chat_name,chat_avatar_url,chat_avatar_thumbnail_url';

  Future<Conversation> _conversationFromRow(
    Map<String, dynamic> relationship, {
    required Map<String, dynamic>? partner,
    required String partnerId,
    required Message? lastMessage,
    required int unreadCount,
  }) async {
    final relationshipId = relationship['id'] as String;
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

    return Conversation(
      id: relationshipId,
      relationshipId: relationshipId,
      partnerId: partnerId,
      name:
          (relationship['chat_name'] as String?) ??
          (partner?['display_name'] as String?) ??
          'Partner',
      // The partner's OWN name, kept separate from the couple's
      // chat_name: a typing indicator or reply preview naming the
      // couple puts their shared name in one person's mouth.
      partnerName: (partner?['display_name'] as String?) ?? 'Partner',
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      unreadCount: unreadCount,
      updatedAt: lastMessage?.createdAt ?? DateTime.now(),
      relationshipStatus: status,
      availability: availability,
    );
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

  /// One relationship read plus the partner row and its unread count.
  /// Deliberately NOT the list fetch filtered to one id: the chat header
  /// refresh runs on every relationship change and used to cost
  /// relationships + users + last message + unread RPC + avatar for every
  /// conversation the person has. No preview is fetched (null here; the
  /// list keeps its own). The unread count IS fetched — alongside the
  /// partner row, bounded, 0 on failure — because a chat opened from a push
  /// or the notification inbox (ChatChannelLoader) takes its Conversation
  /// from here, and the "N unread messages" divider is placed from it
  /// before the open marks the chat read (#32b).
  @override
  Future<Conversation?> getConversation(String relationshipId) async {
    final user = _currentUser;
    final relationship =
        await _supabase
            .from('relationships')
            .select(_relationshipColumns)
            .eq('id', relationshipId)
            // RLS already limits relationships to members; filtering here
            // too means a misconfigured policy still never hands a
            // non-member a Conversation.
            .or('user_a.eq.${user.id},user_b.eq.${user.id}')
            .maybeSingle();
    if (relationship == null) return null;
    final partnerId = _partnerIdFor(relationship, user.id);
    if (partnerId == null) return null;
    final unreadCount = _boundedUnreadCount(relationshipId, user.id);
    final usersById = await _loadUsersById([partnerId]);
    return _conversationFromRow(
      relationship,
      partner: usersById[partnerId],
      partnerId: partnerId,
      lastMessage: null,
      unreadCount: await unreadCount,
    );
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
                .order('sort_at', ascending: false)
                .order('id', ascending: false)
                .limit(limit)
            : await _supabase
                .from('messages')
                .select(_messageColumns)
                .eq('relationship_id', relationshipId)
                .or(
                  'sort_at.lt.${before.sortAt.toUtc().toIso8601String()},'
                  'and(sort_at.eq.${before.sortAt.toUtc().toIso8601String()},id.lt.${before.id})',
                )
                .order('sort_at', ascending: false)
                .order('id', ascending: false)
                .limit(limit);

    return _hydrateMessages(rows, user.id, resolveMediaUrls: false);
  }

  @override
  Future<List<Message>> getMessagesAfter(
    String relationshipId, {
    ChatMessageCursor? after,
    int limit = 50,
    int? maxPages,
  }) async {
    final user = _currentUser;
    final collected = <Map<String, dynamic>>[];
    ChatMessageCursor? cursor = after;

    // Page forward until the gap is exhausted so a reconnect after many missed
    // messages restores every row, not just the first page (Spec 6.1, 16).
    // With maxPages the read stops there; the caller continues from its last
    // row (the realtime catch-up pages, and bounds, one page per call).
    for (var page = 0; maxPages == null || page < maxPages; page++) {
      final rows =
          cursor == null
              ? await _supabase
                  .from('messages')
                  .select(_messageColumns)
                  .eq('relationship_id', relationshipId)
                  .order('sort_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit)
              : await _supabase
                  .from('messages')
                  .select(_messageColumns)
                  .eq('relationship_id', relationshipId)
                  .or(
                    'sort_at.gt.${cursor.sortAt.toUtc().toIso8601String()},'
                    'and(sort_at.eq.${cursor.sortAt.toUtc().toIso8601String()},id.gt.${cursor.id})',
                  )
                  .order('sort_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit);

      if (rows.isEmpty) break;
      collected.addAll(rows);
      if (rows.length < limit) break;
      final last = rows.last;
      cursor = ChatMessageCursor(
        sortAt: DateTime.parse(last['sort_at'] as String),
        id: last['id'] as String,
      );
    }

    return _hydrateMessages(collected, user.id, resolveMediaUrls: false);
  }

  @override
  Future<List<Message>> getMessagesByIds(
    String relationshipId,
    List<String> ids,
  ) async {
    final chunks = chunkMessageIds(ids);
    if (chunks.isEmpty) return const [];
    final user = _currentUser;
    final rows = <Map<String, dynamic>>[];
    for (final chunk in chunks) {
      rows.addAll(
        await _supabase
            .from('messages')
            .select(_messageColumns)
            .eq('relationship_id', relationshipId)
            .inFilter('id', chunk),
      );
    }
    return _hydrateMessages(rows, user.id, resolveMediaUrls: false);
  }

  /// Keyset pages on (updated_at, id): the first page is `updated_at >= since`,
  /// every later page continues strictly after the last row's (updated_at,
  /// id). A bulk receipt (`mark_conversation_read` stamping 200 rows in one
  /// transaction) gives hundreds of rows the SAME updated_at; paging on the
  /// timestamp alone would stall or skip there. The merge dedupes by id.
  /// Capped at [ChatRepository.changedSinceMaxPages] pages so a very old
  /// cursor never turns a resume into a history download — the first-page
  /// reconcile covers the rest.
  @override
  Future<List<Message>> getMessagesChangedSince(
    String relationshipId, {
    required DateTime since,
    String? afterId,
    int limit = 50,
  }) async {
    final user = _currentUser;
    // The keyset needs updated_at on every row; _messageColumns carries it
    // (Message.fromRow reads it into serverUpdatedAt).
    const columns = _messageColumns;
    final sinceIso = since.toUtc().toIso8601String();
    // Between internal pages: the server's own ISO text, never a re-parsed
    // DateTime, so the microseconds survive and the boundary row is neither
    // re-served nor skipped. A caller's [afterId] continuation starts on the
    // keyset branch from its (since, afterId); `since` came from a parsed
    // server updated_at, and toUtc().toIso8601String() keeps its
    // microseconds on the VM.
    final collected = await collectChangedSincePages(
      startUpdatedAt: afterId == null ? null : sinceIso,
      startId: afterId,
      limit: limit,
      maxPages: ChatRepository.changedSinceMaxPages,
      pageTimeout: changedSincePageTimeout,
      fetchPage:
          (lastUpdatedAt, lastId) async =>
              lastUpdatedAt == null
              ? await _supabase
                  .from('messages')
                  .select(columns)
                  .eq('relationship_id', relationshipId)
                  .gte('updated_at', sinceIso)
                  .order('updated_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit)
              : await _supabase
                  .from('messages')
                  .select(columns)
                  .eq('relationship_id', relationshipId)
                  // Implied by the OR below, but PostgREST cannot send a row
                  // comparison and Postgres cannot turn the OR into an index
                  // range: without this bound a continuation page walks the
                  // relationship's whole older history before the cursor.
                  .gte('updated_at', lastUpdatedAt)
                  .or(
                    'updated_at.gt.$lastUpdatedAt,'
                    'and(updated_at.eq.$lastUpdatedAt,id.gt.$lastId)',
                  )
                  .order('updated_at', ascending: true)
                  .order('id', ascending: true)
                  .limit(limit),
    );
    return _hydrateMessages(collected, user.id, resolveMediaUrls: false);
  }

  @override
  Future<void> ensureRealtimeConnected() async {
    try {
      if (!_supabase.realtime.isConnected) {
        // connect() is @internal in realtime_client 2.7.x, but it is the same
        // call RealtimeChannel.subscribe makes when the socket is down, and
        // there is no public "connect now". It returns early when a
        // connection attempt already exists; failures are swallowed below.
        // ignore: invalid_use_of_internal_member
        await _supabase.realtime.connect();
      }
    } catch (error) {
      // The socket's own reconnect loop keeps trying; this only hurries it.
      ChatLog.d('[CHAT] realtime connect nudge failed: ${error.runtimeType}');
    }
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
    int? streakViewsRemaining,
    String? storyItemId,
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
              // A story reply's quoted_text is never sent by this client
              // (spec §5.4): validate_message_story_reply_before_insert
              // (20260939010000) overwrites it server-side from the
              // story's media type regardless of what arrives here, so
              // sending our own value would be a silent no-op at best and
              // a misleading implication of client control at worst.
              // Omitting the key entirely when storyItemId is set (rather
              // than sending null) leaves quotedText for an ordinary
              // message reply completely unaffected.
              if (storyItemId == null) 'quoted_text': quotedText,
              'is_view_once': isViewOnce,
              // Omitted for every other type: the column defaults to 1,
              // and writing null would violate its NOT NULL.
              if (streakViewsRemaining != null)
                'streak_views_remaining': streakViewsRemaining,
              if (storyItemId != null) 'story_item_id': storyItemId,
            })
            .select(_messageColumns)
            .single();

    return _hydrateMessage(row, user.id);
  }

  @override
  Future<void> sendScreenshotNotice({
    required String relationshipId,
    required String clientMessageId,
  }) async {
    await _supabase.rpc('send_screenshot_notice', params: {
      'p_relationship_id': relationshipId,
      'p_client_message_id': clientMessageId,
    });
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

  ChatMediaUploader? _uploader;
  ChatMediaUploader get _mediaUploader =>
      _uploader ??= ChatMediaUploader(
        storageUrl: () => _supabase.storage.url,
        headers: _uploadHeaders,
      );

  /// What the SDK's AuthHttpClient adds to every Storage request, done by
  /// hand because the streaming uploader bypasses that client. In supabase
  /// 2.12.1 storage.headers carries neither credential: AuthHttpClient puts
  /// the `apikey` and the person's bearer on each request
  /// (`_getAccessToken`, which also refreshes an expired session). Without
  /// the apikey the gateway refuses the request; without the bearer Storage
  /// RLS sees an anonymous upload (403, which ChatError counts toward the
  /// cap). The apikey is read from the auth client's headers, where the SDK
  /// sets it to the project key.
  Future<Map<String, String>> _uploadHeaders() async {
    final auth = _supabase.auth;
    final apiKey = auth.headers['apikey'];
    if (auth.currentSession?.isExpired ?? false) {
      try {
        await auth.refreshSession();
      } catch (_) {
        // A failed refresh surfaces as a 401 from Storage, which ChatError
        // classifies transient: the row is retried after the SDK's own
        // refresh lands.
      }
    }
    final token = auth.currentSession?.accessToken;
    return {
      ..._supabase.storage.headers,
      if (apiKey != null) 'apikey': apiKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @visibleForTesting
  Future<Map<String, String>> debugUploadHeaders() => _uploadHeaders();

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) {
    return _mediaUploader.upload(
      bucket: intent.bucket,
      objectKey: intent.storageKey,
      localPath: localPath,
      mimeType: mimeType,
      cancelToken: cancelToken,
      onProgress:
          onProgress == null
              ? null
              : (sent, total) => onProgress(total <= 0 ? 1.0 : sent / total),
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
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    return _createSignedStorageUrl(
      bucket: 'message-media',
      storageKey: mediaKey,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<SignedMediaGrant?> createSignedMediaGrant(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    return _createSignedStorageGrant(
      bucket: 'message-media',
      storageKey: mediaKey,
      forceRefresh: forceRefresh,
    );
  }

  /// Same cache/TTL as [createSignedMediaUrl]. Cache entries include the
  /// bucket name so avatar and message objects never collide.
  Future<String?> _createRelationshipAvatarSignedUrl(String storageKey) async {
    return _createSignedStorageUrl(
      bucket: 'relationship-avatars',
      storageKey: storageKey,
    );
  }

  Future<String?> _createSignedStorageUrl({
    required String bucket,
    required String storageKey,
    bool forceRefresh = false,
  }) async {
    final grant = await _createSignedStorageGrant(
      bucket: bucket,
      storageKey: storageKey,
      forceRefresh: forceRefresh,
    );
    return grant?.url;
  }

  /// The cache entry itself — URL plus the moment this cache stops reusing
  /// it — so [createSignedMediaGrant] callers can refresh before expiry.
  Future<SignedMediaGrant?> _createSignedStorageGrant({
    required String bucket,
    required String storageKey,
    bool forceRefresh = false,
  }) async {
    for (final candidate in _storageKeyCandidates(storageKey, bucket)) {
      final cacheKey = '$bucket::$candidate';
      final cached = _signedUrlCache[cacheKey];
      if (!forceRefresh &&
          cached != null &&
          cached.expiresAt.isAfter(DateTime.now())) {
        return cached;
      }
      try {
        final url = await _supabase.storage
            .from(bucket)
            .createSignedUrl(candidate, _signedUrlTtl.inSeconds);
        final entry = (
          url: url,
          expiresAt: DateTime.now().add(_signedUrlTtl - _signedUrlSafetyMargin),
        );
        _signedUrlCache[cacheKey] = entry;
        return entry;
      } catch (_) {
        // Try the next normalized candidate. Older cached rows and a few
        // storage pipelines have used both bucket-prefixed and unprefixed
        // object names; the private bucket/RLS contract is unchanged.
      }
    }
    // A key that is already a URL passes through unsigned; its real expiry
    // is unknown, so it is trusted for one ordinary signing window.
    return storageKey.startsWith('http')
        ? (
          url: storageKey,
          expiresAt: DateTime.now().add(_signedUrlTtl - _signedUrlSafetyMargin),
        )
        : null;
  }

  List<String> _storageKeyCandidates(String storageKey, String bucket) {
    final keys = <String>[];

    void add(String? value) {
      if (value == null || value.isEmpty) return;
      final normalized = Uri.decodeComponent(value).split('?').first;
      if (normalized.isEmpty || keys.contains(normalized)) return;
      keys.add(normalized);
    }

    add(_storageKeyFromUrl(storageKey, bucket));
    add(storageKey);
    if (storageKey.startsWith('$bucket/')) {
      add(storageKey.substring(bucket.length + 1));
    } else {
      add('$bucket/$storageKey');
    }
    return keys;
  }

  String? _storageKeyFromUrl(String value, String bucket) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return null;
    final marker = '/storage/v1/object/';
    final path = uri.path;
    final markerIndex = path.indexOf(marker);
    if (markerIndex == -1) return null;
    final objectPath = path.substring(markerIndex + marker.length);
    for (final prefix in ['sign/$bucket/', 'public/$bucket/']) {
      if (objectPath.startsWith(prefix)) {
        return objectPath.substring(prefix.length);
      }
    }
    return null;
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

  /// Reduces a frame to a [ChatRealtimeEvent] and forwards it. Never throws:
  /// a malformed frame must not take the subscription down.
  void _forwardChange(
    StreamController<ChatRealtimeEvent> events,
    PostgresChangePayload payload,
  ) {
    if (events.isClosed) return;
    try {
      final event = ChatRealtimeEvent.fromPostgresChange(
        table: payload.table,
        eventType: payload.eventType.name,
        newRecord: payload.newRecord,
        oldRecord: payload.oldRecord,
      );
      if (event != null) events.add(event);
    } catch (error) {
      ChatLog.e('realtime frame ignored', error);
    }
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
      () => StreamController<ChatRealtimeEvent>.broadcast(),
    );
    final typing = _typingControllers.putIfAbsent(
      relationshipId,
      () => StreamController<TypingEvent>.broadcast(),
    );

    // The first `subscribed` of this channel answers the open that created
    // it; every later one is a reconnect (see chatResyncEventFor).
    var joinedBefore = false;
    final channel = _supabase
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
          callback: (payload) => _forwardChange(events, payload),
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
          callback: (payload) => _forwardChange(events, payload),
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
          callback: (payload) => _forwardChange(events, payload),
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
          callback: (payload) => _forwardChange(events, payload),
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
        .subscribe((status, error) {
          // A websocket dies when the network drops, and nothing here
          // used to notice: .subscribe() was called with no status
          // callback at all. After the connection returned the channel
          // stayed dead, so no message, receipt, pin or reaction ever
          // arrived again until the screen was rebuilt -- which is why
          // "turn data off, turn it back on" lost messages entirely.
          //
          // On any non-subscribed terminal status, emit one event: the
          // listener's handler refetches, which closes the gap for
          // everything missed while the socket was down. Supabase's
          // client reconnects the socket itself; what it cannot do is
          // tell the app it missed events in the meantime.
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              // The FIRST subscribe is marked initial: the chat that opened
              // the channel has just read everything itself, so it skips
              // those reads (M2). Every resubscribe after a reconnect is a
              // full resync.
              final event = chatResyncEventFor(
                status,
                joinedBefore: joinedBefore,
              );
              joinedBefore = true;
              if (event != null && !events.isClosed) events.add(event);
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.closed:
              ChatLog.d(
                '[CHAT] realtime channel ${status.name} '
                'rel=${ChatLog.shortId(relationshipId)} '
                '${error ?? ''}',
              );
          }
        });

    _channels[relationshipId] = channel;
    return channel;
  }

  @override
  Stream<void> watchInboxEvents(List<String> relationshipIds) {
    if (relationshipIds.isEmpty) return const Stream<void>.empty();

    final controller = StreamController<void>.broadcast();

    // One channel for the inbox, with a filter per relationship. Supabase
    // filters postgres_changes server-side on a single column, and
    // messages has no user column -- so an unfiltered subscription would
    // be the alternative, and that delivers every couple's message
    // traffic to every client for RLS to discard.
    //
    // A user has one relationship today and a small number at most, so
    // the handler count stays tiny.
    var channel = _supabase.channel('inbox:${_currentUser.id}');

    for (final id in relationshipIds) {
      channel = channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'relationship_id',
              value: id,
            ),
            // The payload is ignored: the list refetches, because the
            // preview and unread count are derived from several rows and
            // reproducing that here would be a second, drifting copy.
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'relationships',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: id,
            ),
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          );
    }

    // Same reconnect handling as the per-chat channel: a resubscribe after
    // a dropped network emits one event, and the listener refetches the
    // list -- which is what makes a message sent while the receiver was
    // offline show up in their conversation list on reconnect instead of
    // only when they open the chat.
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed &&
          !controller.isClosed) {
        controller.add(null);
      }
    });

    controller.onCancel = () {
      unawaited(_supabase.removeChannel(channel));
    };

    return controller.stream;
  }

  @override
  Stream<ChatRealtimeEvent> watchConversationEvents(String relationshipId) {
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
  Future<void> markRelationshipDelivered(String relationshipId) async {
    try {
      await _supabase.rpc(
        'mark_relationship_delivered',
        params: {'p_relationship_id': relationshipId},
      );
    } catch (_) {
      // Best-effort: a missed receipt is cosmetic, and the next fetch
      // retries. Never fail a conversation-list load over a tick.
    }
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
  Future<bool> partnerIsActiveInChat(String relationshipId) async {
    try {
      final result = await _supabase.rpc(
        'partner_is_active_in_chat',
        params: {'p_relationship_id': relationshipId},
      );
      return result == true;
    } catch (_) {
      // Absent rather than wrong: a failed read must not claim the
      // partner is present when we do not know.
      return false;
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
    // All three leave the maps before the first await: a chat subscribing
    // again while the old channel is still being removed (a controller
    // rebuilt for another account, M6) must get a new channel AND new
    // streams — it used to pick up the old stream controller, which this
    // then closed under it, leaving the new chat deaf.
    final channel = _channels.remove(relationshipId);
    final events = _eventControllers.remove(relationshipId);
    final typing = _typingControllers.remove(relationshipId);
    if (channel != null) {
      await _supabase.removeChannel(channel);
    }
    if (events != null) {
      await events.close();
    }
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
        .order('sort_at', ascending: false)
        .order('id', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return _hydrateMessage(rows.first, currentUserId);
  }

  /// [_fetchUnreadCount] for an open: never throws, never waits past
  /// [unreadCountTimeout]. A missing count only costs the unread divider.
  Future<int> _boundedUnreadCount(
    String relationshipId,
    String currentUserId,
  ) async {
    try {
      return await _fetchUnreadCount(
        relationshipId,
        currentUserId,
      ).timeout(unreadCountTimeout);
    } catch (error) {
      ChatLog.e('unread count for open failed; opening without it', error);
      return 0;
    }
  }

  Future<int> _fetchUnreadCount(
    String relationshipId,
    String currentUserId,
  ) async {
    // read_at is the recipient's private marker and is not selectable by
    // clients (Spec 1a); the count comes from a SECURITY DEFINER reader.
    final raw = await _supabase.rpc(
      'count_unread_messages',
      params: {'p_relationship_id': relationshipId},
    );
    return parseUnreadCount(raw);
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
    String currentUserId, {
    bool resolveMediaUrls = true,
  }) async {
    final messageIds = rows.map((row) => row['id'] as String).toList();
    final reactionsByMessageId = await _fetchReactionsFor(messageIds);

    return Future.wait(
      rows.map((row) async {
        var base = Message.fromRow(row, currentUserId: currentUserId);
        final reactions = reactionsByMessageId[base.id];
        if (reactions != null) {
          base = base.copyWith(reactions: reactions);
        }
        // Chat bubbles resolve storage keys lazily and reserve media geometry
        // from the row. Holding a whole page behind signed-URL round trips
        // makes unrelated text messages wait for media they do not need.
        if (!resolveMediaUrls) return base;
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
        // An ephemeral (view-once) video must never resurface in this
        // persistent, replayable gallery — viewed or not, that defeats the
        // entire point of view-once. It keeps its own separate
        // EphemeralVideoViewerScreen flow, reached only from its chat
        // bubble. mediaType == 'video' is the only case this can ever
        // matter for (images/audio have no is_view_once concept today),
        // but the filter is unconditional since is_view_once is false for
        // every other media type's rows anyway.
        .eq('is_view_once', false)
        .order('sort_at', ascending: false)
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
        // Trails repeat the game's name at every move; only the card should
        // match. `.or` with `is.null` keeps plain-text rows (NULL media_type),
        // which a bare `.neq` would silently drop.
        .or('media_type.is.null,media_type.neq.game_trail')
        // A deleted message's content is gone (delete_message RPC clears
        // it) — excluded here since there is nothing to show/highlight in
        // a search result for a tombstoned message.
        .isFilter('deleted_at', null)
        .order('sort_at', ascending: false)
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
