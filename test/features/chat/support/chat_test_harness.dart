import 'dart:async';

import 'package:clock/clock.dart';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend_base.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend_stub.dart'
    as stub;
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart'
    show maxMessageIdsPerRequest;
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:file/file.dart' as file_system;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_voice_engine.dart';

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

/// Keeps controller tests off DefaultCacheManager's platform channels.
/// Tests that exercise cache promotion/prewarming override the provider with
/// their own functional cache manager; every other controller test only needs
/// the optional accelerator to fail quietly and deterministically.
class _NoPlatformChatCacheManager implements BaseCacheManager {
  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  Future<file_system.File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) => Future<file_system.File>.error(
    UnsupportedError('No platform cache in controller tests'),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

/// Records what the chat asked the photo/poster store to drop (I3), instead
/// of DefaultCacheManager's platform channels.
class FakeChatImageCache implements ChatImageCache {
  final List<Set<String>> removals = [];
  int clears = 0;

  Set<String> get removedKeys => {for (final keys in removals) ...keys};

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> removeKeys(Iterable<String> keys) async {
    final set = {for (final key in keys) if (key.isNotEmpty) key};
    if (set.isNotEmpty) removals.add(set);
  }
}

/// Captures exactly what one [FakeChatRepository.sendTextMessage] call
/// received, for tests that need to assert on the CALL rather than the
/// response row (e.g. proving quotedText was never sent for a story
/// reply — Task 6/spec §5.4).
class SentTextMessageArgs {
  const SentTextMessageArgs({
    required this.relationshipId,
    required this.senderId,
    required this.clientMessageId,
    required this.content,
    this.replyToMessageId,
    this.quotedText,
    this.storyItemId,
  });

  final String relationshipId;
  final String senderId;
  final String clientMessageId;
  final String content;
  final String? replyToMessageId;
  final String? quotedText;
  final String? storyItemId;
}

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

  /// Calls to [sendScreenshotNotice] (the send_screenshot_notice RPC).
  int screenshotNoticeCalls = 0;

  /// The exact arguments the most recent [sendTextMessage] call received —
  /// lets a test assert on what was actually SENT (e.g. that quotedText
  /// was withheld for a story reply, Task 6/spec §5.4), not just on what
  /// the fake echoes back in its response row.
  SentTextMessageArgs? lastSendArgs;

  // --- Scripting seams for the W1a delivery/sync plan. ---

  /// Errors thrown by successive [sendTextMessage] calls, FIFO, consulted
  /// before [nextSendError]. Lets a test script "fails N times, then works".
  final List<Object> sendErrorQueue = [];

  /// Content of every send the fake server accepted, in acceptance order.
  final List<String> sentContents = [];

  /// The media / poster keys of every insert ATTEMPT (accepted or not), in
  /// call order.
  final List<String?> sentMediaKeys = [];
  final List<String?> sentThumbnailKeys = [];

  /// Models the server's insert trigger (validate_message_media_before_
  /// insert): returns the error to throw for these keys, or null to accept.
  Object? Function(String? mediaKey, String? thumbnailKey)? insertGuard;

  /// When true a committed insert marks its keys' intents used, as the real
  /// trigger does (used_at), so a retry carrying them is refused as stale.
  bool consumeIntentsOnCommit = false;
  final Set<String> _usedIntentKeys = {};

  /// One-shot: the next insert COMMITS, then this is thrown instead of the
  /// answer (a reply lost on the way back, e.g. the client's bound).
  Object? errorAfterCommit;

  /// When true each upload intent gets its own key (`chat-media/intent-N`,
  /// N = the media call number), so a test can tell a fresh intent from a
  /// reused one. Off by default: older tests expect the one fixed key.
  bool uniqueIntentKeys = false;

  /// Per-call response gates for [sendTextMessage], FIFO: the call commits
  /// its row, then waits on the next gate before answering. A gate never
  /// completed is an insert the server took whose answer was lost.
  final List<Completer<void>> sendResponseGates = [];

  /// When true, a send whose (sender, client_message_id) the server already
  /// holds raises 23505, as messages' unique constraint does.
  bool enforceUniqueClientId = false;

  /// One-shot error for [findMessageByClientId]: a lost response while
  /// reconciling a 23505 duplicate.
  Object? findMessageError;
  int findMessageCalls = 0;

  /// When set, [getConversation] throws it (header metadata unreachable).
  Object? getConversationError;

  /// When set, [getPinnedMessages] throws it.
  Object? getPinnedError;

  /// When set, [getPinnedMessages] waits on it before reading, so a test can
  /// land a purge while a pins refresh is in flight.
  Completer<void>? getPinnedGate;

  /// When set, every [getMessages] page read throws it.
  Object? getMessagesError;

  /// Ids [getMessagesByIds] still returns but list pages ([getMessages])
  /// never do — a row the list query filters. Paging still advances past it.
  final Set<String> hiddenFromPages = {};

  int getConversationCalls = 0;
  int getMessagesCalls = 0;
  int getMessagesAfterCalls = 0;
  int getPinnedCalls = 0;
  int getMessagesByIdsCalls = 0;
  int ensureRealtimeConnectedCalls = 0;

  /// The `since` the controller last asked [getMessagesChangedSince] for.
  DateTime? lastChangedSinceArg;
  String? lastChangedSinceAfterIdArg;
  int changedSinceCalls = 0;

  /// When set, [getMessagesChangedSince] waits on it before reading, so a
  /// test can land a purge while a sync is in flight.
  Completer<void>? getMessagesChangedSinceGate;

  /// How long each internal page of a [getMessagesChangedSince] call takes
  /// (a slow link); zero by default.
  Duration changedSincePageDelay = Duration.zero;

  /// Errors thrown by the Nth [getMessagesChangedSince] call, keyed by the
  /// value [changedSinceCalls] has once that call is counted.
  final Map<int, Object> changedSinceErrorsByCall = {};

  /// When set, [getMessagesAfter] / [getMessagesByIds] wait on it before
  /// reading, so a test can land a purge while the read is in flight.
  Completer<void>? getMessagesAfterGate;
  Completer<void>? getMessagesByIdsGate;

  /// When set, [getMessagesAfter] throws it (after its gate, if any): a
  /// catch-up that fails while other reads work.
  Object? getMessagesAfterError;

  /// When set, [getMessagesByIds] throws it (after its gate, if any).
  Object? getMessagesByIdsError;

  /// How long each internal page of a [getMessagesAfter] read takes (a slow
  /// link); zero by default. The real read pages forward until a short page
  /// (or its `maxPages`), so a big gap is many pages.
  Duration afterPageDelay = Duration.zero;

  /// The `maxPages` the controller last passed to [getMessagesAfter].
  int? lastAfterMaxPagesArg;

  /// How long each request of a [getMessagesByIds] read takes (a slow link);
  /// zero by default. Like the real read: one request per id chunk, plus the
  /// reactions read that hydrates them.
  Duration byIdsRequestDelay = Duration.zero;

  /// Server-side updated_at per message id (migration 20261019100000).
  /// Seeds default to their created_at; every mutation stamps now().
  final Map<String, DateTime> serverUpdatedAt = {};

  void touch(String id, [DateTime? at]) =>
      serverUpdatedAt[id] = at ?? DateTime.now();

  /// A row as a read returns it: like SupabaseChatRepository, every message
  /// read selects `updated_at` (final-review M7).
  Message _served(Message m) =>
      m.copyWith(serverUpdatedAt: serverUpdatedAt[m.id] ?? m.createdAt);

  /// When set, the next send throws this instead of succeeding. Cleared after
  /// one use so a retry can succeed.
  Object? nextSendError;

  /// Thrown once by the next [sendScreenshotNotice] call.
  Object? nextScreenshotNoticeError;

  /// When set, [sendScreenshotNotice] waits on it before answering — a
  /// never-completed gate models an RPC whose response never arrives.
  Completer<void>? screenshotNoticeGate;

  /// Optional artificial latency on send so tests can observe the optimistic
  /// (sending) window before the server acknowledges.
  Duration sendDelay = Duration.zero;
  Duration sendCreatedAtOffset = Duration.zero;

  /// Optional gates for proving cache-first publication independently of a
  /// still-pending network refresh.
  Completer<void>? getMessagesGate;

  /// Holds a page the fake has already computed, so a test can make a write
  /// land AFTER the server built the response but BEFORE the client saw it.
  Completer<void>? getMessagesResponseGate;
  Completer<void>? getConversationGate;

  /// When true, a send raises a 23505 duplicate and the canonical row is
  /// already present under [duplicateClientMessageId].
  bool simulateDuplicate = false;
  String? duplicateClientMessageId;

  final _events = StreamController<ChatRealtimeEvent>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final List<({bool typing})> sentTyping = [];

  /// What [getConversation] returns on refresh. Defaults to an active
  /// conversation; set to a read-only/archived one to test those lifecycles.
  Conversation? conversationOverride;

  /// Pushes a realtime frame to subscribers. Defaults to the `resync` frame a
  /// (re)subscribe emits, which is what every pre-W1a test meant by "a
  /// realtime event".
  void emitRealtime([
    ChatRealtimeEvent event = const ChatRealtimeEvent.resync(),
  ]) => _events.add(event);

  /// Seeds a canonical row as if another member sent it.
  Message seedIncoming({
    required String id,
    required String relationshipId,
    required String senderId,
    required String content,
    required DateTime createdAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    String? mediaType,
    int? streakViewsRemaining,
    DateTime? deletedAt,
    String messageOrigin = 'user',
    DateTime? editedAt,
    String? replyToMessageId,
    String? quotedText,
    DateTime? sortAt,
    String? gameSessionId,
  }) {
    final row = {
      'id': id,
      'relationship_id': relationshipId,
      'sender_id': senderId,
      'client_message_id': 'seed-$id',
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
      'delivered_at': deliveredAt?.toUtc().toIso8601String(),
      'read_receipt_at': readAt?.toUtc().toIso8601String(),
      // Game cards and trails carry no media.
      'media_url':
          mediaType == null || mediaType == 'game' || mediaType == 'game_trail'
              ? null
              : 'https://example.com/m.mp4',
      'media_type': mediaType,
      'streak_views_remaining': streakViewsRemaining,
      'source': 'native',
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
      'message_origin': messageOrigin,
      'edited_at': editedAt?.toUtc().toIso8601String(),
      'reply_to_message_id': replyToMessageId,
      'quoted_text': quotedText,
      // Games: a moved card keeps its id/created_at and advances sort_at.
      'sort_at': (sortAt ?? createdAt).toUtc().toIso8601String(),
      'game_session_id': gameSessionId,
    };
    final message = Message.fromRow(row, currentUserId: currentUserId);
    serverMessages[id] = message;
    serverUpdatedAt[id] = createdAt;
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
    int? streakViewsRemaining,
    String? storyItemId,
  }) async {
    sendCallCount++;
    lastSendArgs = SentTextMessageArgs(
      relationshipId: relationshipId,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: content,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
      storyItemId: storyItemId,
    );
    sentMediaKeys.add(mediaKey);
    sentThumbnailKeys.add(mediaThumbnailKey);
    if (sendDelay > Duration.zero) await Future<void>.delayed(sendDelay);

    final refusal = insertGuard?.call(mediaKey, mediaThumbnailKey);
    if (refusal != null) throw refusal;

    // The real trigger runs BEFORE INSERT, ahead of the client_message_id
    // unique index: a key whose intent a committed insert already used is
    // refused as stale, never answered with 23505.
    if (consumeIntentsOnCommit &&
        ((mediaKey != null && _usedIntentKeys.contains(mediaKey)) ||
            (mediaThumbnailKey != null &&
                _usedIntentKeys.contains(mediaThumbnailKey)))) {
      throw const PostgrestException(
        message: 'Chat media upload intent is invalid or expired',
        code: 'P0001',
      );
    }

    if (simulateDuplicate) {
      throw const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
    }

    if (sendErrorQueue.isNotEmpty) {
      throw sendErrorQueue.removeAt(0);
    }

    final error = nextSendError;
    if (error != null) {
      nextSendError = null;
      throw error;
    }

    if (enforceUniqueClientId &&
        serverMessages.values.any(
          (m) => m.senderId == senderId && m.clientMessageId == clientMessageId,
        )) {
      throw const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
    }

    // Mirrors validate_message_story_reply_before_insert
    // (20260939010000_story_replies.sql): when a story is quoted, the
    // client's own quotedText is discarded and the server normalizes it
    // from the story's media type. A test wanting the "story unavailable"
    // refusal path sets nextSendError instead of relying on this fake to
    // model the trigger's lookup — that refusal is a real Postgres
    // decision this in-memory fake cannot reproduce.
    final effectiveQuotedText =
        storyItemId == null
            ? quotedText
            : (storyReplyMediaType == 'video' ? 'Video story' : 'Photo story');

    final id = 'srv-$clientMessageId';
    final row = {
      'id': id,
      'relationship_id': relationshipId,
      'sender_id': senderId,
      'client_message_id': clientMessageId,
      'content': content,
      'created_at':
          DateTime.now().add(sendCreatedAtOffset).toUtc().toIso8601String(),
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
      'quoted_text': effectiveQuotedText,
      'story_item_id': storyItemId,
      'is_view_once': isViewOnce,
      'is_system_notice': false,
      'streak_views_remaining': streakViewsRemaining,
    };
    final message = Message.fromRow(row, currentUserId: currentUserId);
    serverMessages[id] = message;
    sentContents.add(content);
    touch(id);
    if (consumeIntentsOnCommit) {
      if (mediaKey != null) _usedIntentKeys.add(mediaKey);
      if (mediaThumbnailKey != null) _usedIntentKeys.add(mediaThumbnailKey);
    }
    final lost = errorAfterCommit;
    if (lost != null) {
      // Committed; the answer never reaches the client.
      errorAfterCommit = null;
      throw lost;
    }
    if (sendResponseGates.isNotEmpty) {
      await sendResponseGates.removeAt(0).future;
    }
    return message;
  }

  /// Set before calling sendTextMessage with a storyItemId to control
  /// which server-normalized quotedText the fake produces ('image' or
  /// 'video' — defaults to the photo case). Mirrors the real trigger's
  /// CASE on story_items.media_type.
  String storyReplyMediaType = 'image';

  @override
  Future<void> sendScreenshotNotice({
    required String relationshipId,
    required String clientMessageId,
  }) async {
    screenshotNoticeCalls++;
    final failure = nextScreenshotNoticeError;
    if (failure != null) {
      nextScreenshotNoticeError = null;
      throw failure;
    }
    final gate = screenshotNoticeGate;
    if (gate != null) await gate.future;
    final id = 'srv-$clientMessageId';
    if (serverMessages.containsKey(id)) return; // idempotent, like the RPC
    serverMessages[id] = Message.fromRow({
      'id': id,
      'relationship_id': relationshipId,
      'sender_id': currentUserId,
      'client_message_id': clientMessageId,
      'content': 'Someone took a screenshot',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'native',
      'is_system_notice': true,
    }, currentUserId: currentUserId);
    touch(id);
  }

  @override
  Future<Message?> findMessageByClientId({
    required String senderId,
    required String clientMessageId,
  }) async {
    findMessageCalls++;
    final findError = findMessageError;
    if (findError != null) {
      findMessageError = null;
      throw findError;
    }
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
    getMessagesCalls++;
    final gate = getMessagesGate;
    if (gate != null) await gate.future;
    final error = getMessagesError;
    if (error != null) throw error;
    final all =
        serverMessages.values
            .where((m) => m.relationshipId == relationshipId)
            .where((m) => !hiddenFromPages.contains(m.id))
            .toList()
          ..sort((a, b) {
            final t = b.sortAt.compareTo(a.sortAt);
            return t != 0 ? t : b.id.compareTo(a.id);
          });
    final page =
        before == null
            ? all.take(limit).toList()
            : all
                .where((m) => m.sortAt.isBefore(before.sortAt))
                .take(limit)
                .toList();
    final responseGate = getMessagesResponseGate;
    if (responseGate != null) await responseGate.future;
    return page.map(_served).toList();
  }

  @override
  Future<List<Message>> getMessagesAfter(
    String relationshipId, {
    ChatMessageCursor? after,
    int limit = 50,
    int? maxPages,
  }) async {
    getMessagesAfterCalls++;
    lastAfterMaxPagesArg = maxPages;
    final afterGate = getMessagesAfterGate;
    if (afterGate != null) await afterGate.future;
    final afterError = getMessagesAfterError;
    if (afterError != null) throw afterError;
    final all =
        serverMessages.values
            .where((m) => m.relationshipId == relationshipId)
            .toList()
          ..sort((a, b) {
            final t = a.sortAt.compareTo(b.sortAt);
            return t != 0 ? t : a.id.compareTo(b.id);
          });
    if (after == null) return all.take(limit).map(_served).toList();
    // (sort_at, id) keyset, strictly after the cursor, like the real read.
    final newer =
        all
            .where(
              (m) =>
                  m.sortAt.isAfter(after.sortAt) ||
                  (m.sortAt.isAtSameMomentAs(after.sortAt) &&
                      m.id.compareTo(after.id) > 0),
            )
            .toList();
    final rows =
        maxPages == null ? newer : newer.take(limit * maxPages).toList();
    if (afterPageDelay > Duration.zero) {
      // Pages until a short one: a full last page costs one more (empty) read.
      var pages = rows.length ~/ limit + 1;
      if (maxPages != null && pages > maxPages) pages = maxPages;
      await Future<void>.delayed(afterPageDelay * pages);
    }
    return rows.map(_served).toList();
  }

  @override
  Future<List<Message>> getMessagesByIds(
    String relationshipId,
    List<String> ids,
  ) async {
    getMessagesByIdsCalls++;
    final byIdsGate = getMessagesByIdsGate;
    if (byIdsGate != null) await byIdsGate.future;
    final byIdsError = getMessagesByIdsError;
    if (byIdsError != null) throw byIdsError;
    if (byIdsRequestDelay > Duration.zero) {
      final unique = ids.toSet().length;
      final chunks =
          (unique + maxMessageIdsPerRequest - 1) ~/ maxMessageIdsPerRequest;
      await Future<void>.delayed(byIdsRequestDelay * (chunks + 1));
    }
    return [
      for (final id in ids)
        if (serverMessages[id] case final m?
            when m.relationshipId == relationshipId)
          _served(m),
    ];
  }

  @override
  Future<List<Message>> getMessagesChangedSince(
    String relationshipId, {
    required DateTime since,
    String? afterId,
    int limit = 50,
  }) async {
    lastChangedSinceArg = since;
    lastChangedSinceAfterIdArg = afterId;
    changedSinceCalls++;
    final gate = getMessagesChangedSinceGate;
    if (gate != null) await gate.future;
    final scripted = changedSinceErrorsByCall[changedSinceCalls];
    if (scripted != null) throw scripted;
    DateTime at(Message m) => serverUpdatedAt[m.id] ?? m.createdAt;
    Future<void> pagesTook(int rows) async {
      if (changedSincePageDelay == Duration.zero) return;
      // The real call reads page after page until a short one or the cap.
      final pages = (rows ~/ limit + 1).clamp(
        1,
        ChatRepository.changedSinceMaxPages,
      );
      await Future<void>.delayed(changedSincePageDelay * pages);
    }
    final changed =
        serverMessages.values.where((m) {
            if (m.relationshipId != relationshipId) return false;
            final t = at(m);
            if (afterId == null) return !t.isBefore(since);
            // Keyset continuation: strictly after (since, afterId).
            return t.isAfter(since) ||
                (t.isAtSameMomentAs(since) && m.id.compareTo(afterId) > 0);
          }).toList()
          ..sort((a, b) {
            final byTime = at(a).compareTo(at(b));
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    await pagesTook(changed.length);
    // Mirrors SupabaseChatRepository: the row carries its server updated_at,
    // and one call returns at most ChatRepository.changedSinceMaxPages pages.
    return [
      for (final m in changed.take(
        limit * ChatRepository.changedSinceMaxPages,
      ))
        m.copyWith(serverUpdatedAt: serverUpdatedAt[m.id] ?? m.createdAt),
    ];
  }

  @override
  Future<void> ensureRealtimeConnected() async {
    ensureRealtimeConnectedCalls++;
  }

  /// When set, [markDelivered] throws it (after recording the call).
  Object? markDeliveredError;

  @override
  Future<void> markDelivered(List<String> messageIds) async {
    markDeliveredCalls.add(messageIds);
    final error = markDeliveredError;
    if (error != null) throw error;
  }

  /// Relationships the list reported as delivered.
  final relationshipDeliveredCalls = <String>[];

  @override
  Future<void> markRelationshipDelivered(String relationshipId) async {
    relationshipDeliveredCalls.add(relationshipId);
  }

  @override
  Future<void> markConversationRead(String relationshipId) async {
    markReadCalls.add(relationshipId);
  }

  @override
  Future<void> setPresence(String? relationshipId) async {
    presenceCalls.add(relationshipId);
  }

  /// Whether the fake partner is in the chat. Settable so a test can
  /// drive the "Active in this chat" indicator both ways.
  bool partnerActive = false;

  @override
  Future<bool> partnerIsActiveInChat(String relationshipId) async {
    return partnerActive;
  }

  /// Drives the conversation list's realtime refresh in tests.
  final inboxEvents = StreamController<void>.broadcast();

  /// The ids the notifier subscribed with, so a test can assert it
  /// subscribed at all and to the right relationships.
  final inboxSubscriptions = <List<String>>[];

  @override
  Stream<void> watchInboxEvents(List<String> relationshipIds) {
    inboxSubscriptions.add(relationshipIds);
    return inboxEvents.stream;
  }

  @override
  Stream<ChatRealtimeEvent> watchConversationEvents(String relationshipId) =>
      _events.stream;

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
    final gate = getConversationGate;
    if (gate != null) await gate.future;
    getConversationCalls++;
    final error = getConversationError;
    if (error != null) throw error;
    if (returnNullConversation) return null;
    final base = conversationOverride ?? activeConversation(relationshipId);
    return base.copyWith();
  }

  /// Makes [getConversation] answer null (the relationship is gone).
  bool returnNullConversation = false;

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
  /// What the conversation list fetches. Mutable so a test can change it
  /// between refreshes and assert the list actually re-read it.
  List<Conversation> conversations = const [];
  int getConversationsCalls = 0;

  /// Per-call gates for [getConversations], FIFO: each call takes the next
  /// one (if any) and waits on it, then reads [conversations].
  final List<Completer<void>> getConversationsGates = [];

  /// When set, [getConversations] throws it.
  Object? getConversationsError;

  @override
  Future<List<Conversation>> getConversations() async {
    getConversationsCalls++;
    if (getConversationsGates.isNotEmpty) {
      await getConversationsGates.removeAt(0).future;
    }
    final error = getConversationsError;
    if (error != null) throw error;
    return conversations;
  }

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

  /// Per-call gates, numbered like [mediaCallFailures]: that call waits on
  /// its gate (a gate never completed is a request the network black-holed,
  /// e.g. only the poster's intent).
  final Map<int, Completer<void>> mediaCallGates = {};
  int _mediaCallCount = 0;
  int get mediaCallCount => _mediaCallCount;

  @override
  Future<ChatMediaUploadIntent> createMediaUploadIntent({
    required String relationshipId,
    required String mimeType,
    required String mediaType,
  }) async {
    _mediaCallCount++;
    final call = _mediaCallCount;
    final gate = intentGate;
    if (gate != null) await gate.future;
    final callGate = mediaCallGates[call];
    if (callGate != null) await callGate.future;
    final failure = mediaCallFailures[call];
    if (failure != null) throw failure;
    return ChatMediaUploadIntent(
      intentId: 'intent',
      storageKey:
          uniqueIntentKeys ? 'chat-media/intent-$call' : 'chat-media/test.jpg',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      bucket: 'message-media',
    );
  }

  /// When set, every [createMediaUploadIntent] waits on it: a slow intent
  /// request, so a test can act while the upload slot is being requested.
  Completer<void>? intentGate;

  /// Progress fractions emitted (in order) before an upload completes or
  /// throws its scripted [mediaCallFailures] entry.
  List<double> uploadProgressScript = const [];

  /// When set, the upload waits on it (mid-flight) before completing; if the
  /// token was cancelled while waiting the upload throws ChatUploadCancelled.
  Completer<void>? uploadGate;
  ChatUploadCancelToken? lastUploadCancelToken;

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    _mediaCallCount++;
    final call = _mediaCallCount;
    lastUploadCancelToken = cancelToken;
    final gate = uploadChatMediaGate;
    if (gate != null) await gate.future;
    final callGate = mediaCallGates[call];
    if (callGate != null) await callGate.future;
    // Progress first, then any scripted failure: an upload that dies part
    // way leaves its ring where the bytes stopped.
    for (final fraction in uploadProgressScript) {
      onProgress?.call(fraction);
    }
    final failure = mediaCallFailures[call];
    if (failure != null) throw failure;
    final midFlight = uploadGate;
    if (midFlight != null) {
      await midFlight.future;
      if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
    }
  }

  /// When set, every [uploadChatMedia] waits on it: a slow upload, so a test
  /// can send texts while a media upload is still in progress.
  Completer<void>? uploadChatMediaGate;

  /// How many leading [createSignedMediaUrl] calls return null before the
  /// normal [signMediaUrls] behaviour applies — models "offline once, then
  /// back" for the signed-URL retry tests.
  int signMediaUrlFailuresBeforeSuccess = 0;

  /// When set, every signing call waits on it: a slow sign, so a test can
  /// dispose the caller's provider while the request is in flight.
  Completer<void>? signMediaUrlGate;

  @override
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    final grant = await createSignedMediaGrant(
      mediaKey,
      forceRefresh: forceRefresh,
    );
    return grant?.url;
  }

  @override
  Future<SignedMediaGrant?> createSignedMediaGrant(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    signedUrlRequests.add(mediaKey);
    signedUrlForceRefreshes.add(forceRefresh);
    final gate = signMediaUrlGate;
    if (gate != null) await gate.future;
    if (signMediaUrlFailuresBeforeSuccess > 0) {
      signMediaUrlFailuresBeforeSuccess--;
      return null;
    }
    // Null by default preserves the behaviour every existing test was
    // written against (no URL resolves); tests that need a real one opt in
    // via [signMediaUrls].
    if (!signMediaUrls) return null;
    final cacheHit = cachedSignedUrlLifetime;
    final lifetime =
        (!forceRefresh && cacheHit != null) ? cacheHit : signedUrlLifetime;
    return (
      url: 'https://signed.test/$mediaKey?token=abc',
      expiresAt: clock.now().add(lifetime),
    );
  }

  /// How long a fresh fake signed URL is trusted — the real repository's
  /// 10-minute token less its 60 s safety margin.
  Duration signedUrlLifetime = const Duration(minutes: 9);

  /// When set, a non-forced sign returns an entry with only this long left,
  /// as the real repository's cache does near the end of an entry's life.
  Duration? cachedSignedUrlLifetime;

  /// The forceRefresh flag of every signing call, in call order.
  final List<bool> signedUrlForceRefreshes = [];

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

  /// Prior versions per message id, oldest first — what the edit-history
  /// sheet renders. Empty by default, matching a never-edited message.
  final Map<String, List<MessageEditHistoryEntry>> editHistory = {};
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
    touch(messageId);
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
    touch(messageId);
  }

  @override
  Future<List<MessageEditHistoryEntry>> getMessageEditHistory(
    String messageId,
  ) async => editHistory[messageId] ?? const [];

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
    touch(messageId);
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
    touch(messageId);
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
  Future<List<Message>> getPinnedMessages(String relationshipId) async {
    getPinnedCalls++;
    final gate = getPinnedGate;
    if (gate != null) await gate.future;
    final error = getPinnedError;
    if (error != null) throw error;
    return serverMessages.values
        .where(
          (m) =>
              m.relationshipId == relationshipId &&
              pinnedMessageIds.contains(m.id),
        )
        .toList();
  }
}

