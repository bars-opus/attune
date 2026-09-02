enum MessageStatus { queued, sending, sent, delivered, read, failed }

class Message {
  static const int maxContentRunes = 10000;
  final String id;
  final String clientMessageId;
  final String relationshipId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final String? mediaKey;
  final String? mediaType;

  /// Ordering position in the chat, distinct from [createdAt].
  ///
  /// Equal to createdAt for every ordinary message. A game card moves to
  /// the bottom when the turn passes, which bumps sort_at only -- so the
  /// date separator still shows when the game was actually sent.
  ///
  /// Defaulted from createdAt rather than required: the two are equal for
  /// every message except a resurfaced game card, so forcing every caller
  /// to pass it would be ceremony that buys nothing.
  final DateTime sortAt;

  /// Set on a game card; the session whose live status the bubble renders.
  final String? gameSessionId;

  bool get isGame => mediaType == 'game';

  /// A place a partner CHOSE to share -- never something the app
  /// revealed. The distinction is the whole feature.
  bool get isPlace => mediaType == 'place';

  /// The marker a game card leaves behind when it moves to the other
  /// side. Not a card: it carries no session and never opens a game.
  bool get isGameTrail => mediaType == 'game_trail';
  final String? mediaThumbnailKey;
  final String? signedMediaUrl;
  final String? localMediaPath;
  final int? mediaDurationMs;
  final List<int>? waveform;
  final String? signedThumbnailUrl;
  final int? mediaWidth;
  final int? mediaHeight;
  final bool isViewOnce;

  /// Views the recipient has left on a streak. Null for every other
  /// message type.
  final int? streakViewsRemaining;

  bool get isStreak => mediaType == 'streak';
  final DateTime? viewedAt;
  final bool isSystemNotice;
  final String source;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final MessageStatus status;
  final bool isMine;
  final String? replyToMessageId;
  final String? quotedText;
  final DateTime? deletedAt;
  final DateTime? editedAt;
  final Map<String, Set<String>> reactions;

  /// True while a video message's optimistic bubble is showing but the
  /// client-side ChatVideoPreparer compression that must finish before
  /// upload is still running. Client-only, like localMediaPath/
  /// signedMediaUrl — never sent to or read from the server (excluded from
  /// toJson/fromJson) and never true for a hydrated/canonical row.
  /// Lets VideoMessagePlayer render a compressing-progress state instead of
  /// trying to build a player around a video that isn't ready yet.
  final bool isPreparing;

  /// 0.0-1.0 compression progress, only meaningful while [isPreparing] is
  /// true — mirrors VideoPrepareProgressDialog's own normalized
  /// (value/100).clamp(0.0, 1.0) reading of video_compress's progress
  /// channel. Null before the first progress callback fires.
  final double? compressProgress;

  /// On-device path to a video's poster frame, set on the optimistic row so
  /// a just-sent video shows its real thumbnail immediately instead of a
  /// blank tile while the upload and server round-trip complete. Client-only
  /// like [localMediaPath] — excluded from toJson/fromJson and never present
  /// on a hydrated canonical row, which uses [signedThumbnailUrl] instead.
  final String? localThumbnailPath;

  const Message({
    required this.id,
    required this.clientMessageId,
    required this.relationshipId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    required this.status,
    required this.isMine,
    this.mediaKey,
    this.mediaType,
    DateTime? sortAt,
    this.gameSessionId,
    this.mediaThumbnailKey,
    this.signedMediaUrl,
    this.localMediaPath,
    this.mediaDurationMs,
    this.waveform,
    this.signedThumbnailUrl,
    this.mediaWidth,
    this.mediaHeight,
    this.isViewOnce = false,
    this.streakViewsRemaining,
    this.viewedAt,
    this.isSystemNotice = false,
    this.source = 'native',
    this.deliveredAt,
    this.readAt,
    this.replyToMessageId,
    this.quotedText,
    this.deletedAt,
    this.editedAt,
    this.reactions = const {},
    this.isPreparing = false,
    this.compressProgress,
    this.localThumbnailPath,
  }) : sortAt = sortAt ?? createdAt;

