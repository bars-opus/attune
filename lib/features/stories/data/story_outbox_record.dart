/// The durable outbox record for a story capture (spec §6.1).
///
/// A story is captured in the moment, often on poor connectivity, and a
/// failed upload that silently vanishes is worse here than in chat —
/// there is no bubble to show a retry affordance. This record is what
/// [StoryOutboxStore] persists so a queued or in-flight capture survives
/// an app restart.
///
/// Fields are the spec's, verbatim: `clientStoryId, relationshipId,
/// localMediaPath, localThumbnailPath, mediaType, mimeType, width,
/// height, durationMs, utcOffsetMinutes, state, attempts, nextAttemptAt,
/// lastErrorCode, createdAt`.
library;

import 'package:attune/features/stories/domain/captured_media.dart';

/// spec §6.1, verbatim and exhaustive: `queued`, `uploading_media`,
/// `uploading_thumbnail`, `finalizing`, `failed_permanent`.
///
/// This task persists the record only — it does not drive transitions
/// between these states. That state machine is Task 6.
enum StoryOutboxState {
  queued,
  uploadingMedia,
  uploadingThumbnail,
  finalizing,
  failedPermanent,
}

class StoryOutboxRecord {
  const StoryOutboxRecord({
    required this.clientStoryId,
    required this.relationshipId,
    required this.localMediaPath,
    required this.localThumbnailPath,
    required this.mediaType,
    required this.mimeType,
    required this.width,
    required this.height,
    this.durationMs,
    required this.utcOffsetMinutes,
    this.state = StoryOutboxState.queued,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastErrorCode,
    required this.createdAt,
  });

  /// Idempotency key for `create_story_item` (spec §4.2, §6.1). Minted
  /// once when the capture is enqueued and never regenerated — a fresh
  /// id per attempt would defeat the server's idempotency on
  /// `(author_id, client_story_id)` and risk posting the same capture
  /// twice.
  final String clientStoryId;
  final String relationshipId;
  final String localMediaPath;
  final String localThumbnailPath;
  final CapturedMediaType mediaType;
  final String mimeType;
  final int width;
  final int height;

  /// Null for an image, matching [CapturedMedia.durationMs].
  final int? durationMs;
  final int utcOffsetMinutes;
  final StoryOutboxState state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final DateTime createdAt;

  StoryOutboxRecord copyWith({
    StoryOutboxState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
  }) {
    return StoryOutboxRecord(
      clientStoryId: clientStoryId,
      relationshipId: relationshipId,
      localMediaPath: localMediaPath,
      localThumbnailPath: localThumbnailPath,
      mediaType: mediaType,
      mimeType: mimeType,
      width: width,
      height: height,
      durationMs: durationMs,
      utcOffsetMinutes: utcOffsetMinutes,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt:
          clearNextAttemptAt ? null : (nextAttemptAt ?? this.nextAttemptAt),
      lastErrorCode:
          clearLastErrorCode ? null : (lastErrorCode ?? this.lastErrorCode),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'clientStoryId': clientStoryId,
    'relationshipId': relationshipId,
    'localMediaPath': localMediaPath,
    'localThumbnailPath': localThumbnailPath,
    'mediaType': mediaType.name,
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'durationMs': durationMs,
    'utcOffsetMinutes': utcOffsetMinutes,
    'state': state.name,
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'lastErrorCode': lastErrorCode,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StoryOutboxRecord.fromJson(Map<String, dynamic> json) {
    return StoryOutboxRecord(
      clientStoryId: json['clientStoryId'] as String,
      relationshipId: json['relationshipId'] as String,
      localMediaPath: json['localMediaPath'] as String,
      localThumbnailPath: json['localThumbnailPath'] as String,
      mediaType: CapturedMediaType.values.byName(json['mediaType'] as String),
      mimeType: json['mimeType'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      utcOffsetMinutes: (json['utcOffsetMinutes'] as num).toInt(),
      state: StoryOutboxState.values.byName(json['state'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt:
          json['nextAttemptAt'] == null
              ? null
              : DateTime.parse(json['nextAttemptAt'] as String),
      lastErrorCode: json['lastErrorCode'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
