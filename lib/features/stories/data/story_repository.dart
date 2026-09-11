/// Server calls that post a story: intent -> upload -> finalize (spec §4.2).
///
/// Follows `snakes_service.dart`'s shape: an `_unwrap` that throws a typed
/// error on `{error:true, code, message}`, and a 30-second timeout on every
/// call (checklist 1.2). The server's `message` is the only part meant for
/// a person; `code` stays internal for branching (checklist 2.4/5.5) — see
/// [StoryApiError.retryable] for which codes Task 6's retry loop may retry.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
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
  /// URL; Storage RLS authorizes the write (spec §4.2). Always
  /// `upsert: false`: an upsert would let a second capture overwrite an
  /// object another intent already claimed.
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
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

  @override
  String toString() => message;
}

class StoryRepository implements StoryGateway {
  StoryRepository(this._supabase);

  final SupabaseClient _supabase;

  /// Checklist 1.2, matching `snakes_service.dart`: without a bound, a
  /// stalled connection leaves the poster staring at a spinner that never
  /// resolves, with no error and no way back.
  static const _timeout = Duration(seconds: 30);

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
    } on StoryApiError {
      rethrow;
    } catch (e) {
      throw StoryApiError.network(e);
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
  }) => _guard(() async {
    await _supabase.storage
        .from(bucket)
        .upload(
          storageKey,
          File(localPath),
          // Spec §4.2: an upsert would let a second capture overwrite an
          // object another intent already claimed.
          fileOptions: FileOptions(upsert: false, contentType: mimeType),
        );
  });

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
  }) => _guard(() async {
    final data = _unwrap(
      await _supabase.rpc(
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
        },
      ),
    );
    return StoryFinalizeResult(
      storyId: '${data['story_id']}',
      existing: data['existing'] == true,
    );
  });
}
