/// Server calls that post a story: intent -> upload -> finalize (spec §4.2).
///
/// Follows `snakes_service.dart`'s shape: an `_unwrap` that throws a typed
/// error on `{error:true, code, message}`, and a 30-second timeout on every
/// call (checklist 1.2). The server's `message` is the only part meant for
/// a person; `code` stays internal for branching (checklist 2.4/5.5) — see
/// [StoryApiError.retryable] for which codes Task 6's retry loop may retry.
library;

import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart'
    show
        ChatMediaUploader,
        ChatUploadCancelToken,
        ChatUploadCancelled,
        chatMediaMissingCode;
import 'package:attune/features/chat/utils/chat_error.dart'
    show ChatError, ChatErrorCategory, ChatImageRejectedSignal;
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every server call this feature's post flow makes.
abstract class StoryGateway {
  /// `create_story_upload_intent`. [objectKind] is `'media'` or
  /// `'thumbnail'`; [mediaType] is `'image'` or `'video'`. A thumbnail
  /// must be `image/jpeg`; media must be `image/jpeg` or `video/mp4`
  /// (spec §4.2) — the server validates this, this method does not.
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  });

  /// Uploads straight to Storage — the intent carries a KEY, not a signed
  /// URL; Storage RLS authorizes the write (spec §4.2).
  ///
  /// Streams the file straight to Storage under the intent's key (spec
  /// §4.2). Never upserts. [onProgress] reports bytes handed to the
  /// socket; [cancelToken] aborts the request. Every failure arrives as a
  /// classified [StoryApiError] (`kind`).
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  });

  /// `create_story_item`. Idempotent on `(author_id, clientStoryId)`: a
  /// retry after a lost response returns the SAME story with
  /// `existing: true` rather than posting twice.
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,

    /// The pinned place (couple map), or null.
    Map<String, dynamic>? place,

    /// When the media was captured (Wave 5, 04 #3): the server files the
    /// story on this instant's date (clamped to the last 7 days). Null on
    /// a record from before this field existed.
    DateTime? capturedAt,
  });
}

/// What `create_story_upload_intent` returns: a key to upload to, not a
/// signed URL (spec §4.1/§4.2).
@immutable
class StoryUploadIntent {
  const StoryUploadIntent({
    required this.intentId,
    required this.storageKey,
    required this.bucket,
    required this.expiresAt,
  });

  final String intentId;
  final String storageKey;
  final String bucket;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'intentId': intentId,
    'storageKey': storageKey,
    'bucket': bucket,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  /// Null for anything incomplete: a half-written intent is no intent, and
  /// the outbox mints a fresh pair.
  static StoryUploadIntent? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['intentId'];
    final key = json['storageKey'];
    final bucket = json['bucket'];
    final expires = DateTime.tryParse('${json['expiresAt']}');
    if (id is! String || key is! String || bucket is! String || expires == null) {
      return null;
    }
    return StoryUploadIntent(
      intentId: id,
      storageKey: key,
      bucket: bucket,
      expiresAt: expires,
    );
  }
}

/// What `create_story_item` returns.
@immutable
class StoryFinalizeResult {
  const StoryFinalizeResult({required this.storyId, required this.existing});

  final String storyId;

  /// True when this call landed on an existing row via the idempotency
  /// key rather than creating a new one — a safe retry, not a duplicate.
  final bool existing;
}

/// How the outbox treats a failure (Wave 2, P1). Mirrors chat's split in
/// `_handleSendFailure`: only an unknown-shape failure (and a stale intent)
/// can exhaust the automatic attempts; a network-class failure never does.
enum StoryFailureKind {
  /// No answer, a stalled or dropped socket, Storage 5xx/408/401. Retried
  /// for as long as it takes, at the capped backoff; never a strike.
  offline,

  /// RATE_LIMITED / Storage 429. Same as [offline].
  rateLimited,

  /// Storage 403 (the intent expired or was used) or finalize UNAVAILABLE:
  /// mint a fresh pair and re-upload. A strike.
  intentStale,

  /// Storage 409 on our own key: an earlier attempt's upload landed.
  alreadyUploaded,

  /// 413 / 415 / MIME: this file will never be accepted. Permanent.
  mediaRejected,

  /// The local file is gone. Permanent; Discard only.
  mediaMissing,

  /// UNAUTHORIZED / FORBIDDEN / INVALID_INPUT / UNAVAILABLE. Permanent.
  refused,

  /// The person cancelled. The row is removed by whoever cancelled it.
  cancelled,

  /// Anything else. A strike, up to the cap.
  unknown,
}

