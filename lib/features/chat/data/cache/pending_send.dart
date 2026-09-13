enum PendingSendState { queued, sending, failedPermanent }

class PendingSend {
  static const Object _notProvided = Object();

  final String clientMessageId;
  final String relationshipId;
  final String senderId;
  final String text;
  final String? localMediaPath;
  final String? mediaMimeType;
  final String? mediaType;
  final int? mediaDurationMs;
  final List<int>? waveform;
  final String? localThumbnailPath;
  final String? thumbnailMimeType;

  /// Stable storage keys for files whose upload already completed but whose
  /// message row has not been acknowledged yet. Persisting these prevents a
  /// retry/restart after a later failure from uploading the same bytes again
  /// under a fresh object key.
  final String? uploadedMediaKey;
  final String? uploadedThumbnailKey;
  final int? mediaWidth;
  final int? mediaHeight;
  final bool isViewOnce;

  /// True while [localMediaPath] still points at the original picked file
  /// and must pass through the client preparation pipeline before upload.
  /// Persisting this stage makes an already-visible optimistic bubble
  /// recoverable after either preparation failure or process death.
  final bool requiresPreparation;

  /// Trim window needed to repeat video preparation after a retry/restart.
  /// Null for images and for media that is already prepared.
  final int? trimStartMs;
  final int? trimEndMs;

  /// Views the recipient gets on a streak. Null for every other message
  /// type — a budget on a non-streak is meaningless, and defaulting it
  /// would quietly turn a video into a one-view message if its media type
  /// were ever mis-set.
  final int? streakViewsRemaining;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCategory;
  final PendingSendState state;
  final String? replyToMessageId;
  final String? quotedText;

  const PendingSend({
    required this.clientMessageId,
    required this.relationshipId,
    required this.senderId,
    required this.text,
    this.localMediaPath,
    this.mediaMimeType,
    this.mediaType,
    this.mediaDurationMs,
    this.waveform,
    this.localThumbnailPath,
    this.thumbnailMimeType,
    this.uploadedMediaKey,
    this.uploadedThumbnailKey,
    this.mediaWidth,
    this.mediaHeight,
    this.isViewOnce = false,
    this.requiresPreparation = false,
    this.trimStartMs,
    this.trimEndMs,
    this.streakViewsRemaining,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastErrorCategory,
    this.state = PendingSendState.queued,
    this.replyToMessageId,
    this.quotedText,
  });

  PendingSend copyWith({
    String? localMediaPath,
    String? mediaMimeType,
    int? mediaDurationMs,
    List<int>? waveform,
    String? localThumbnailPath,
    String? thumbnailMimeType,
    String? uploadedMediaKey,
    String? uploadedThumbnailKey,
    int? mediaWidth,
    int? mediaHeight,
    bool? requiresPreparation,
    int? attempts,
    Object? nextAttemptAt = _notProvided,
    Object? lastErrorCategory = _notProvided,
    PendingSendState? state,
  }) {
    return PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: senderId,
      text: text,
      localMediaPath: localMediaPath ?? this.localMediaPath,
      mediaMimeType: mediaMimeType ?? this.mediaMimeType,
      mediaType: mediaType,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      waveform: waveform ?? this.waveform,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      thumbnailMimeType: thumbnailMimeType ?? this.thumbnailMimeType,
      uploadedMediaKey: uploadedMediaKey ?? this.uploadedMediaKey,
      uploadedThumbnailKey: uploadedThumbnailKey ?? this.uploadedThumbnailKey,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      isViewOnce: isViewOnce,
      requiresPreparation: requiresPreparation ?? this.requiresPreparation,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      streakViewsRemaining: streakViewsRemaining,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt:
          identical(nextAttemptAt, _notProvided)
              ? this.nextAttemptAt
              : nextAttemptAt as DateTime?,
      lastErrorCategory:
          identical(lastErrorCategory, _notProvided)
              ? this.lastErrorCategory
              : lastErrorCategory as String?,
      state: state ?? this.state,
      replyToMessageId: replyToMessageId,
      quotedText: quotedText,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clientMessageId': clientMessageId,
      'relationshipId': relationshipId,
      'senderId': senderId,
      'text': text,
      'localMediaPath': localMediaPath,
      'mediaMimeType': mediaMimeType,
      'mediaType': mediaType,
      'mediaDurationMs': mediaDurationMs,
      'waveform': waveform,
      'localThumbnailPath': localThumbnailPath,
      'thumbnailMimeType': thumbnailMimeType,
      'uploadedMediaKey': uploadedMediaKey,
      'uploadedThumbnailKey': uploadedThumbnailKey,
      'mediaWidth': mediaWidth,
      'mediaHeight': mediaHeight,
      'isViewOnce': isViewOnce,
      'requiresPreparation': requiresPreparation,
      'trimStartMs': trimStartMs,
      'trimEndMs': trimEndMs,
      'streakViewsRemaining': streakViewsRemaining,
      'createdAt': createdAt.toIso8601String(),
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt?.toIso8601String(),
      'lastErrorCategory': lastErrorCategory,
      'state': state.name,
      'replyToMessageId': replyToMessageId,
      'quotedText': quotedText,
    };
  }

  factory PendingSend.fromJson(Map<String, dynamic> json) {
    return PendingSend(
      clientMessageId: json['clientMessageId'] as String,
      relationshipId: json['relationshipId'] as String,
      senderId: json['senderId'] as String,
      text: json['text'] as String,
      localMediaPath: json['localMediaPath'] as String?,
      mediaMimeType: json['mediaMimeType'] as String?,
      mediaType: json['mediaType'] as String?,
      mediaDurationMs: (json['mediaDurationMs'] as num?)?.toInt(),
      waveform:
          (json['waveform'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList(),
      localThumbnailPath: json['localThumbnailPath'] as String?,
      thumbnailMimeType: json['thumbnailMimeType'] as String?,
      uploadedMediaKey: json['uploadedMediaKey'] as String?,
      uploadedThumbnailKey: json['uploadedThumbnailKey'] as String?,
      mediaWidth: (json['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (json['mediaHeight'] as num?)?.toInt(),
      isViewOnce: (json['isViewOnce'] as bool?) ?? false,
      requiresPreparation: (json['requiresPreparation'] as bool?) ?? false,
      trimStartMs: (json['trimStartMs'] as num?)?.toInt(),
      trimEndMs: (json['trimEndMs'] as num?)?.toInt(),
      streakViewsRemaining: (json['streakViewsRemaining'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt:
          json['nextAttemptAt'] == null
              ? null
              : DateTime.parse(json['nextAttemptAt'] as String),
      lastErrorCategory: json['lastErrorCategory'] as String?,
      state: PendingSendState.values.byName(json['state'] as String),
      replyToMessageId: json['replyToMessageId'] as String?,
      quotedText: json['quotedText'] as String?,
    );
  }
}