/// An in-memory cache backend for tests (no platform storage).
ChatCacheBackend memBackend() => stub.createBackend();

/// An in-memory backend whose outbox reads and writes a test can hold or
/// fail, to model a slow or broken local cache.
class ScriptedCacheBackend implements ChatCacheBackend {
  ScriptedCacheBackend() : _inner = stub.createBackend();
  final ChatCacheBackend _inner;

  /// When set, every putOutbox WRITES, then waits on it before returning
  /// (the row is on disk; the caller has not seen the write finish).
  Completer<void>? putOutboxGate;

  /// Fails a putOutbox when this returns true for (client id, n), where n
  /// counts that client id's puts from 1.
  bool Function(String clientMessageId, int ordinal)? failPutOutbox;
  final Map<String, int> _putOrdinals = {};

  /// Fails the readOutbox calls whose number (counting from the moment it
  /// is set, from 1) this returns true for.
  bool Function(int call)? failReadOutbox;
  int _readCalls = 0;

  /// Every readOutbox call, failed or not, since the backend was built.
  int readOutboxCalls = 0;

  /// When true, every writeMessages throws (a disk cache failing at runtime).
  bool failWriteMessages = false;

  /// One-shot: the next readOutbox waits on it (e.g. to hold a purge, whose
  /// first step reads the queue). Cleared when taken.
  Completer<void>? readOutboxGate;
  void armReadOutboxFailures(bool Function(int call) when) {
    _readCalls = 0;
    failReadOutbox = when;
  }