/// Client-side codes. Server codes stay UPPERCASE (`story_intent_error`).
abstract final class StoryErrorCodes {
  static const network = 'network';
  static const storageUnavailable = 'storage_unavailable';
  static const storageForbidden = 'storage_forbidden';
  static const storageDuplicate = 'storage_duplicate';
  static const storageRejected = 'storage_rejected';
  static const mediaTooLarge = 'media_too_large';
  static const mediaTypeRejected = 'media_type_rejected';
  static const mediaMissing = chatMediaMissingCode; // 'media_missing'
  static const cancelled = 'cancelled';
  static const serverError = 'server_error';

  /// The outbox's own verdict, never a server answer: a full upload twice
  /// outlived its 15-minute intents (final review #2). Retry stays offered.
  static const mediaLinkTooSlow = 'media_link_too_slow';
}

/// Server-side refusals, already carrying a user-facing message.
///
/// [code] never reaches the UI; only [message] does. [retryable] is what
/// Task 6's outbox state machine branches on: true for a failure that is
/// safe to retry unchanged, false for one that will fail the same way
/// again.
///
/// The server's five codes (`public.story_intent_error`, see
/// `supabase/migrations/20260938040000_stories_intent_rpc.sql:32-38`) are
/// UPPERCASE and deliberately coarse:
///
/// - `RATE_LIMITED` — retryable. `create_story_upload_intent` refuses past
///   120 calls/hour or 20 live unused intents; the caller backs off and
///   retries (spec §4.2, explicitly documented as retryable there). This
///   is the only retryable server code.
/// - `UNAUTHORIZED`, `FORBIDDEN`, `INVALID_INPUT` — permanent. Retrying an
///   unchanged request produces the same refusal.
/// - `UNAVAILABLE` — permanent, and deliberately NOT retried even though
///   an expired upload intent is one of the conditions that produces it.
///   The server collapses "not a member," "relationship ended," "feature
///   off," and "expired/consumed/mismatched intent" into this single code
///   on purpose, so a client probing it can never turn it into an
///   existence oracle (`20260938050000_stories_finalize_rpc.sql:30,96`).
///   Because the client cannot tell an expired intent apart from a
///   permanent membership refusal from the code alone, blanket-retrying
///   `UNAVAILABLE` would spin forever on the permanent cases.
///
///   **This is why an expired intent is not a retry-the-same-call case.**
///   Spec §6.1: "An expired intent causes a new pair of intents and
///   re-upload; the server cleanup removes the old unused objects." Task
///   6's outbox must treat `UNAVAILABLE` as `failed_permanent` for the
///   purpose of *this* error, but the outbox's own state machine is what
///   decides — on other grounds (e.g. elapsed time since the intents were
///   minted, or a story stuck in `uploading_media`/`uploading_thumbnail`/
///   `finalizing` past the 15-minute intent window) — to mint a fresh pair
///   of intents and re-upload rather than to retry the identical finalize
///   call. That recovery lives one layer up from this repository.
///
/// A call that never reaches the server at all (timeout, socket failure)
/// is a separate, always-retryable case — see [StoryApiError.network].
@immutable
class StoryApiError implements Exception {
  const StoryApiError({
    required this.code,
    required this.message,
    required this.retryable,
  });

  /// The one server code that is safe to retry unchanged. Kept in one
  /// place so `fromJson` and the test that derives truth from the
  /// migrations agree. UPPERCASE: matches `story_intent_error`'s actual
  /// wire format exactly (verified against
  /// `supabase/migrations/2026093[89]*.sql`), not the lowercase form an
  /// earlier draft of this file guessed at.
  static const _retryableCodes = {'RATE_LIMITED'};

  /// Exposed for the test that proves this set matches the server's real
  /// vocabulary rather than a remembered/guessed one.
  @visibleForTesting
  static const retryableCodesForTest = _retryableCodes;

  factory StoryApiError.fromJson(Map<String, dynamic> json) {
    final code = '${json['code'] ?? 'UNKNOWN'}';
    return StoryApiError(
      code: code,
      // The server writes these for people; the client never composes
      // its own from an exception, which is how internals leak into a UI.
      message: '${json['message'] ?? 'Something went wrong. Please try again.'}',
      retryable: _retryableCodes.contains(code),
    );
  }

  /// A call that never reached the server: timeout or transport failure.
  /// Always retryable — nothing about the request was refused.
  factory StoryApiError.network([Object? cause]) => const StoryApiError(
    code: 'network',
    message: 'Could not reach the server. Please try again.',
    retryable: true,
  );

  final String code;
  final String message;
  final bool retryable;

  StoryFailureKind get kind => kindForCode(code);

