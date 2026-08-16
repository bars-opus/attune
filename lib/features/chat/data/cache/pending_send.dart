enum PendingSendState { queued, sending, failedPermanent }

class PendingSend {
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
  final int? mediaWidth;
  final int? mediaHeight;
  final bool isViewOnce;
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
    this.mediaWidth,
    this.mediaHeight,
    this.isViewOnce = false,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastErrorCategory,
    this.state = PendingSendState.queued,
    this.replyToMessageId,
    this.quotedText,
  });

  PendingSend copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastErrorCategory,
    PendingSendState? state,
  }) {
    return PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: senderId,
      text: text,
      localMediaPath: localMediaPath,
      mediaMimeType: mediaMimeType,
      mediaType: mediaType,
      mediaDurationMs: mediaDurationMs,
      waveform: waveform,
      localThumbnailPath: localThumbnailPath,
      thumbnailMimeType: thumbnailMimeType,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      isViewOnce: isViewOnce,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCategory: lastErrorCategory ?? this.lastErrorCategory,
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
      'mediaWidth': mediaWidth,
      'mediaHeight': mediaHeight,
      'isViewOnce': isViewOnce,
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
      waveform: (json['waveform'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      localThumbnailPath: json['localThumbnailPath'] as String?,
      thumbnailMimeType: json['thumbnailMimeType'] as String?,
      mediaWidth: (json['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (json['mediaHeight'] as num?)?.toInt(),
      isViewOnce: (json['isViewOnce'] as bool?) ?? false,
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