  @override
  Future<void> putOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
    String payload,
    int createdAtMillis,
  ) async {
    final ordinal = _putOrdinals[clientMessageId] =
        (_putOrdinals[clientMessageId] ?? 0) + 1;
    if (failPutOutbox?.call(clientMessageId, ordinal) ?? false) {
      throw StateError('outbox write failed (scripted)');
    }
    await _inner.putOutbox(
      userId,
      relationshipId,
      clientMessageId,
      payload,
      createdAtMillis,
    );
    final gate = putOutboxGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<List<String>> readOutbox(
    String userId, {
    String? relationshipId,
  }) async {
    readOutboxCalls++;
    final gate = readOutboxGate;
    if (gate != null) {
      readOutboxGate = null;
      await gate.future;
    }
    final when = failReadOutbox;
    if (when != null && when(++_readCalls)) {
      throw StateError('outbox read failed (scripted)');
    }
    return _inner.readOutbox(userId, relationshipId: relationshipId);
  }

  @override
  Future<void> init() => _inner.init();
  @override
  Future<void> reset() => _inner.reset();
  @override
  Future<void> requestWipeOnNextOpen() => _inner.requestWipeOnNextOpen();
  @override
  Future<String?> readMessages(String userId, String relationshipId) =>
      _inner.readMessages(userId, relationshipId);
  @override
  Future<void> writeMessages(
    String userId,
    String relationshipId,
    String payload,
  ) async {
    if (failWriteMessages) {
      throw StateError('history write failed (scripted)');
    }
    await _inner.writeMessages(userId, relationshipId, payload);
  }
  @override
  Future<void> deleteMessages(String userId, String relationshipId) =>
      _inner.deleteMessages(userId, relationshipId);
  @override
  Future<String?> readConversations(String userId) =>
      _inner.readConversations(userId);
  @override
  Future<void> writeConversations(String userId, String payload) =>
      _inner.writeConversations(userId, payload);
  @override
  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) => _inner.removeOutbox(userId, relationshipId, clientMessageId);
  @override
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
    String userId,
    int limit,
  ) => _inner.oldestOutbox(userId, limit);
  @override
  Future<void> purgeOutboxForRelationship(
    String userId,
    String relationshipId,
  ) => _inner.purgeOutboxForRelationship(userId, relationshipId);
  @override
  Future<String?> readDraft(String userId, String relationshipId) =>
      _inner.readDraft(userId, relationshipId);
  @override
  Future<void> writeDraft(String userId, String relationshipId, String draft) =>
      _inner.writeDraft(userId, relationshipId, draft);
  @override
  Future<void> clearDraft(String userId, String relationshipId) =>
      _inner.clearDraft(userId, relationshipId);
  @override
  Future<({int micros, String? id})?> readSyncCursor(
    String userId,
    String relationshipId,
  ) => _inner.readSyncCursor(userId, relationshipId);
  @override
  Future<void> writeSyncCursor(
    String userId,
    String relationshipId,
    int micros,
    String? id,
  ) => _inner.writeSyncCursor(userId, relationshipId, micros, id);
  @override
  Future<void> clearSyncCursor(String userId, String relationshipId) =>
      _inner.clearSyncCursor(userId, relationshipId);
  @override
  Future<void> clearAll() => _inner.clearAll();
}

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
  ChatCacheService? cache,
  List<Override> extraOverrides = const [],
  Stream<bool>? connectivity,
  StateProvider<User?>? userSwitch,
}) {
  final effectiveCache =
      cache ?? ChatCacheService.forTesting(backend: stub.createBackend());
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
      chatCacheServiceProvider.overrideWithValue(effectiveCache),
      chatPosterPrewarmerProvider.overrideWith(
        (ref) => ChatPosterPrewarmer(
          repository: repository,
          cacheManager: _NoPlatformChatCacheManager(),
        ),
      ),
      // No platform cache in controller tests; voice/video fall back to the
      // URL when fetch throws, which is the production fallback too.
      chatMediaCacheProvider.overrideWith(
        (ref) => ChatMediaCache(manager: _NoPlatformChatCacheManager()),
      ),
      // Photos/posters (I3): a recording fake, read back by tests through
      // `container.read(chatImageCacheProvider) as FakeChatImageCache`.
      chatImageCacheProvider.overrideWith((ref) => FakeChatImageCache()),
      // One fake voice engine per container: ChatScreen touches the
      // playback controller on init, and a real AudioPlayer has no
      // platform channel here (Wave 2 #21).
      voicePlaybackEngineProvider.overrideWith((ref) => FakeVoiceEngine()),
      // The voice note borrows/returns the audio session (#40); the real
      // port is a platform channel, absent here.
      audioSessionProvider.overrideWith(
        (ref) => AudioSessionCoordinator(port: FakeAudioSessionPort()),
      ),
      // [userSwitch] lets a test sign a different account in mid-test (the
      // controller's account-change listener then runs for real).
      if (userSwitch == null)
        currentUserProvider.overrideWithValue(testUser(userId))
      else
        currentUserProvider.overrideWith((ref) => ref.watch(userSwitch)),
      // _MessageList reads chatExpressivenessProvider to modulate the
      // first-of-day shimmer and reconnect cascade. Override it with a fake
      // notifier (calm default, matching production's default) so tests
      // don't need an async SharedPreferences.getInstance() just to render.
      chatExpressivenessProvider.overrideWith(
        (ref) => ChatFeelPreferenceNotifier.forTesting(),
      ),
      messageSoundsEnabledProvider.overrideWith(
        (ref) => SoundPreferenceNotifier.forTesting(),
      ),
      // Controller-only tests have no ServicesBinding. Keep incidental chat
      // sounds deterministic and off platform channels; sound contract tests
      // provide their own recording fake after this default override.
      soundServiceProvider.overrideWithValue(FakeSoundService()),
      // The controller listens for connectivity coming back (W1a #1). Unit
      // tests have no connectivity_plus channel; a test that drives the
      // signal passes its own stream.
      chatConnectivityProvider.overrideWith(
        (ref) => connectivity ?? Stream<bool>.value(true),
      ),
      ...extraOverrides,
    ],
  );
  return container;
}