  static StoryFailureKind kindForCode(String code) => switch (code) {
    StoryErrorCodes.network ||
    StoryErrorCodes.storageUnavailable => StoryFailureKind.offline,
    'RATE_LIMITED' => StoryFailureKind.rateLimited,
    StoryErrorCodes.storageForbidden => StoryFailureKind.intentStale,
    StoryErrorCodes.storageDuplicate => StoryFailureKind.alreadyUploaded,
    StoryErrorCodes.mediaTooLarge ||
    StoryErrorCodes.mediaTypeRejected => StoryFailureKind.mediaRejected,
    StoryErrorCodes.mediaMissing => StoryFailureKind.mediaMissing,
    'UNAUTHORIZED' ||
    'FORBIDDEN' ||
    'INVALID_INPUT' ||
    'UNAVAILABLE' => StoryFailureKind.refused,
    StoryErrorCodes.cancelled => StoryFailureKind.cancelled,
    _ => StoryFailureKind.unknown,
  };

  static StoryApiError _client(String code, String message) => StoryApiError(
    code: code,
    message: message,
    retryable: switch (kindForCode(code)) {
      StoryFailureKind.offline || StoryFailureKind.rateLimited => true,
      _ => false,
    },
  );

  /// Any failure from the intent, upload or finalize step, classified.
  /// The message is fixed copy; the cause never reaches it (2.4/5.5).
  factory StoryApiError.fromFailure(Object error) {
    if (error is StoryApiError) return error;
    if (error is ChatUploadCancelled) {
      return _client(StoryErrorCodes.cancelled, 'Cancelled.');
    }
    if ((error is ChatImageRejectedSignal &&
            error.code == StoryErrorCodes.mediaMissing) ||
        error is FileSystemException) {
      return _client(
        StoryErrorCodes.mediaMissing,
        'This photo or video is no longer on this phone.',
      );
    }
    if (error is StorageException) return _fromStorage(error);
    // IOException covers a TLS handshake failure (captive portal, flaky
    // cellular) and a raw dart:io HttpException, which http's IOClient does
    // not wrap. FileSystemException, also an IOException, is handled above.
    if (error is TimeoutException ||
        error is IOException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return StoryApiError.network(error);
    }
    // The RPCs report business refusals as `{error:true}` jsonb, so a
    // PostgrestException is usually transport-shaped: a gateway 5xx,
    // PGRST0xx (database unreachable), PGRST301 (JWT expired across a
    // resume), no code at all. Chat's rule decides (chat_error.dart
    // `_categorizePostgrest`): unavailable never strikes, a real rejection
    // of the request does.
    if (error is PostgrestException) {
      return switch (ChatError.from(error).category) {
        ChatErrorCategory.unavailable => StoryApiError.network(error),
        ChatErrorCategory.rateLimited => _rateLimited,
        _ => _client(
          StoryErrorCodes.serverError,
          'Something went wrong. Please try again.',
        ),
      };
    }
    // Anything else, AuthException included (a revoked refresh token is
    // not a transport failure): unknown shape.
    return _client(
      StoryErrorCodes.serverError,
      'Something went wrong. Please try again.',
    );
  }

  static const _rateLimited = StoryApiError(
    code: 'RATE_LIMITED',
    message: 'Too many tries. Please wait a moment.',
    retryable: true,
  );

  static StoryApiError _fromStorage(StorageException error) {
    final status = int.tryParse(error.statusCode ?? '');
    final text = '${error.error ?? ''} ${error.message}'.toLowerCase();
    if (status == null || status >= 500 || status == 401 || status == 408) {
      return _client(
        StoryErrorCodes.storageUnavailable,
        'Could not reach the server. Please try again.',
      );
    }
    if (status == 429) return _rateLimited;
    if (status == 403) {
      return _client(StoryErrorCodes.storageForbidden, 'Upload refused.');
    }
    if (status == 409) {
      return _client(StoryErrorCodes.storageDuplicate, 'Already uploaded.');
    }
    if (status == 413) {
      return _client(StoryErrorCodes.mediaTooLarge, 'This file is too large.');
    }
    if (status == 415 || text.contains('mime')) {
      return _client(
        StoryErrorCodes.mediaTypeRejected,
        "This file type can't be posted.",
      );
    }
    return _client(StoryErrorCodes.storageRejected, 'Upload refused.');
  }

  @override
  String toString() => message;
}

class StoryRepository implements StoryGateway {
  StoryRepository(this._supabase, {ChatMediaUploader? uploader})
    : _uploaderOverride = uploader;

  final SupabaseClient _supabase;
  final ChatMediaUploader? _uploaderOverride;
  ChatMediaUploader? _uploader;

  /// The same streamed uploader chat uses (chat review #25): bounded by a
  /// 20 s stall and a 60 s response window, aborted by closing the client,
  /// so a timed-out attempt can no longer race its own retry to the key.
  ChatMediaUploader get _mediaUploader =>
      _uploaderOverride ??
      (_uploader ??= ChatMediaUploader(
        storageUrl: () => _supabase.storage.url,
        headers: _uploadHeaders,
      ));

