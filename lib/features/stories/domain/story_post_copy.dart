import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';

/// Why a take could not be shared (01 #20): one plain sentence per
/// preparer rejection code (chat_video_preparer.dart / capture_image_
/// preparer.dart / the pipeline), never the code itself.
String storyPrepareFailureMessage(String code, CapturedMediaType type) {
  final noun = type == CapturedMediaType.image ? 'photo' : 'video';
  return switch (code) {
    'media_too_long' => 'That video is longer than a minute.',
    'media_too_short' => 'That video is too short. Hold a little longer.',
    'media_too_large' ||
    'media_dimensions_excessive' ||
    'media_compress_failed' => "That $noun couldn't be prepared. Try again.",
    'media_missing' || 'media_empty' => "That $noun wasn't saved. Try again.",
    'media_decode_failed' ||
    'media_type_unsupported' => "That $noun couldn't be read. Try again.",
    'thumbnail_failed' ||
    'thumbnail_frame_failed' => "That $noun couldn't be prepared. Try again.",
    'not_saved' => "That $noun couldn't be saved. Try again.",
    'place_dropped' =>
      "Shared without a place. We couldn't find where you are in time.",
    'signed_out' => 'Sign in again to share a story.',
    _ => 'That could not be posted.',
  };
}

/// A transient prepare failure while the take is still on the review: the
/// take was kept, so the person can tap Share again (batch-7 review I3).
String storyPrepareRetryMessage(CapturedMediaType type) {
  final noun = type == CapturedMediaType.image ? 'photo' : 'video';
  return "Couldn't prepare that $noun. Tap Share to try again.";
}

/// The rings-row line for a take whose camera had gone when it failed
/// (Task 16's notice). `place_dropped` is the one notice for a story that
/// WAS shared; an unexpected code never reaches the person as a code or a
/// vague "that could not be posted".
String storyPostNoticeMessage(String code, CapturedMediaType type) {
  final noun = type == CapturedMediaType.image ? 'photo' : 'video';
  if (code == 'place_dropped') {
    return "Your story was shared without a place. We couldn't find where "
        'you are in time.';
  }
  // Every notice but place_dropped is raised after the pipeline deleted the
  // take, so nothing is left to "try again" (final review #3): the reason,
  // then what the person can do now. The on-camera snackbars keep "Try
  // again", which there means retake.
  final (reason, tail) = switch (code) {
    'media_too_long' => (
      'That video is longer than a minute.',
      'Take a shorter one to share it.',
    ),
    'media_too_short' => (
      'That video was too short.',
      'Hold a little longer next time.',
    ),
    'media_too_large' ||
    'media_dimensions_excessive' ||
    'media_compress_failed' ||
    'thumbnail_failed' ||
    'thumbnail_frame_failed' => ("That $noun couldn't be prepared.", _retake),
    'media_missing' || 'media_empty' => ("That $noun wasn't saved.", _retake),
    'media_decode_failed' ||
    'media_type_unsupported' => ("That $noun couldn't be read.", _retake),
    'not_saved' => ("That $noun couldn't be saved.", _retake),
    _ => ('Something went wrong preparing that $noun.', _retake),
  };
  return "Your story wasn't shared. $reason $tail";
}

const String _retake = 'Take it again to share it.';

/// What a dead outbox record says, and whether Retry can help (01 #20).
({String message, bool canRetry}) storyOutboxFailureCopy(
  String? code,
  CapturedMediaType type,
) {
  final noun = type == CapturedMediaType.image ? 'photo' : 'video';
  return switch (code) {
    StoryErrorCodes.mediaMissing => (
      message: 'This $noun is no longer on this phone.',
      canRetry: false,
    ),
    StoryErrorCodes.mediaTooLarge => (
      message: 'This $noun is too large to post.',
      canRetry: false,
    ),
    StoryErrorCodes.mediaTypeRejected => (
      message: "This $noun can't be posted.",
      canRetry: false,
    ),
    'FORBIDDEN' => (
      message: "You can't post to this story any more.",
      canRetry: false,
    ),
    'INVALID_INPUT' => (
      message: "This $noun couldn't be posted.",
      canRetry: false,
    ),
    StoryErrorCodes.mediaLinkTooSlow => (
      message:
          'Your connection was too slow to post this $noun. Try again on '
          'Wi-Fi.',
      canRetry: true,
    ),
    'UNAUTHORIZED' => (
      message: 'Sign in again to post your story.',
      canRetry: true,
    ),
    _ => (message: 'Your story could not be posted.', canRetry: true),
  };
}

/// Offline-class failures a `finalizing` row may run up before the person
/// is offered Discard (final review #3d). They never strike, so without
/// this a persistent transport fault on finalize had no way out.
const int storyFinalizingExitAfterAttempts = 5;

/// A `finalizing` row whose finalize keeps failing offline: the post may
/// already exist, so it is never cancelled, but past
/// [storyFinalizingExitAfterAttempts] the person may Discard it.
bool storyFinalizingMayBeStuck(StoryOutboxRecord record) {
  final code = record.lastErrorCode;
  return record.state == StoryOutboxState.finalizing &&
      record.attempts >= storyFinalizingExitAfterAttempts &&
      code != null &&
      switch (StoryApiError.kindForCode(code)) {
        StoryFailureKind.offline || StoryFailureKind.rateLimited => true,
        _ => false,
      };
}

/// The pending line under the ring.
String storyPendingStatus(StoryOutboxRecord record) {
  if (storyFinalizingMayBeStuck(record)) {
    return 'Still trying to post your story. It may already have posted, so '
        'check your story.';
  }
  final code = record.lastErrorCode;
  final waiting =
      code != null &&
      record.nextAttemptAt != null &&
      switch (StoryApiError.kindForCode(code)) {
        StoryFailureKind.offline || StoryFailureKind.rateLimited => true,
        _ => false,
      };
  return waiting
      ? "Waiting for a connection. Your story will post when you're back online."
      : 'Posting your story…';
}
