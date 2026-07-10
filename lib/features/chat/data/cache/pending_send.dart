enum PendingSendState { queued, sending, failedPermanent }

class PendingSend {
  final String clientMessageId;
  final String relationshipId;
  final String senderId;
  final String text;
  final String? localMediaPath;
  final String? mediaMimeType;
  final String? mediaType;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCategory;
  final PendingSendState state;

  const PendingSend({
    required this.clientMessageId,
    required this.relationshipId,
    required this.senderId,
    required this.text,
    this.localMediaPath,
    this.mediaMimeType,
    this.mediaType,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastErrorCategory,
    this.state = PendingSendState.queued,
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
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCategory: lastErrorCategory ?? this.lastErrorCategory,
      state: state ?? this.state,
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
      'createdAt': createdAt.toIso8601String(),
      'attempts': attempts,
      'nextAttemptAt': nextAttemptAt?.toIso8601String(),
      'lastErrorCategory': lastErrorCategory,
      'state': state.name,
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
      createdAt: DateTime.parse(json['createdAt'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt:
          json['nextAttemptAt'] == null
              ? null
              : DateTime.parse(json['nextAttemptAt'] as String),
      lastErrorCategory: json['lastErrorCategory'] as String?,
      state: PendingSendState.values.byName(json['state'] as String),
    );
  }
}