  /// Mirrors `SupabaseChatRepository._uploadHeaders` (supabase_chat_
  /// repository.dart:633-660): the streaming uploader bypasses the SDK's
  /// AuthHttpClient, so the apikey and the CURRENT bearer are added by hand,
  /// refreshing an expired session first. Kept in step with chat's copy.
  Future<Map<String, String>> _uploadHeaders() async {
    final auth = _supabase.auth;
    final apiKey = auth.headers['apikey'];
    if (auth.currentSession?.isExpired ?? false) {
      try {
        await auth.refreshSession();
      } catch (_) {
        // A failed refresh surfaces as Storage 401: offline-class, retried.
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

  /// Checklist 1.2, matching `snakes_service.dart`: without a bound, a
  /// stalled connection leaves the poster staring at a spinner that never
  /// resolves, with no error and no way back.
  static const _timeout = Duration(seconds: 30);

  /// When the server last answered as one that predates p_captured_at
  /// (PGRST202); the date then falls back to posting time and p_client_now
  /// is dropped with it. Null: send the capture time.
  DateTime? _finalizeWithoutCaptureAt;

  /// How long a PGRST202 is believed before sending the capture time again,
  /// so a client that hit a deploy's schema-reload window recovers without
  /// a restart (as the day-items fallback does in story_read_repository).
  static const _finalizeCaptureReprobe = Duration(minutes: 10);

  Map<String, dynamic> _unwrap(Object? response) {
    final data = Map<String, dynamic>.from(response! as Map);
    if (data['error'] == true) throw StoryApiError.fromJson(data);
    return data;
  }

  /// Runs [op], converting a timeout or any other transport failure into
  /// [StoryApiError.network] rather than letting a raw exception (a
  /// `SocketException`, a `PostgrestException` with a database detail
  /// in its message) reach the UI. A [StoryApiError] already thrown by
  /// [_unwrap] passes through unchanged.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(_timeout);
    } catch (e) {
      throw StoryApiError.fromFailure(e);
    }
  }

  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) => _guard(() async {
    final data = _unwrap(
      await _supabase.rpc(
        'create_story_upload_intent',
        params: {
          'p_relationship_id': relationshipId,
          'p_object_kind': objectKind,
          'p_media_type': mediaType,
          'p_mime_type': mimeType,
        },
      ),
    );
    return StoryUploadIntent(
      intentId: '${data['intent_id']}',
      storageKey: '${data['storage_key']}',
      bucket: '${data['bucket']}',
      expiresAt: DateTime.parse('${data['expires_at']}'),
    );
  });

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    // No flat .timeout() here: the uploader's own stall/response bounds
    // decide, and they abort the request instead of abandoning it.
    try {
      await _mediaUploader.upload(
        bucket: bucket,
        objectKey: storageKey,
        localPath: localPath,
        mimeType: mimeType,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } catch (e) {
      throw StoryApiError.fromFailure(e);
    }
  }

  @override
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,
    Map<String, dynamic>? place,
    DateTime? capturedAt,
  }) => _guard(() async {
    Future<dynamic> call({required bool withCapture}) => _supabase.rpc(
      'create_story_item',
      params: {
        'p_relationship_id': relationshipId,
        'p_client_story_id': clientStoryId,
        'p_media_intent_id': mediaIntentId,
        'p_thumbnail_intent_id': thumbnailIntentId,
        'p_media_width': mediaWidth,
        'p_media_height': mediaHeight,
        'p_duration_ms': durationMs,
        'p_utc_offset_minutes': utcOffsetMinutes,
        // Only when pinned: a client shipped before the migration
        // deploys must still finalize.
        if (place != null) 'p_place': place,
        if (withCapture && capturedAt != null) ...{
          'p_captured_at': capturedAt.toUtc().toIso8601String(),
          // The phone's clock now (fix round 1): the server applies the
          // capture's age on this clock to its own, so a phone clock that
          // is off does not move the story's date.
          'p_client_now': clock.now().toUtc().toIso8601String(),
        },
      },
    );
    dynamic response;
    final since = _finalizeWithoutCaptureAt;
    final withCapture =
        capturedAt != null &&
        (since == null ||
            clock.now().difference(since) >= _finalizeCaptureReprobe);
    try {
      response = await call(withCapture: withCapture);
      if (withCapture) _finalizeWithoutCaptureAt = null;
    } on PostgrestException catch (e) {
      // PGRST202: the function was never called, so asking again cannot
      // post twice.
      if (!withCapture || e.code != 'PGRST202') rethrow;
      _finalizeWithoutCaptureAt = clock.now();
      response = await call(withCapture: false);
    }
    final data = _unwrap(response);
    return StoryFinalizeResult(
      storyId: '${data['story_id']}',
      existing: data['existing'] == true,
    );
  });
}
