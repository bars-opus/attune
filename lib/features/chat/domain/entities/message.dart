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
  final String? mediaThumbnailKey;
  final String? signedMediaUrl;
  final String? localMediaPath;
  final String source;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final MessageStatus status;
  final bool isMine;
  final String? replyToMessageId;
  final String? quotedText;
  final DateTime? deletedAt;
  final DateTime? editedAt;

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
    this.mediaThumbnailKey,
    this.signedMediaUrl,
    this.localMediaPath,
    this.source = 'native',
    this.deliveredAt,
    this.readAt,
    this.replyToMessageId,
    this.quotedText,
    this.deletedAt,
    this.editedAt,
  });

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
      mediaThumbnailKey: row['media_thumbnail_url'] as String?,
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
    String? replyToMessageId,
    String? quotedText,
  }) {
    return Message(
      id: id,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: senderId,
      content: content,
      createdAt: createdAt,
      mediaKey: mediaKey,
      mediaType: mediaType,
      localMediaPath: localMediaPath,
      source: 'native',
      status: MessageStatus.sending,
      isMine: true,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );
  }

  Message copyWith({
    String? id,
    String? clientMessageId,
    String? relationshipId,
    String? senderId,
    String? content,
    DateTime? createdAt,
    String? mediaKey,
    String? mediaType,
    String? mediaThumbnailKey,
    String? signedMediaUrl,
    String? localMediaPath,
    String? source,
    DateTime? deliveredAt,
    DateTime? readAt,
    MessageStatus? status,
    bool? isMine,
    String? replyToMessageId,
    String? quotedText,
    DateTime? deletedAt,
    DateTime? editedAt,
  }) {
    return Message(
      id: id ?? this.id,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      relationshipId: relationshipId ?? this.relationshipId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      mediaKey: mediaKey ?? this.mediaKey,
      mediaType: mediaType ?? this.mediaType,
      mediaThumbnailKey: mediaThumbnailKey ?? this.mediaThumbnailKey,
      signedMediaUrl: signedMediaUrl ?? this.signedMediaUrl,
      localMediaPath: localMediaPath ?? this.localMediaPath,
      source: source ?? this.source,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      status: status ?? this.status,
      isMine: isMine ?? this.isMine,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      quotedText: quotedText ?? this.quotedText,
      deletedAt: deletedAt ?? this.deletedAt,
      editedAt: editedAt ?? this.editedAt,
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
      'mediaKey': mediaKey,
      'mediaType': mediaType,
      'mediaThumbnailKey': mediaThumbnailKey,
      'source': source,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'status': status.name,
      'isMine': isMine,
      'replyToMessageId': replyToMessageId,
      'quotedText': quotedText,
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
      mediaKey: json['mediaKey'] as String?,
      mediaType: json['mediaType'] as String?,
      mediaThumbnailKey: json['mediaThumbnailKey'] as String?,
      source: (json['source'] as String?) ?? 'native',
      deliveredAt: _parseDateTime(json['deliveredAt']),
      readAt: _parseDateTime(json['readAt']),
      deletedAt: _parseDateTime(json['deletedAt']),
      editedAt: _parseDateTime(json['editedAt']),
      status: MessageStatus.values.byName(json['status'] as String),
      isMine: json['isMine'] as bool,
      replyToMessageId: json['replyToMessageId'] as String?,
      quotedText: json['quotedText'] as String?,
    );
  }

  bool get hasImage =>
      mediaType == 'image' &&
      (signedMediaUrl != null || localMediaPath != null);
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