  factory Message.fromRow(
    Map<String, dynamic> row, {
    required String currentUserId,
  }) {
    final senderId = row['sender_id'] as String;
    final deliveredAt = _parseDateTime(row['delivered_at']);
    final readAt = _parseDateTime(row['read_at']);

    return Message(
      id: row['id'] as String,
      clientMessageId: row['client_message_id'] as String,
      relationshipId: row['relationship_id'] as String,
      senderId: senderId,
      content: (row['content'] as String?) ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      mediaKey: row['media_url'] as String?,
      mediaType: row['media_type'] as String?,
      // Older rows predate the column; falling back to created_at keeps
      // them ordered exactly as before.
      sortAt:
          _parseDateTime(row['sort_at']) ??
          DateTime.parse(row['created_at'] as String).toLocal(),
      gameSessionId: row['game_session_id'] as String?,
      mediaThumbnailKey: row['media_thumbnail_url'] as String?,
      mediaDurationMs: (row['media_duration_ms'] as num?)?.toInt(),
      waveform:
          (row['media_waveform'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList(),
      mediaWidth: (row['media_width'] as num?)?.toInt(),
      mediaHeight: (row['media_height'] as num?)?.toInt(),
      isViewOnce: (row['is_view_once'] as bool?) ?? false,
      streakViewsRemaining: (row['streak_views_remaining'] as num?)?.toInt(),
      viewedAt: _parseDateTime(row['viewed_at']),
      isSystemNotice: (row['is_system_notice'] as bool?) ?? false,
      source: (row['source'] as String?) ?? 'native',
      deliveredAt: deliveredAt,
      readAt: readAt,
      isMine: senderId == currentUserId,
      status: _deriveStatus(
        senderId: senderId,
        currentUserId: currentUserId,
        deliveredAt: deliveredAt,
        readAt: readAt,
      ),
      replyToMessageId: row['reply_to_message_id'] as String?,
      quotedText: row['quoted_text'] as String?,
      deletedAt: _parseDateTime(row['deleted_at']),
      editedAt: _parseDateTime(row['edited_at']),
    );
  }

  factory Message.optimistic({
    required String id,
    required String clientMessageId,
    required String relationshipId,
    required String senderId,
    required String content,
    required DateTime createdAt,
    String? mediaKey,
    String? mediaType,
    String? mediaThumbnailKey,
    String? localMediaPath,
    int? mediaDurationMs,
    List<int>? waveform,
    int? mediaWidth,
    int? mediaHeight,
    bool isViewOnce = false,
    String? replyToMessageId,
    String? quotedText,
    bool isPreparing = false,
    double? compressProgress,
    String? localThumbnailPath,
  }) {
    return Message(
      id: id,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: senderId,
      content: content,
      createdAt: createdAt,
      sortAt: createdAt,
      mediaKey: mediaKey,
      mediaType: mediaType,
      localMediaPath: localMediaPath,
      mediaDurationMs: mediaDurationMs,
      waveform: waveform,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      isViewOnce: isViewOnce,
      source: 'native',
      status: MessageStatus.sending,
      isMine: true,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
      isPreparing: isPreparing,
      compressProgress: compressProgress,
      localThumbnailPath: localThumbnailPath,
    );
  }

  Message copyWith({
    String? id,
    String? clientMessageId,
    String? relationshipId,
    String? senderId,
    String? content,
    DateTime? createdAt,
    DateTime? sortAt,
    String? gameSessionId,
    String? mediaKey,
    String? mediaType,
    String? mediaThumbnailKey,
    String? signedMediaUrl,
    String? localMediaPath,
    int? mediaDurationMs,
    List<int>? waveform,
    String? signedThumbnailUrl,
    int? mediaWidth,
    int? mediaHeight,
    bool? isViewOnce,
    DateTime? viewedAt,
    int? streakViewsRemaining,
    bool? isSystemNotice,
    String? source,
    DateTime? deliveredAt,
    DateTime? readAt,
    MessageStatus? status,
    bool? isMine,
    String? replyToMessageId,
    String? quotedText,
    DateTime? deletedAt,
    DateTime? editedAt,
    Map<String, Set<String>>? reactions,
    bool? isPreparing,
    double? compressProgress,
    String? localThumbnailPath,
  }) {
    return Message(
      id: id ?? this.id,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      relationshipId: relationshipId ?? this.relationshipId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      sortAt: sortAt ?? this.sortAt,
      gameSessionId: gameSessionId ?? this.gameSessionId,
      mediaKey: mediaKey ?? this.mediaKey,
      mediaType: mediaType ?? this.mediaType,
      mediaThumbnailKey: mediaThumbnailKey ?? this.mediaThumbnailKey,
      signedMediaUrl: signedMediaUrl ?? this.signedMediaUrl,
      localMediaPath: localMediaPath ?? this.localMediaPath,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      waveform: waveform ?? this.waveform,
      signedThumbnailUrl: signedThumbnailUrl ?? this.signedThumbnailUrl,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      isViewOnce: isViewOnce ?? this.isViewOnce,
      viewedAt: viewedAt ?? this.viewedAt,
      streakViewsRemaining: streakViewsRemaining ?? this.streakViewsRemaining,
      isSystemNotice: isSystemNotice ?? this.isSystemNotice,
      source: source ?? this.source,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      status: status ?? this.status,
      isMine: isMine ?? this.isMine,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      quotedText: quotedText ?? this.quotedText,
      deletedAt: deletedAt ?? this.deletedAt,
      editedAt: editedAt ?? this.editedAt,
      reactions: reactions ?? this.reactions,
      isPreparing: isPreparing ?? this.isPreparing,
      compressProgress: compressProgress ?? this.compressProgress,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientMessageId': clientMessageId,
      'relationshipId': relationshipId,
      'senderId': senderId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'sortAt': sortAt.toIso8601String(),
      'gameSessionId': gameSessionId,
      'mediaKey': mediaKey,
      'mediaType': mediaType,
      'mediaThumbnailKey': mediaThumbnailKey,
      'mediaDurationMs': mediaDurationMs,
      'waveform': waveform,
      'mediaWidth': mediaWidth,
      'mediaHeight': mediaHeight,
      'isViewOnce': isViewOnce,
      'viewedAt': viewedAt?.toIso8601String(),
      'isSystemNotice': isSystemNotice,
      'source': source,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'status': status.name,
      'isMine': isMine,
      'replyToMessageId': replyToMessageId,
      'quotedText': quotedText,
      'reactions': reactions.map((emoji, ids) => MapEntry(emoji, ids.toList())),
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      clientMessageId: json['clientMessageId'] as String,
      relationshipId: json['relationshipId'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sortAt:
          json['sortAt'] == null
              ? DateTime.parse(json['createdAt'] as String)
              : DateTime.parse(json['sortAt'] as String),
      gameSessionId: json['gameSessionId'] as String?,
      mediaKey: json['mediaKey'] as String?,
      mediaType: json['mediaType'] as String?,
      mediaThumbnailKey: json['mediaThumbnailKey'] as String?,
      mediaDurationMs: (json['mediaDurationMs'] as num?)?.toInt(),
      waveform:
          (json['waveform'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList(),
      mediaWidth: (json['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (json['mediaHeight'] as num?)?.toInt(),
      isViewOnce: (json['isViewOnce'] as bool?) ?? false,
      viewedAt: _parseDateTime(json['viewedAt']),
      isSystemNotice: (json['isSystemNotice'] as bool?) ?? false,
      source: (json['source'] as String?) ?? 'native',
      deliveredAt: _parseDateTime(json['deliveredAt']),
      readAt: _parseDateTime(json['readAt']),
      deletedAt: _parseDateTime(json['deletedAt']),
      editedAt: _parseDateTime(json['editedAt']),
      status: MessageStatus.values.byName(json['status'] as String),
      isMine: json['isMine'] as bool,
      replyToMessageId: json['replyToMessageId'] as String?,
      quotedText: json['quotedText'] as String?,
      reactions:
          (json['reactions'] as Map<String, dynamic>?)?.map(
            (emoji, ids) => MapEntry(
              emoji,
              (ids as List<dynamic>).map((e) => e as String).toSet(),
            ),
          ) ??
          const {},
    );
  }

  // True whenever we know what this media IS — mediaKey (the stable
  // storage path) alone is sufficient, same as an already-resolved
  // signedMediaUrl or a client-local file. NOT gated on requiring
  // signedMediaUrl/localMediaPath specifically: a locally-restored (cached)
  // message has mediaKey but no signedMediaUrl yet — requiring the URL made
  // every cached media message flash "Unsupported message" before
  // ChatController's hydration pass re-signed it moments later. Resolving a
  // URL from mediaKey is the rendering widget's job (see
  // signedMediaUrlProvider), not a precondition for recognizing the type.
  bool get hasImage =>
      mediaType == 'image' &&
      (mediaKey != null || signedMediaUrl != null || localMediaPath != null);
  bool get hasAudio =>
      mediaType == 'audio' &&
      (mediaKey != null || signedMediaUrl != null || localMediaPath != null);
  bool get hasVideo =>
      mediaType == 'video' &&
      (mediaKey != null || signedMediaUrl != null || localMediaPath != null);
  bool get isEphemeralVideoAvailable =>
      isViewOnce &&
      viewedAt == null &&
      (localMediaPath != null || signedMediaUrl != null);
  bool get isEphemeralVideoExpired => isViewOnce && viewedAt != null;
  bool get isQueued => status == MessageStatus.queued;
  bool get isSending => status == MessageStatus.sending;
  bool get isFailed => status == MessageStatus.failed;
  bool get isRead => status == MessageStatus.read;
  bool get isDelivered => status == MessageStatus.delivered;
  bool get isImported => source.startsWith('import:');

  bool get isDeleted => deletedAt != null;

  /// True only for the sender's own message, not yet deleted, sent within
  /// the last 5 minutes. [now] is injectable for testing; callers pass
  /// DateTime.now() in production.
  bool canEditOrDelete({required String currentUserId, required DateTime now}) {
    if (senderId != currentUserId) return false;
    if (isDeleted) return false;
    return now.difference(createdAt) < const Duration(minutes: 5);
  }

  static bool isValidContent(String value, {bool hasMedia = false}) {
    if (!hasMedia && value.trim().isEmpty) return false;
    return value.runes.length <= maxContentRunes;
  }

  static MessageStatus _deriveStatus({
    required String senderId,
    required String currentUserId,
    required DateTime? deliveredAt,
    required DateTime? readAt,
  }) {
    if (senderId != currentUserId) {
      return MessageStatus.sent;
    }
    if (readAt != null) return MessageStatus.read;
    if (deliveredAt != null) return MessageStatus.delivered;
    return MessageStatus.sent;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value).toLocal();
    }
    return null;
  }
}
