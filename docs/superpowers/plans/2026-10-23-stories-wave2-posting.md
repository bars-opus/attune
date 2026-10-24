# Stories Wave 2 — Posting, Outbox and the Shared Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a story posted on a bad connection always arrive (or say exactly why it cannot), keep queued captures private and off backups, fix the shared camera (resolution, microphone, copy, lifecycle, the 60 s edge), and add a Share / Retake review step before anything leaves the phone.

**Architecture:** The outbox keeps its shape (`StoryOutboxController` over `StoryOutboxStore`) but gains chat's retry policy: every failure is classified into a `StoryFailureKind`, and only unknown-shape failures and stale intents count toward the 5-strike cap. Intents are persisted inside the encrypted record and re-minted near expiry. Uploads go through chat's `ChatMediaUploader` (streamed, stall-bounded, cancellable, with byte progress). A new `StoryOutboxTriggers` (warmed in `App.initState`, like `ChatOutboxDrainer`) flushes on resume, reconnect and sign-in, and wipes other accounts' captures. Queued media moves into `ApplicationSupport/story_outbox/<userId>/<clientStoryId>/` (`StoryMediaVault`), stored as relative paths. Posting a capture moves out of the widget into `StoryPostPipeline` (a provider), so it survives the camera unmounting. The story adapter adds a review layer over the embedded `CaptureCameraScreen` using its existing `isReviewing` contract. Every new `CaptureCameraScreen` parameter defaults to today's streak behaviour.

**Tech Stack:** Flutter 3.29.1, flutter_riverpod 2.6.1, camera 0.11.2+1 (camera_avfoundation 0.9.21+2, camera_android_camerax 0.6.19+1), video_compress 3.1.4, video_player, connectivity_plus 4.x (via `chatConnectivityProvider`), permission_handler (`openAppSettings`), http 1.x `MockClient`, `package:clock`, Drift/SQLite (outbox backend), flutter_test.

**Spec:** `docs/reviews/2026-10-23-stories-robustness-review.md` (Wave 2 = P1–P4; owner ruling 1 is binding: Share / Retake before posting, overriding STORIES.md §6.1), `docs/reviews/2026-10-23-stories-review/01_posting.md` (findings 1–16, 19–20), `07a_verification_client.md` (V11–V17, groups I, J, K), `07b_verification_server.md` (V3, V5, V9; G3, G5, G9 and their regression notes), `05_security_privacy.md` #2, `06_standards_checklist.md` #12–#14, and `lib/architecture/STORIES.md` §6 (amended in Task 19).

## Global Constraints

- Work in the **main working tree** on `main`. The user has unrelated uncommitted edits (`ios/Podfile.lock`, `games_docs.dart`, `manual_documentation_registry.dart`, `app_router.dart`, `chat_screen.dart`, `message_bubble.dart`, `planning_home_screen.dart`, `scripts/wipe_all_chat_dev.sql`, docs tests, and others). **Wave 1's reel changes are also uncommitted in the tree** (`story_reel_screen.dart`, `story_providers.dart`, `story_progress_bars.dart`, `story_reel_header.dart`, `STORIES.md`, `story_reel_*_test.dart`, `story_pager_refresh_test.dart`, `story_progress_bars_test.dart`, `story_calendar_test.dart`, `story_reel_test.dart`). Never revert, stash, stage or reformat any of them. Touch only the files each task names. `STORIES.md` is edited only in §6 / §6.1 / §6.4 / §5.1's pending-tile sentence (Task 19), never elsewhere.
- **No commits.** Every "Commit" step of the standard template is replaced by "Run tests". Nothing is staged.
- **Never `dart format` a pre-existing file.** The repo uses an older formatter, and formatting reflows whole files. Run `dart format` only on files this plan creates (listed as "Create").
- **TDD:** write the test, run it, and **see it fail** (or fail to compile, where noted) before writing production code. A regression guard that already passes is labelled as such.
- **Design tokens:** spacing `Spacing.*`, icon sizes `IconSizes.*` (`lib/app/theme/design_tokens.dart`); destructive actions use `Theme.of(context).colorScheme.error` (as `story_rings_row.dart` already does). Any displayed date or time uses `MyDateFormat` (none is expected in this wave). The camera and review layer are a fixed black media surface in both themes, so their foreground is literal `Colors.white` / white-with-alpha, exactly as `capture_camera_screen.dart` does today (`theme.appColors.white` is themed and wrong there).
- **State via Riverpod.** No new dependencies. Everything used here is already in `pubspec.yaml` (`http`, `clock`, `permission_handler`, `connectivity_plus`, `video_player`, `path_provider`).
- **SQL:** none. No migration is planned. If a check needs a database, use only local `attune_spec3a`, never `attune_test`.
- **Shared-camera regression gate:** `test/features/stories/capture_camera_test.dart`, `test/features/chat/streak_camera_contract_test.dart`, `streak_camera_test.dart`, `streak_camera_photo_test.dart` and `streak_lock_test.dart` stay green after every task that touches `capture_camera_screen.dart` (Tasks 11–14). Every new `CaptureCameraScreen` parameter defaults to the current streak behaviour, and `streak_camera_screen.dart` is **not edited**. The literal `enableAudio: true` must stay in `capture_camera_screen.dart` (`streak_camera_test.dart:51-61` pins it in the source).
- **Shared-chat regression gate:** `chat_video_preparer.dart` (Task 15) and `chat_media_uploader.dart` (read-only reuse) are chat files. Task 15's change is opt-in (a new optional constructor field, `null` = byte-identical behaviour, so no `prepare` override in any test fake has to change); re-run `test/features/chat/chat_video_preparer_test.dart`, `chat_state_send_video_message_test.dart`, `chat_state_send_ephemeral_video_message_test.dart`, `video_trim_screen_test.dart` and `chat_media_uploader_test.dart`.
- **Shared core files touched** (each additive, each with a regression note in its task): `lib/app/app.dart` (Task 6, one warm-up microtask), `lib/features/auth/providers/auth_provider.dart` (Task 9, one extra wipe in its own try inside `signOut`), `lib/features/safety/data/safety_sign_out.dart` (Task 9, one extra wipe in its own try), the two Android backup XMLs (Task 10).
- **Allowed edits to existing tests** (no others):
  - Every `implements StoryGateway` fake gains the two new optional `uploadObject` parameters (Task 2): `story_outbox_controller_test.dart`, `story_rings_test.dart`, `story_calendar_test.dart`, `story_camera_test.dart`. Signature only.
  - `story_repository_test.dart` "uploads use upsert: false" is re-pointed at the streamed uploader (Task 2).
  - `story_outbox_controller_test.dart`: "a permanent failure is reached after a bounded number of retryable failures" and "retry restarts the backoff cycle…" switch their driving error from `network` to an unknown-shape error, because network failures no longer exhaust (Task 4, the point of P1).
  - `story_camera_test.dart`: `buildContainer` gains a vault override; `tapShutter` also taps Share; the thumbnail-exists assertion resolves the now vault-relative path (Task 17, owner ruling 1 and Task 7).
  - `capture_camera_test.dart`: its private `_FakeCameraPlatform` records `MediaSettings` (Task 11). New tests are added; existing assertions are unchanged. New tests that need denial, stop errors or dispose counts use `support/capture_fakes.dart`'s `FakeCameraPlatform` (imported `as fakes`).
  - `test/core/android_manifest_test.dart` gains one test (Task 10).
  - Only if Task 9 Step 8 shows a timing failure: `test/features/auth/auth_sign_out_media_wipe_test.dart`'s container gains a `storyOutboxWiperProvider` override with a zero bound. Harness only; report it.
- **Never edited:** `streak_camera_screen.dart`, `streak_camera_contract_test.dart`, any other streak test, `story_ring.dart` (Wave 4), `story_reel_screen.dart` (Wave 1), any SQL or migration.
- User-facing copy is plain English, sentence case, and never says "streak" in the story flow. l10n extraction is a separate gate item.

## Review Focus

Five conditions the spec implies but no requirement names. Each is pinned by a test in its owning task:

1. **Device clock skew against the server's `expires_at`:** the phone's clock is minutes off, so a freshly minted intent already looks expired (or never does). A record must still post: re-minting must not count as a strike, and a stale-at-load intent re-mints instead of failing. Test in Task 5.
2. **Sign-out while an upload is in flight:** the person signs out mid-upload on a shared phone. Nothing of theirs may be written back to the store or left on disk after the wipe, and the old controller's timers must not fire into a disposed notifier. Tests in Tasks 6 and 9.
3. **A record queued by the build before this one:** absolute `tmp/` paths, no persisted intents, no `strikes` field. It must still load, post, and be discardable. Tests in Tasks 3 and 7.
4. **A phone call or Control Centre mid-hold:** the app goes inactive while a video is recording. The take recorded so far is kept and reaches review, and the camera works again on return. Test in Task 14.
5. **Double taps:** Share tapped twice before the first tap's frame. Exactly one record is queued and the take is prepared once. (A second shutter press during review cannot happen, because the shared camera hides its record button while `isReviewing`. `_onCaptured` still drops and deletes a stray second take.) Test in Task 17.

## Spec rulings made by this plan

Owner ruling 1 is binding. Where the review leaves a choice, the plan rules as follows:

- **Review step (P4):**
  - A full-bleed preview with **Retake** and **Share**, built in `story_camera_screen.dart` only. It uses the existing `CaptureCameraScreen.isReviewing`, so the shared screen's contract does not change.
  - The pin pill stays where it is (top centre) on both the live camera and the review. The place is read when Share is tapped, bounded at 3 s. Past that, the story posts without a place and the person is told.
  - Closing (X or back) during review asks "Discard this photo?". While a Share is being prepared, Close is hidden and back is blocked.
- **Retry policy (P1), the same as chat's `_handleSendFailure`:**
  - `network`, Storage 5xx/408/401 and `RATE_LIMITED` never strike. They keep the capped 64 s backoff (chat's cap) with equal jitter. 07b G3 suggested 6 h; the plan keeps chat's 64 s so both outboxes behave alike, and reconnect/resume flushes cover the long-outage case.
  - Unknown-shape failures, and stale intents (Storage 403, finalize `UNAVAILABLE`), strike, up to 5.
  - Storage 409 on our own key counts as "already uploaded", and the record moves to the next step. Finalize re-verifies size and MIME.
  - These are permanent at once, with a reason:
    - Storage 413 or 415/MIME → `media_too_large` / `media_type_rejected`;
    - a missing local file → `media_missing`, offered as Discard only;
    - `UNAUTHORIZED` / `FORBIDDEN` / `INVALID_INPUT`, and `UNAVAILABLE` outside finalize.
- **Intents:** persisted in the encrypted record. Both are re-minted (no strike) when either is within **2 minutes** of `expiresAt` before an upload or finalize step.
- **Cancel:** offered while a story is posting, until finalize has been sent. After that, Cancel says "It has already posted. You can delete it from your story." (Wave 1 adds Delete to the own reel.)
- **Storage:**
  - Queued media lives at `ApplicationSupport/story_outbox/<userId>/<clientStoryId>/{media.<ext>,thumb.jpg}`.
  - Records store paths relative to Application Support. Legacy absolute paths still work.
  - The `story_outbox/` folder and the outbox DB (+`-wal`/`-shm`) are excluded from iOS and Android backups.
- **Wipes:**
  - Sign-out and quick-exit sign-out wipe every row and file.
  - "Account switch" means any sign-in, cold start included. It wipes every *other* user's rows and files, which also covers a session that expired without a sign-out.
- **Shared camera (P3):**
  - The resolution preset is an embedder parameter (default `medium`; stories `veryHigh`).
  - The silent-photo fallback for a denied microphone is opt-in (`microphoneOptional`, stories only). Streaks keep today's behaviour.
  - Copy is an embedder parameter (`CaptureCameraCopy`; streak strings are the defaults).
  - **Applied to both embedders, deliberately:**
    - Close and Open Settings on the camera error screen (a dead end today);
    - accessibility labels;
    - `stopVideoRecording` error recovery;
    - lifecycle pause and re-init on inactive and resume.

    These fix broken states rather than change working ones. The lifecycle handling is required before Wave 3 keeps the camera mounted (07b G7 risk 1). This is the one place streak runtime behaviour changes (an interrupted take is kept instead of stranding the camera), and the owner can make it opt-in with a one-line default if wanted.
- **60 s edge and fractional trims:**
  - Opt-in on `ChatVideoPreparer(boundaryTolerance:)` (a constructor field), passed only by the story pipeline (2 s).
  - When it is set: a recording up to 62 s is clamped to exactly 60 s, an untrimmed source is exported whole (no whole-second window), and `durationMs = min(exported, 60000)`.
  - Streak and chat calls are byte-identical. Opting streaks in later is a one-line follow-up for the owner.
- **Left out (not in Wave 2 scope):**
  - strict FIFO across a backed-off record (01 #21, Low);
  - dropping records when a relationship closes (01 #11 tail; it needs a relationship-state signal from Wave 4/5);
  - reusing the preparer's poster as the thumbnail (01 #19 second half);
  - a "post queued stories?" prompt after a quick-exit return (05 #2's suggestion: the wipe makes it moot).

## Server dependencies

None is required. Notes for the device and staging checks:
1. Storage reports RLS refusals and duplicates in the JSON body (`statusCode: "403"` / `"409"`), which `ChatMediaUploader.storageExceptionFor` already decodes. Confirm on staging with an expired intent (wait 15 min) and with a re-upload to the same key.
2. Wave 5's bucket `file_size_limit` / `allowed_mime_types` will make 413/415 reachable at upload time. Task 1 already classifies them.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `lib/features/stories/data/story_repository.dart` (modify) | `StoryFailureKind`, `StoryErrorCodes`, `StoryApiError.fromFailure`/`.kind`; streamed upload via `ChatMediaUploader`; intent JSON | 1, 2, 3 |
| `lib/features/stories/data/story_outbox_record.dart` (modify) | `mediaIntent`, `thumbnailIntent`, `strikes`; copyWith passthrough | 3 |
| `lib/features/stories/presentation/state/story_outbox_controller.dart` (modify) | Retry policy, persisted intents, re-mint, force flush, dispose/epoch guards, vault paths, cancel, progress | 4–8 |
| `lib/features/stories/data/story_outbox_store.dart` (modify) | `epoch`, `wipeAll`, `removeOtherUsers` | 6, 9 |
| `lib/features/stories/data/story_outbox_backend_base.dart`, `_io.dart`, `_stub.dart` (modify) | `removeOtherUsers`; backup exclusion of the DB files | 9, 10 |
| `lib/features/stories/presentation/state/story_outbox_triggers.dart` (create) | Flush on resume, reconnect and sign-in; account-switch wipe | 6, 9 |
| `lib/app/app.dart` (modify, one microtask) | Warm `storyOutboxTriggersProvider` | 6 |
| `lib/features/stories/data/story_media_vault.dart` (create) | App-private capture folder, relative paths, wipes, backup exclusion | 7, 9 |
| `lib/features/stories/data/story_outbox_wipe.dart` (create) | `StoryOutboxWiper`: bounded, never-throwing wipe of rows and files | 9 |
| `lib/features/auth/providers/auth_provider.dart` (modify, additive) | Story wipe in `signOut` | 9 |
| `lib/features/safety/data/safety_sign_out.dart` (modify, additive) | Story wipe in the quick-exit sign-out | 9 |
| `android/app/src/main/res/xml/backup_rules.xml`, `data_extraction_rules.xml` (modify) | Exclude the outbox DB files and `story_outbox/` | 10 |
| `lib/features/chat/presentation/screens/capture_camera_screen.dart` (modify) | `resolutionPreset`, `microphoneOptional`, `copy`, `openSettings`; error screen; a11y; stop errors; lifecycle | 11–14 |
| `lib/features/chat/domain/services/chat_video_preparer.dart` (modify, opt-in) | `boundaryTolerance`, `debugExportWindow`, `debugReportedDurationMs` | 15 |
| `lib/features/stories/presentation/state/story_post_pipeline.dart` (create) | Prepare, thumbnail, bounded place, vault adopt, enqueue; independent of the widget | 16 |
| `lib/features/stories/domain/story_post_copy.dart` (create) | Reasoned copy for prepare rejections and outbox failures | 16, 18 |
| `lib/features/stories/presentation/widgets/story_review_layer.dart` (create) | Share / Retake overlay | 17 |
| `lib/features/stories/presentation/screens/story_camera_screen.dart` (modify) | Review state, Share via the pipeline, close confirm, story camera config | 11, 12, 16, 17 |
| `lib/features/stories/presentation/widgets/story_outbox_notices.dart` (create) | Pending (status + Cancel), failed (reason, Retry only when useful, confirmed Discard), prepare-failed | 18 |
| `lib/features/stories/presentation/widgets/story_rings_row.dart` (modify) | Use the notices; byte progress on the pending ring | 18 |
| `lib/architecture/STORIES.md` (modify, §5.1 one sentence, §6, §6.1, §6.4) | Owner ruling 1 and the new outbox contract | 19 |
| `test/features/stories/story_outbox_policy_test.dart` (create) | Tasks 4, 5, 7, 8 behaviour | 4, 5, 7, 8 |
| `test/features/stories/story_outbox_triggers_test.dart` (create) | Task 6 and the account-switch wipe | 6, 9 |
| `test/features/stories/story_media_vault_test.dart` (create) | Vault | 7, 10 |
| `test/features/stories/story_outbox_sign_out_test.dart` (create) | Sign-out and quick-exit wipes | 9 |
| `test/features/stories/story_outbox_backup_test.dart` (create) | DB backup exclusion | 10 |
| `test/features/stories/story_post_pipeline_test.dart` (create) | Pipeline | 16 |
| `test/features/stories/story_review_test.dart` (create) | Review step | 17 |
| `test/features/stories/story_outbox_notices_test.dart` (create) | Notices | 18 |
| `test/features/stories/support/outbox_fakes.dart` (create) | Shared scriptable gateway and record builder for the new suites | 4 |
| `test/features/stories/story_repository_test.dart` (modify) | Taxonomy and streamed-upload tests | 1, 2 |
| `test/features/stories/story_outbox_record_test.dart` (create) | Record JSON round-trip and legacy load | 3 |
| `test/features/stories/capture_camera_test.dart` (modify: fake + new tests) | P3 | 11–14 |
| `test/features/chat/chat_video_preparer_test.dart` (modify: new group) | Task 15 helpers | 15 |
| `test/core/android_manifest_test.dart` (modify: one test) | Backup XMLs | 10 |

## Before you start

- [ ] **Baseline.** Run the regression suites and record the pass counts. Everything must pass before Task 1. If anything already fails, stop and report it; do not fix it under this plan.

```bash
cd /Users/user/attune
flutter test test/features/stories test/features/chat/streak_camera_contract_test.dart \
  test/features/chat/streak_camera_test.dart test/features/chat/streak_camera_photo_test.dart \
  test/features/chat/streak_lock_test.dart test/features/chat/chat_video_preparer_test.dart \
  test/features/chat/chat_media_uploader_test.dart test/features/auth test/features/safety \
  test/core/android_manifest_test.dart test/features/chat/chat_backup_exclusion_test.dart
```
Expected: all pass.

---

### Task 1: Classify every posting failure (`StoryFailureKind`)

Fixes 01 #3 (classification half) and V13; groundwork for V11/V12. `_guard` currently maps every non-`StoryApiError` to `network` (`story_repository.dart:195-203`).

**Files:**
- Modify: `lib/features/stories/data/story_repository.dart`: imports at `:10-13`; `StoryApiError` at `:126-172`; `_guard` at `:195-203`.
- Test: `test/features/stories/story_repository_test.dart` (append a new group; existing tests untouched).

**Interfaces:**
- Consumes: `ChatUploadCancelled`, `ChatImageRejectedSignal`, `chatMediaMissingCode` (chat, read-only); `StorageException`, `PostgrestException`, `AuthException`, `AuthRetryableFetchException` (supabase_flutter); `http.ClientException`.
- Produces:
  - `enum StoryFailureKind { offline, rateLimited, intentStale, alreadyUploaded, mediaRejected, mediaMissing, refused, cancelled, unknown }`
  - `abstract final class StoryErrorCodes { static const network = 'network'; storageUnavailable = 'storage_unavailable'; storageForbidden = 'storage_forbidden'; storageDuplicate = 'storage_duplicate'; storageRejected = 'storage_rejected'; mediaTooLarge = 'media_too_large'; mediaTypeRejected = 'media_type_rejected'; mediaMissing = 'media_missing'; cancelled = 'cancelled'; serverError = 'server_error'; }`
  - `StoryFailureKind StoryApiError.kind` (getter) and `static StoryFailureKind StoryApiError.kindForCode(String code)`
  - `factory StoryApiError.fromFailure(Object error)`

- [ ] **Step 1: Write the failing tests.** Append to `test/features/stories/story_repository_test.dart` inside `main()`, after the `timeout` group. Add these imports at the top (keep the existing ones):

```dart
import 'dart:async';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/utils/chat_error.dart'
    show ChatImageRejectedSignal;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException, PostgrestException;
```

```dart
  group('failure kinds (Wave 2, P1)', () {
    StoryApiError storage(int status, String body) => StoryApiError.fromFailure(
      ChatMediaUploader.storageExceptionFor(status, body),
    );

    test('transport failures are offline and never a server refusal', () {
      for (final error in <Object>[
        const SocketException('no route'),
        TimeoutException('upload stalled (body)'),
        http.ClientException('Connection closed'),
        AuthRetryableFetchException(message: 'offline'),
      ]) {
        final mapped = StoryApiError.fromFailure(error);
        expect(mapped.kind, StoryFailureKind.offline, reason: '$error');
        expect(mapped.code, StoryErrorCodes.network);
        expect(mapped.retryable, isTrue);
      }
    });

    test('Storage refusals are read from the body status, as chat does', () {
      // Storage answers RLS/duplicate/size as HTTP 400 with the real code in
      // the JSON body (chat_media_uploader.dart storageExceptionFor).
      expect(
        storage(400, '{"statusCode":"403","error":"Unauthorized",'
            '"message":"new row violates row-level security policy"}').kind,
        StoryFailureKind.intentStale,
      );
      expect(
        storage(400, '{"statusCode":"409","error":"Duplicate",'
            '"message":"The resource already exists"}').kind,
        StoryFailureKind.alreadyUploaded,
      );
      final tooLarge = storage(400, '{"statusCode":"413","error":"Payload too large",'
          '"message":"The object exceeded the maximum allowed size"}');
      expect(tooLarge.kind, StoryFailureKind.mediaRejected);
      expect(tooLarge.code, StoryErrorCodes.mediaTooLarge);
      final mime = storage(400, '{"statusCode":"415","error":"invalid_mime_type",'
          '"message":"mime type video/quicktime is not supported"}');
      expect(mime.code, StoryErrorCodes.mediaTypeRejected);
      expect(storage(503, 'upstream down').kind, StoryFailureKind.offline);
      expect(storage(408, '').kind, StoryFailureKind.offline);
      expect(storage(401, '{"statusCode":"401","message":"jwt expired"}').kind,
          StoryFailureKind.offline);
      expect(storage(429, '').kind, StoryFailureKind.rateLimited);
      expect(storage(400, '{"statusCode":"400","message":"weird"}').kind,
          StoryFailureKind.unknown);
    });

    test('a missing local file is media_missing, never a network retry', () {
      for (final error in <Object>[
        const ChatImageRejectedSignal('media_missing'),
        const FileSystemException('gone', '/tmp/x.jpg'),
        const PathNotFoundException('/tmp/x.jpg', OSError('No such file', 2)),
      ]) {
        final mapped = StoryApiError.fromFailure(error);
        expect(mapped.kind, StoryFailureKind.mediaMissing, reason: '$error');
        expect(mapped.code, StoryErrorCodes.mediaMissing);
      }
    });

    test('a cancelled upload is cancelled', () {
      expect(
        StoryApiError.fromFailure(const ChatUploadCancelled()).kind,
        StoryFailureKind.cancelled,
      );
    });

    test('an unexpected server or auth error has an unknown shape', () {
      expect(
        StoryApiError.fromFailure(const PostgrestException(message: 'boom')).kind,
        StoryFailureKind.unknown,
      );
      expect(
        StoryApiError.fromFailure(const AuthException('refresh token revoked')).kind,
        StoryFailureKind.unknown,
      );
      expect(StoryApiError.fromFailure(StateError('bug')).kind,
          StoryFailureKind.unknown);
    });

    test('server codes keep their meaning', () {
      expect(StoryApiError.kindForCode('RATE_LIMITED'), StoryFailureKind.rateLimited);
      for (final code in ['UNAUTHORIZED', 'FORBIDDEN', 'INVALID_INPUT', 'UNAVAILABLE']) {
        expect(StoryApiError.kindForCode(code), StoryFailureKind.refused, reason: code);
      }
      // A StoryApiError passes through untouched.
      const refused = StoryApiError(code: 'FORBIDDEN', message: 'm', retryable: false);
      expect(identical(StoryApiError.fromFailure(refused), refused), isTrue);
    });

    test('the copy a person sees never carries an exception', () {
      final mapped = StoryApiError.fromFailure(const SocketException('secret host'));
      expect(mapped.message, isNot(contains('secret host')));
      expect(mapped.toString(), isNot(contains('Exception')));
    });
  });
```

- [ ] **Step 2: Run them and see them fail**

Run: `flutter test test/features/stories/story_repository_test.dart --plain-name "failure kinds"`
Expected: compile failure (`StoryFailureKind`, `StoryErrorCodes` and `fromFailure` are not defined).

- [ ] **Step 3: Implement.** In `story_repository.dart`, add these imports:

```dart
import 'dart:async';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart'
    show ChatUploadCancelled, chatMediaMissingCode;
import 'package:attune/features/chat/utils/chat_error.dart'
    show ChatImageRejectedSignal;
import 'package:http/http.dart' as http;
```

Above `class StoryApiError`, add:

```dart
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
}
```

Inside `StoryApiError` (keep everything that is already there), add:

```dart
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
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException ||
        error is AuthRetryableFetchException) {
      return StoryApiError.network(error);
    }
    if (error is PostgrestException || error is AuthException) {
      return _client(
        StoryErrorCodes.serverError,
        'Something went wrong. Please try again.',
      );
    }
    return _client(
      StoryErrorCodes.serverError,
      'Something went wrong. Please try again.',
    );
  }

  static StoryApiError _fromStorage(StorageException error) {
    final status = int.tryParse(error.statusCode ?? '');
    final text = '${error.error ?? ''} ${error.message}'.toLowerCase();
    if (status == null || status >= 500 || status == 401 || status == 408) {
      return _client(
        StoryErrorCodes.storageUnavailable,
        'Could not reach the server. Please try again.',
      );
    }
    if (status == 429) {
      return const StoryApiError(
        code: 'RATE_LIMITED',
        message: 'Too many tries. Please wait a moment.',
        retryable: true,
      );
    }
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
```

`StorageException` comes from `package:supabase_flutter/supabase_flutter.dart`, which this file already imports. If `StorageException.error` is not a field in storage_client 2.5.5, drop `error.error` from `text` and match on `message` only.

Replace the body of `_guard` (`:195-203`):

```dart
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(_timeout);
    } catch (e) {
      throw StoryApiError.fromFailure(e);
    }
  }
```

- [ ] **Step 4: Run the tests and see them pass**

Run: `flutter test test/features/stories/story_repository_test.dart`
Expected: all pass, the existing `errors` and `timeout` groups included.

- [ ] **Step 5: Run tests** (replaces commit): `flutter test test/features/stories/story_outbox_controller_test.dart test/features/stories/story_camera_test.dart`. Expected: pass. The controller still branches on `retryable`, and the codes it sees are unchanged.

---

### Task 2: Streamed, stall-bounded, cancellable upload through `ChatMediaUploader`

Fixes 01 #2 / V12 (the flat 30 s bound does not abort, so the retry collides with its own orphan) and 01 checklist 2.14 (the whole file is held in memory).

**Files:**
- Modify: `lib/features/stories/data/story_repository.dart`: `StoryGateway.uploadObject` at `:32-37`; `StoryRepository` at `:174-247`.
- Modify (signature only): every `implements StoryGateway` fake: `test/features/stories/story_outbox_controller_test.dart:101-115`, `story_rings_test.dart` (`_HangingStoryGateway`), `story_calendar_test.dart` (its gateway fake), `story_camera_test.dart` (`_FakeStoryGateway.uploadObject`).
- Modify: `test/features/stories/story_repository_test.dart`: re-point "uploads use upsert: false" (`:155-183`); add an upload group.

**Interfaces:**
- Consumes: Task 1's `StoryApiError.fromFailure`; `ChatMediaUploader`, `ChatUploadCancelToken`.
- Produces:
  - `StoryGateway.uploadObject({required String bucket, required String storageKey, required String localPath, required String mimeType, void Function(int sent, int total)? onProgress, ChatUploadCancelToken? cancelToken})`
  - `StoryRepository(SupabaseClient supabase, {ChatMediaUploader? uploader})`

- [ ] **Step 1: Write the failing tests.** In `story_repository_test.dart`, add `import 'dart:convert';`, `import 'package:http/testing.dart';` and `import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;`. Fold the last into the Task 1 `show` list: `show AuthException, AuthRetryableFetchException, PostgrestException, SupabaseClient`. Replace the test "uploads use upsert: false" with:

```dart
    test('uploads stream through ChatMediaUploader, which never upserts', () {
      // Spec §4.2: an upsert would let a second capture overwrite an object
      // another intent already claimed. The streamed uploader pins
      // x-upsert: false on every request (chat_media_uploader_test.dart).
      final source =
          File('lib/features/stories/data/story_repository.dart').readAsStringSync();
      expect(source, contains('ChatMediaUploader'));
      expect(source, contains('.upload('));
      expect(source.contains('upsert: true'), isFalse);
      final uploader = File(
        'lib/features/chat/data/repositories/chat_media_uploader.dart',
      ).readAsStringSync();
      expect(uploader, contains("headers['x-upsert'] = 'false'"));
    });
```

Then append this group:

```dart
  group('streamed upload (Wave 2, P1)', () {
    late Directory dir;
    late File file;
    late SupabaseClient client;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('story_upload');
      file = File('${dir.path}/media.jpg')
        ..writeAsBytesSync(List<int>.generate(200 * 1024, (i) => i % 251));
      client = SupabaseClient('http://127.0.0.1:9', 'test-anon-key');
    });
    tearDown(() async {
      await client.dispose();
      await dir.delete(recursive: true);
    });

    StoryRepository repoWith(http.Client http) => StoryRepository(
      client,
      uploader: ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () async => {'Authorization': 'Bearer jwt', 'apikey': 'anon'},
        clientFactory: () => http,
      ),
    );

    test('a 409 on our key surfaces as alreadyUploaded, not network', () async {
      final repo = repoWith(MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          Stream.value(utf8.encode(
            '{"statusCode":"409","error":"Duplicate","message":"exists"}',
          )),
          400,
        );
      }));

      await expectLater(
        repo.uploadObject(
          bucket: 'story-media',
          storageKey: 'rel/k1.jpg',
          localPath: file.path,
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<StoryApiError>().having(
          (e) => e.kind, 'kind', StoryFailureKind.alreadyUploaded,
        )),
      );
    });

    test('reports byte progress and honours a cancel token', () async {
      final seen = <int>[];
      final repo = repoWith(MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      }));
      await repo.uploadObject(
        bucket: 'story-media',
        storageKey: 'rel/k2.jpg',
        localPath: file.path,
        mimeType: 'image/jpeg',
        onProgress: (sent, total) => seen.add(sent),
      );
      expect(seen.last, 200 * 1024);

      final token = ChatUploadCancelToken()..cancel();
      await expectLater(
        repo.uploadObject(
          bucket: 'story-media',
          storageKey: 'rel/k3.jpg',
          localPath: file.path,
          mimeType: 'image/jpeg',
          cancelToken: token,
        ),
        throwsA(isA<StoryApiError>().having(
          (e) => e.kind, 'kind', StoryFailureKind.cancelled,
        )),
      );
    });

    test('a missing file fails as media_missing before any request', () async {
      var requests = 0;
      final repo = repoWith(MockClient.streaming((request, body) async {
        requests++;
        return http.StreamedResponse(const Stream.empty(), 200);
      }));
      await expectLater(
        repo.uploadObject(
          bucket: 'story-media',
          storageKey: 'rel/k4.jpg',
          localPath: '${dir.path}/gone.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<StoryApiError>().having(
          (e) => e.code, 'code', StoryErrorCodes.mediaMissing,
        )),
      );
      expect(requests, 0);
    });
  });
```

- [ ] **Step 2: Run and see the failure**

Run: `flutter test test/features/stories/story_repository_test.dart --plain-name "streamed upload"`
Expected: compile failure (`uploader:` / `onProgress:` / `cancelToken:` are not parameters).

- [ ] **Step 3: Implement.** In `StoryGateway`, replace `uploadObject` with:

```dart
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
```

Widen the chat import to `show ChatMediaUploader, ChatUploadCancelToken, ChatUploadCancelled, chatMediaMissingCode`. In `StoryRepository`, replace the constructor and `uploadObject`:

```dart
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
  /// repository.dart:632-656): the streaming uploader bypasses the SDK's
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
```

Update each test fake's `uploadObject` signature by adding exactly these two parameters (bodies unchanged), plus `import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart' show ChatUploadCancelToken;` where needed:

```dart
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
```

- [ ] **Step 4: Run and see them pass**

Run: `flutter test test/features/stories/story_repository_test.dart`
Expected: all pass (the `timeout` group still finds `.timeout(` and `Duration(seconds: 30)` on the RPCs).

- [ ] **Step 5: Run tests:** `flutter test test/features/stories test/features/chat/chat_media_uploader_test.dart`. Expected: all pass.

---

### Task 3: Persist intents and strikes in the record

Groundwork for 01 #8 (intents held only in memory) and for a strike count separate from the backoff exponent.

**Files:**
- Modify: `lib/features/stories/data/story_repository.dart`: `StoryUploadIntent` at `:57-72` (add JSON).
- Modify: `lib/features/stories/data/story_outbox_record.dart`: fields, constructor, `copyWith`, `toJson`, `fromJson`.
- Create: `test/features/stories/story_outbox_record_test.dart`

**Interfaces:**
- Produces:
  - `Map<String, dynamic> StoryUploadIntent.toJson()`; `static StoryUploadIntent? StoryUploadIntent.fromJson(Object? json)`
  - `StoryOutboxRecord.mediaIntent` / `.thumbnailIntent` (`StoryUploadIntent?`); `StoryOutboxRecord.strikes` (`int`, default 0); `bool get hasIntents`
  - `copyWith({..., StoryUploadIntent? mediaIntent, StoryUploadIntent? thumbnailIntent, bool clearIntents = false, int? strikes})`

- [ ] **Step 1: Write the failing test.** Create `test/features/stories/story_outbox_record_test.dart`:

```dart
import 'dart:convert';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter_test/flutter_test.dart';

StoryOutboxRecord _record() => StoryOutboxRecord(
  clientStoryId: 'cid-1',
  relationshipId: 'rel-1',
  localMediaPath: 'story_outbox/u1/cid-1/media.jpg',
  localThumbnailPath: 'story_outbox/u1/cid-1/thumb.jpg',
  mediaType: CapturedMediaType.image,
  mimeType: 'image/jpeg',
  width: 1080,
  height: 1920,
  utcOffsetMinutes: 60,
  createdAt: DateTime.utc(2026, 10, 23, 9),
);

StoryUploadIntent _intent(String kind) => StoryUploadIntent(
  intentId: 'intent-$kind',
  storageKey: 'rel-1/$kind.jpg',
  bucket: 'story-media',
  expiresAt: DateTime.utc(2026, 10, 23, 9, 15),
);

void main() {
  test('intents and strikes survive a JSON round trip', () {
    final record = _record().copyWith(
      state: StoryOutboxState.uploadingThumbnail,
      mediaIntent: _intent('media'),
      thumbnailIntent: _intent('thumbnail'),
      strikes: 2,
    );
    final back = StoryOutboxRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
    );
    expect(back.hasIntents, isTrue);
    expect(back.mediaIntent!.intentId, 'intent-media');
    expect(back.mediaIntent!.storageKey, 'rel-1/media.jpg');
    expect(back.thumbnailIntent!.expiresAt, DateTime.utc(2026, 10, 23, 9, 15));
    expect(back.strikes, 2);
  });

  test('copyWith keeps intents unless told to clear them', () {
    final held = _record().copyWith(
      mediaIntent: _intent('media'),
      thumbnailIntent: _intent('thumbnail'),
    );
    expect(held.copyWith(attempts: 3).hasIntents, isTrue);
    final cleared = held.copyWith(clearIntents: true);
    expect(cleared.mediaIntent, isNull);
    expect(cleared.thumbnailIntent, isNull);
    expect(cleared.hasIntents, isFalse);
  });

  test('a record written by the previous build still loads (Review Focus 3)', () {
    // No intents, no strikes, absolute tmp paths: exactly what is on
    // phones today.
    final legacy = {
      'clientStoryId': 'old-1',
      'relationshipId': 'rel-1',
      'localMediaPath': '/private/var/mobile/tmp/capture_1.jpg',
      'localThumbnailPath': '/private/var/mobile/tmp/thumb_1.jpg',
      'mediaType': 'image',
      'mimeType': 'image/jpeg',
      'width': 640,
      'height': 480,
      'durationMs': null,
      'utcOffsetMinutes': 0,
      'state': 'uploadingMedia',
      'attempts': 1,
      'nextAttemptAt': null,
      'lastErrorCode': 'network',
      'createdAt': '2026-10-22T10:00:00.000Z',
    };
    final record = StoryOutboxRecord.fromJson(legacy);
    expect(record.strikes, 0);
    expect(record.hasIntents, isFalse);
    expect(record.localMediaPath, '/private/var/mobile/tmp/capture_1.jpg');
  });

  test('a half-written intent is treated as none', () {
    expect(StoryUploadIntent.fromJson({'intentId': 'x'}), isNull);
    expect(StoryUploadIntent.fromJson(null), isNull);
  });
}
```

- [ ] **Step 2: Run and see the failure**

Run: `flutter test test/features/stories/story_outbox_record_test.dart`
Expected: compile failure.

- [ ] **Step 3: Implement.** In `StoryUploadIntent` (`story_repository.dart`), add:

```dart
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
```

In `story_outbox_record.dart`, add `import 'package:attune/features/stories/data/story_repository.dart' show StoryUploadIntent;`. Add constructor parameters `this.mediaIntent, this.thumbnailIntent, this.strikes = 0`, and these fields with docs:

```dart
  /// The pair this record is uploading under (spec §4.2), persisted inside
  /// the encrypted payload so a restart resumes the same keys instead of
  /// orphaning uploaded objects (01 #8). Null until minted; cleared when
  /// stale.
  final StoryUploadIntent? mediaIntent;
  final StoryUploadIntent? thumbnailIntent;

  /// Failures that count toward the automatic cap (unknown shape, stale
  /// intent). [attempts] still drives the backoff window; offline failures
  /// raise [attempts] but never [strikes] (Wave 2, P1).
  final int strikes;

  bool get hasIntents => mediaIntent != null && thumbnailIntent != null;
```

Extend `copyWith`:

```dart
  StoryOutboxRecord copyWith({
    StoryOutboxState? state,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
    StoryUploadIntent? mediaIntent,
    StoryUploadIntent? thumbnailIntent,
    bool clearIntents = false,
    int? strikes,
  }) {
    return StoryOutboxRecord(
      // ...every existing argument unchanged...
      mediaIntent: clearIntents ? null : (mediaIntent ?? this.mediaIntent),
      thumbnailIntent:
          clearIntents ? null : (thumbnailIntent ?? this.thumbnailIntent),
      strikes: strikes ?? this.strikes,
    );
  }
```

In `toJson` add `if (mediaIntent != null) 'mediaIntent': mediaIntent!.toJson(), if (thumbnailIntent != null) 'thumbnailIntent': thumbnailIntent!.toJson(), 'strikes': strikes,`. In `fromJson` add `mediaIntent: StoryUploadIntent.fromJson(json['mediaIntent']), thumbnailIntent: StoryUploadIntent.fromJson(json['thumbnailIntent']), strikes: (json['strikes'] as num?)?.toInt() ?? 0,`.

- [ ] **Step 4: Run and see it pass:** `flutter test test/features/stories/story_outbox_record_test.dart`. Expected: PASS.

- [ ] **Step 5: Run tests:** `flutter test test/features/stories/story_outbox_store_test.dart test/features/stories/story_outbox_controller_test.dart`. Expected: pass.

---

### Task 4: Chat's retry policy: offline never exhausts; refusals are permanent with a reason

Fixes 01 #1 / V11 / 06 #3 / 07b V3 (an offline post goes permanent after about 23 s), the 409 half of V12, and the 403 / 413 / missing-file half of V13.

**Files:**
- Create: `test/features/stories/support/outbox_fakes.dart`
- Create: `test/features/stories/story_outbox_policy_test.dart`
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart`: `_maxAutomaticAttempts` at `:111-112`; `_drive` at `:280-346`; `_handleFailure` at `:378-432`; `retry` at `:235-249` (reset `strikes`).
- Modify (allowed edits): `test/features/stories/story_outbox_controller_test.dart`, the tests at `:498-538` and `:540-610`.

**Interfaces:**
- Consumes: Task 1's `StoryFailureKind`; Task 3's `strikes`.
- Produces:
  - `static const int StoryOutboxController.maxStrikes = 5`
  - `@visibleForTesting static Duration StoryOutboxController.backoffWindowFor(int attempts)` (the window *upper bound*: `2^clamp(attempts,1,6)` seconds)
  - test support: `ScriptedStoryGateway`, `outboxRecord(...)`, `outboxHarness(...)`

- [ ] **Step 1: Write the shared fakes.** Create `test/features/stories/support/outbox_fakes.dart`:

```dart
// Shared doubles for the Wave 2 outbox suites. The older
// story_outbox_controller_test.dart keeps its own private fake.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const outboxUserId = 'user-w2';

User outboxUser([String id = outboxUserId]) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

/// Each call pops its next scripted outcome (an Object to throw, or null
/// to succeed); an empty script succeeds. [uploadGate] holds uploads open
/// until completed, honouring the cancel token.
class ScriptedStoryGateway implements StoryGateway {
  final intentScript = <Object?>[];
  final uploadScript = <Object?>[];
  final finalizeScript = <Object?>[];
  final intentCalls = <String>[];
  final uploads = <({String key, String path})>[];
  final finalizes = <({String media, String thumb})>[];
  Completer<void>? uploadGate;
  Completer<void>? finalizeGate;
  Duration intentLifetime = const Duration(minutes: 15);
  DateTime Function() now = DateTime.now;
  int _seq = 0;

  Object? _next(List<Object?> script) =>
      script.isEmpty ? null : script.removeAt(0);

  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) async {
    final failure = _next(intentScript);
    if (failure != null) throw failure;
    intentCalls.add(objectKind);
    _seq++;
    return StoryUploadIntent(
      intentId: 'intent-$objectKind-$_seq',
      storageKey: 'key-$objectKind-$_seq',
      bucket: 'story-media',
      expiresAt: now().add(intentLifetime),
    );
  }

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    final gate = uploadGate;
    if (gate != null) {
      cancelToken?.onCancel(() {
        if (!gate.isCompleted) {
          gate.completeError(StoryApiError.fromFailure(const ChatUploadCancelled()));
        }
      });
      onProgress?.call(50, 100);
      await gate.future;
    }
    final failure = _next(uploadScript);
    if (failure != null) throw failure;
    if (!File(localPath).existsSync()) {
      throw StoryApiError.fromFailure(const FileSystemException('gone'));
    }
    onProgress?.call(100, 100);
    uploads.add((key: storageKey, path: localPath));
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
  }) async {
    await finalizeGate?.future;
    final failure = _next(finalizeScript);
    if (failure != null) throw failure;
    finalizes.add((media: mediaIntentId, thumb: thumbnailIntentId));
    return StoryFinalizeResult(storyId: 's-$clientStoryId', existing: false);
  }
}

StoryApiError storageError(int status) => StoryApiError.fromFailure(
  ChatMediaUploader.storageExceptionFor(400, '{"statusCode":"$status","message":"x"}'),
);

const unknownError = StoryApiError(
  code: StoryErrorCodes.serverError,
  message: 'Something went wrong.',
  retryable: false,
);

StoryOutboxRecord outboxRecord(
  Directory dir, {
  String id = 'cid-1',
  StoryOutboxState state = StoryOutboxState.queued,
}) {
  final media = File('${dir.path}/$id-media.jpg')..writeAsBytesSync([1, 2, 3]);
  final thumb = File('${dir.path}/$id-thumb.jpg')..writeAsBytesSync([4, 5]);
  return StoryOutboxRecord(
    clientStoryId: id,
    relationshipId: 'rel-1',
    localMediaPath: media.path,
    localThumbnailPath: thumb.path,
    mediaType: CapturedMediaType.image,
    mimeType: 'image/jpeg',
    width: 1080,
    height: 1920,
    utcOffsetMinutes: 0,
    state: state,
    createdAt: DateTime.utc(2026, 10, 23, 8),
  );
}

typedef OutboxHarness = ({
  ProviderContainer container,
  StoryOutboxStore store,
  ScriptedStoryGateway gateway,
  StoryOutboxController Function() controller,
});

/// [user] replaces the default signed-in-user override (a provider may be
/// overridden only once per container).
OutboxHarness outboxHarness({
  StoryOutboxStore? store,
  ScriptedStoryGateway? gateway,
  Override? user,
  List<Override> extra = const [],
}) {
  final s = store ?? StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
  final g = gateway ?? ScriptedStoryGateway();
  final container = ProviderContainer(
    overrides: [
      user ?? currentUserProvider.overrideWithValue(outboxUser()),
      storyOutboxStoreProvider.overrideWithValue(s),
      storyGatewayProvider.overrideWithValue(g),
      ...extra,
    ],
  );
  return (
    container: container,
    store: s,
    gateway: g,
    controller: () => container.read(storyOutboxProvider.notifier),
  );
}

/// Clears the backoff on every non-failed row and flushes once.
Future<void> forceOnce(OutboxHarness h) async {
  for (final row in await h.store.readAll(outboxUserId)) {
    await h.store.put(outboxUserId, row.copyWith(clearNextAttemptAt: true));
  }
  await h.controller().flush();
}
```

- [ ] **Step 2: Write the failing policy tests.** Create `test/features/stories/story_outbox_policy_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('outbox_policy'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('retry policy (P1, V11)', () {
    test('offline failures never exhaust: still queued after 12 tries, then posts',
        () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript.addAll(List.filled(12, StoryApiError.network()));
      await h.controller().enqueue(outboxRecord(dir));
      for (var i = 0; i < 11; i++) {
        await forceOnce(h);
      }
      var row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, isNot(StoryOutboxState.failedPermanent));
      expect(row.strikes, 0);
      expect(row.lastErrorCode, StoryErrorCodes.network);
      expect(row.nextAttemptAt, isNotNull);

      await forceOnce(h); // the network is back
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.gateway.finalizes, hasLength(1));
    });

    test('RATE_LIMITED never strikes either', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript.addAll(List.filled(7, const StoryApiError(
        code: 'RATE_LIMITED', message: 'slow down', retryable: true)));
      await h.controller().enqueue(outboxRecord(dir));
      for (var i = 0; i < 6; i++) {
        await forceOnce(h);
      }
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, isNot(StoryOutboxState.failedPermanent));
      expect(row.strikes, 0);
    });

    test('an unknown-shape failure exhausts after 5 strikes', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript.addAll(List.filled(10, unknownError));
      await h.controller().enqueue(outboxRecord(dir));
      for (var i = 0; i < 9; i++) {
        final rows = await h.store.readAll(outboxUserId);
        if (rows.single.state == StoryOutboxState.failedPermanent) break;
        await forceOnce(h);
      }
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, StoryOutboxState.failedPermanent);
      expect(row.strikes, StoryOutboxController.maxStrikes);
    });

    test('offline tries do not use up the strikes an unknown failure gets', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript
        ..addAll(List.filled(8, StoryApiError.network()))
        ..add(unknownError);
      await h.controller().enqueue(outboxRecord(dir));
      for (var i = 0; i < 8; i++) {
        await forceOnce(h);
      }
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, isNot(StoryOutboxState.failedPermanent));
      expect(row.strikes, 1);
    });

    test('Storage 409 on our key means it landed: move on, no re-upload', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.uploadScript.add(storageError(409));
      await h.controller().enqueue(outboxRecord(dir));
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.gateway.intentCalls, ['media', 'thumbnail']);
      expect(h.gateway.finalizes, hasLength(1));
    });

    test('Storage 403 drops the intents, re-queues and re-mints (a strike)', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.uploadScript.add(storageError(403));
      await h.controller().enqueue(outboxRecord(dir));
      var row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, StoryOutboxState.queued);
      expect(row.hasIntents, isFalse);
      expect(row.strikes, 1);
      await forceOnce(h);
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.gateway.intentCalls, hasLength(4));
    });

    for (final (status, code) in [
      (413, StoryErrorCodes.mediaTooLarge),
      (415, StoryErrorCodes.mediaTypeRejected),
    ]) {
      test('Storage $status is permanent at once with code $code', () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.uploadScript.add(storageError(status));
        await h.controller().enqueue(outboxRecord(dir));
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, StoryOutboxState.failedPermanent);
        expect(row.lastErrorCode, code);
        expect(row.attempts, 1);
      });
    }

    test('a missing local file is permanent at once as media_missing', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final record = outboxRecord(dir);
      File(record.localMediaPath).deleteSync();
      await h.controller().enqueue(record);
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, StoryOutboxState.failedPermanent);
      expect(row.lastErrorCode, StoryErrorCodes.mediaMissing);
    });

    test('backoff windows are chat\'s: 2, 4 … capped at 64 s', () {
      expect(StoryOutboxController.backoffWindowFor(1), const Duration(seconds: 2));
      expect(StoryOutboxController.backoffWindowFor(3), const Duration(seconds: 8));
      expect(StoryOutboxController.backoffWindowFor(40), const Duration(seconds: 64));
    });
  });
}
```

- [ ] **Step 3: Run and see them fail**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart`
Expected: compile failure (`maxStrikes`, `backoffWindowFor`), then, once those stubs exist, FAILs on "offline failures never exhaust", "409" and "403".

- [ ] **Step 4: Implement.** In `story_outbox_controller.dart`:

1. Replace `static const _maxAutomaticAttempts = 5;` with:

```dart
  /// Same ceiling as chat's `_maxAutomaticSendAttempts`, counted in
  /// strikes: only an unknown-shape failure or a stale intent is a strike.
  static const int maxStrikes = 5;

  /// Equal-jitter window, identical to chat_state.dart `_handleSendFailure`.
  @visibleForTesting
  static Duration backoffWindowFor(int attempts) =>
      Duration(seconds: 1 << attempts.clamp(1, 6));
```

2. In `_drive`, wrap each upload so a 409 counts as done. Add this helper and call it in place of the two `_gateway.uploadObject(...)` calls (Task 7 later resolves paths, and Task 8 adds progress and cancel):

```dart
  /// One upload step. A 409 on our own key means an earlier attempt's
  /// upload already landed (V12): the step is done; finalize re-verifies
  /// the object's size and MIME server-side.
  Future<void> _uploadStep({
    required StoryUploadIntent intent,
    required String localPath,
    required String mimeType,
  }) async {
    try {
      await _gateway.uploadObject(
        bucket: intent.bucket,
        storageKey: intent.storageKey,
        localPath: localPath,
        mimeType: mimeType,
      );
    } on StoryApiError catch (e) {
      if (e.kind == StoryFailureKind.alreadyUploaded) return;
      rethrow;
    }
  }
```

3. Replace the two `catch` clauses at the end of `_drive` with `} catch (error) { await _handleFailure(current, StoryApiError.fromFailure(error)); }`.

4. Replace `_handleFailure` with:

```dart
  Future<void> _handleFailure(StoryOutboxRecord original, StoryApiError error) async {
    final kind = error.kind;
    // A cancel removes the row itself (Task 8); nothing to record.
    if (kind == StoryFailureKind.cancelled) return;

    // Finalize UNAVAILABLE is the server's collapsed "expired intent"
    // (StoryApiError doc): structurally the same recovery as Storage 403.
    final isFinalizeUnavailable =
        original.state == StoryOutboxState.finalizing && error.code == 'UNAVAILABLE';
    final intentStale = kind == StoryFailureKind.intentStale || isFinalizeUnavailable;

    final attempts = original.attempts + 1;
    final strikes = original.strikes +
        ((kind == StoryFailureKind.unknown || intentStale) ? 1 : 0);
    final permanent = switch (kind) {
      StoryFailureKind.mediaRejected || StoryFailureKind.mediaMissing => true,
      StoryFailureKind.refused => !isFinalizeUnavailable || strikes >= maxStrikes,
      StoryFailureKind.offline || StoryFailureKind.rateLimited => false,
      _ => strikes >= maxStrikes,
    };

    final windowMillis = backoffWindowFor(attempts).inMilliseconds;
    final backoffMillis =
        (windowMillis ~/ 2) + _backoffJitter.nextInt(windowMillis ~/ 2 + 1);

    final updated = original.copyWith(
      attempts: attempts,
      strikes: strikes,
      lastErrorCode: error.code,
      state: permanent
          ? StoryOutboxState.failedPermanent
          : (intentStale ? StoryOutboxState.queued : original.state),
      clearIntents: intentStale,
      nextAttemptAt: permanent
          ? null
          : DateTime.now().add(Duration(milliseconds: backoffMillis)),
      clearNextAttemptAt: permanent,
    );

    await _store.put(_userId, updated);
    await _refreshState();

    if (!permanent) {
      final delay = updated.nextAttemptAt?.difference(DateTime.now()) ?? Duration.zero;
      Timer(delay.isNegative ? Duration.zero : delay, () {
        unawaited(flush());
      });
    }
  }
```

Keep `_intents.remove(...)` while the in-memory map still exists (Task 5 removes it). Call `_intents.remove(original.clientStoryId)` when `intentStale`.

5. In `retry`, add `strikes: 0` and `clearIntents: true` to the `copyWith`.

6. Update the class header comment's taxonomy bullets to describe strikes, kinds and the 409/403 handling, replacing ":18-42". This edits the doc comment only.

- [ ] **Step 5: Update the two old tests (allowed edit).** In `story_outbox_controller_test.dart`:
  - In "a permanent failure is reached after a bounded number of retryable failures" (`:498-538`), rename it to `'a permanent failure is reached after a bounded number of unknown-shape failures, not an unbounded spin'` and replace `StoryApiError.network()` with `const StoryApiError(code: 'server_error', message: 'boom', retryable: false)`.
  - In "retry restarts the backoff cycle…" (`:556`), make the same replacement of the driving error. Keep the rest of its assertions; `attempts` becomes `strikes` in `expect(rows.single.attempts, lessThan(5))`.

- [ ] **Step 6: Run and see everything pass**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart test/features/stories/story_outbox_controller_test.dart`
Expected: all pass.

- [ ] **Step 7: Run tests:** `flutter test test/features/stories`. Expected: all pass.

---

### Task 5: Persisted intents and re-minting near expiry

Fixes 01 #8 (a kill mid-post burns an attempt and orphans two objects) and the automatic-path half of 01 #3 (an intent that expired while suspended is reused).

**Files:**
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart`: delete `_IntentPair` (`:87-98`) and `_intents` (`:115`); rewrite `_ensureIntents` (`:350-370`); `_drive` uses `record.mediaIntent` / `record.thumbnailIntent`; `retry`/`discard` drop their `_intents.remove`; use `clock.now()` everywhere the controller reads the time.
- Test: `test/features/stories/story_outbox_policy_test.dart` (append a group).

**Interfaces:**
- Consumes: Task 3's record intents; `package:clock`.
- Produces: `static const Duration StoryOutboxController.remintMargin = Duration(minutes: 2)`. The controller reads the time only through `clock.now()`.

- [ ] **Step 1: Write the failing tests.** Append to `story_outbox_policy_test.dart` (add `import 'package:clock/clock.dart';` and `import 'package:attune/features/stories/data/story_repository.dart';` if not present):

```dart
  group('persisted intents (01 #8, V13)', () {
    StoryUploadIntent intent(String kind, DateTime expiresAt) => StoryUploadIntent(
      intentId: 'persisted-$kind',
      storageKey: 'persisted-key-$kind',
      bucket: 'story-media',
      expiresAt: expiresAt,
    );

    test('a restart mid-post resumes the same keys and skips the media upload',
        () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final soon = DateTime.now().add(const Duration(minutes: 10));
      final record = outboxRecord(dir, state: StoryOutboxState.uploadingThumbnail)
          .copyWith(
            mediaIntent: intent('media', soon),
            thumbnailIntent: intent('thumbnail', soon),
          );
      await h.store.put(outboxUserId, record);

      await h.controller().flush();

      expect(h.gateway.intentCalls, isEmpty, reason: 'no fresh pair minted');
      expect(h.gateway.uploads.map((u) => u.key), ['persisted-key-thumbnail']);
      expect(h.gateway.finalizes.single,
          (media: 'persisted-media', thumb: 'persisted-thumbnail'));
    });

    test('minted intents are written to the store before uploading', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.uploadScript.add(StoryApiError.network());
      await h.controller().enqueue(outboxRecord(dir));
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.hasIntents, isTrue);
      expect(row.mediaIntent!.intentId, startsWith('intent-media'));
    });

    test('an intent within 2 minutes of expiry is re-minted, with no strike',
        () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final nearly = DateTime.now().add(const Duration(seconds: 90));
      final record = outboxRecord(dir, state: StoryOutboxState.uploadingThumbnail)
          .copyWith(
            mediaIntent: intent('media', nearly),
            thumbnailIntent: intent('thumbnail', nearly),
          );
      await h.store.put(outboxUserId, record);

      await h.controller().flush();

      expect(h.gateway.intentCalls, ['media', 'thumbnail']);
      // Both objects go up again under the NEW keys: a new intent is a new key.
      expect(h.gateway.uploads.map((u) => u.key),
          ['key-media-1', 'key-thumbnail-2']);
      expect(h.gateway.finalizes.single.media, 'intent-media-1');
      expect(await h.store.readAll(outboxUserId), isEmpty);
    });

    test('device clock ahead of the server: a fresh-looking-stale intent still '
        'posts (Review Focus 1)', () async {
      // The phone is 20 minutes fast: every intent the server mints looks
      // expired the moment it lands. The record must still post, and
      // re-minting must never strike.
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentLifetime = const Duration(minutes: 15);
      await withClock(Clock.fixed(DateTime.now().add(const Duration(minutes: 20))),
          () async {
        await h.controller().enqueue(outboxRecord(dir));
      });
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.gateway.intentCalls, ['media', 'thumbnail'],
          reason: 'one fresh pair is used once even if it already looks stale');
    });

    test('a record killed mid-thumbnail by the previous build (no intents) '
        're-uploads both objects under the new pair (01 #8, Review Focus 3)',
        () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, state: StoryOutboxState.uploadingThumbnail),
      );
      await h.controller().flush();
      expect(h.gateway.uploads.map((u) => u.key),
          ['key-media-1', 'key-thumbnail-2'],
          reason: 'the media goes up again: the old code skipped it and '
              'finalize always failed');
      expect(h.gateway.finalizes.single.media, 'intent-media-1');
      final row = await h.store.readAll(outboxUserId);
      expect(row, isEmpty);
    });
  });
```

- [ ] **Step 2: Run and see them fail**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart --plain-name "persisted intents"`
Expected: FAIL. The restart test mints a new pair, and the near-expiry test reuses the old keys.

- [ ] **Step 3: Implement.** Add `import 'package:clock/clock.dart';`. Delete `_IntentPair` and `_intents`. Replace `_ensureIntents`:

```dart
  /// Re-mint before using a pair that expires within this margin (spec
  /// §4.2: 15-minute intents). Re-minting is never a strike.
  static const Duration remintMargin = Duration(minutes: 2);

  bool _nearExpiry(StoryUploadIntent intent) =>
      intent.expiresAt.difference(clock.now()) < remintMargin;

  /// Returns [record] holding a usable pair, minting one when it has none
  /// or when either is near expiry. A new pair means new keys, so a record
  /// past `uploadingMedia` goes back to it: both objects are re-uploaded.
  /// The pair is persisted (encrypted) before any upload uses it.
  ///
  /// Called once, at the start of each drive. A pair it mints is used for
  /// that whole drive even if the device clock already calls it stale
  /// (Review Focus 1): the server, not this phone, decides whether it has
  /// expired, and a refusal comes back as Storage 403 / finalize
  /// UNAVAILABLE (intentStale). A record with no pair, or one whose pair
  /// was replaced, is always at `uploadingMedia` afterwards: new keys mean
  /// both objects go up again (01 #8: the old code finalized a fresh pair
  /// whose media was never uploaded).
  Future<StoryOutboxRecord> _ensureIntents(StoryOutboxRecord record) async {
    final media = record.mediaIntent;
    final thumb = record.thumbnailIntent;
    if (media != null && thumb != null && !_nearExpiry(media) && !_nearExpiry(thumb)) {
      return record;
    }
    final freshMedia = await _gateway.createUploadIntent(
      relationshipId: record.relationshipId,
      objectKind: 'media',
      mediaType: record.mediaType.name,
      mimeType: record.mimeType,
    );
    final freshThumb = await _gateway.createUploadIntent(
      relationshipId: record.relationshipId,
      objectKind: 'thumbnail',
      mediaType: 'image',
      mimeType: 'image/jpeg',
    );
    return _persist(record.copyWith(
      mediaIntent: freshMedia,
      thumbnailIntent: freshThumb,
      state: StoryOutboxState.uploadingMedia,
    ));
  }
```

In `_drive`, replace `final pair = await _ensureIntents(current);` with `current = await _ensureIntents(current);`. Then use `current.mediaIntent!` / `current.thumbnailIntent!` in the upload steps and finalize. Do not re-check before finalize. A long upload that crosses the margin ends in finalize `UNAVAILABLE`, and Task 4 already handles that as a stale intent (re-mint and re-upload). A second check would need the drive to loop back to the uploads. On a badly skewed clock, every new drive re-mints, which costs 2 intent calls per attempt; the 64 s cap keeps that inside the server's 120/hour bound. Replace `DateTime.now()` in `flush` and `_handleFailure` with `clock.now()`. Delete every `_intents.remove(...)`; `clearIntents: true` on the record (Task 4) replaces it.

- [ ] **Step 4: Run and see them pass**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart test/features/stories/story_outbox_controller_test.dart`
Expected: all pass. The old "a manual retry does not reuse stale intents" still passes because `retry` clears the intents (Task 4).

- [ ] **Step 5: Run tests:** `flutter test test/features/stories`. Expected: all pass.

---

### Task 6: Flush on resume, reconnect and sign-in; start at app level; dispose and epoch guards

Fixes 01 #1 (no reconnect or resume flush), 01 #9 (the outbox only starts with the rings row), 01 #12 (no dispose or epoch guard; the provider rebuilds on any `User` change) and Review Focus 2 (the write-back half).

**Files:**
- Create: `lib/features/stories/presentation/state/story_outbox_triggers.dart`
- Create: `test/features/stories/story_outbox_triggers_test.dart`
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart`: constructor, `flush`, `_persist`, `_handleFailure` timer, new `dispose`, provider at `:443-448`.
- Modify: `lib/features/stories/data/story_outbox_store.dart`: add `epoch` and `wipeAll()`.
- Modify: `lib/app/app.dart:49-52` (add one microtask after the chat drainer's).

**Interfaces:**
- Consumes: `chatConnectivityProvider` (`lib/features/chat/presentation/providers/chat_experience_providers.dart`), `currentUserProvider`.
- Produces:
  - `Future<void> StoryOutboxController.flush({bool force = false})`: `force` clears `nextAttemptAt` on non-failed rows before the pass.
  - `@visibleForTesting bool StoryOutboxController.debugHasRetryTimer`
  - `int StoryOutboxStore.epoch`; `Future<void> StoryOutboxStore.wipeAll()` (deletes every row of every user and bumps `epoch`)
  - `final storyOutboxTriggersProvider = Provider<StoryOutboxTriggers>`; `class StoryOutboxTriggers { Future<void> poke(); void dispose(); }`

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_outbox_triggers_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_triggers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/outbox_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('outbox_triggers'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A row waiting out a long backoff, as after an offline failure.
  Future<void> seedWaiting(OutboxHarness h) => h.store.put(
    outboxUserId,
    outboxRecord(dir).copyWith(
      attempts: 6,
      lastErrorCode: StoryErrorCodes.network,
      nextAttemptAt: DateTime.now().add(const Duration(minutes: 5)),
    ),
  );

  test('connectivity coming back flushes a waiting story at once', () async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    final h = outboxHarness(extra: [
      chatConnectivityProvider.overrideWith((ref) => online.stream),
    ]);
    addTearDown(h.container.dispose);
    // Let the cold-start pass run first; it would post anything already
    // queued, which is a different test.
    h.container.read(storyOutboxTriggersProvider);
    await pumpEventQueue(times: 20);
    await seedWaiting(h);
    online.add(false);
    await pumpEventQueue();
    expect(h.gateway.finalizes, isEmpty);

    online.add(true);
    await pumpEventQueue(times: 50);
    expect(h.gateway.finalizes, hasLength(1));
    expect(await h.store.readAll(outboxUserId), isEmpty);
  });

  test('coming back to the foreground flushes a waiting story', () async {
    final h = outboxHarness(extra: [
      chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
    ]);
    addTearDown(h.container.dispose);
    h.container.read(storyOutboxTriggersProvider);
    await pumpEventQueue(times: 20); // the cold-start pass, on an empty queue
    await seedWaiting(h);
    final before = h.gateway.finalizes.length;

    final binding = TestWidgetsFlutterBinding.instance;
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(s);
    }
    await pumpEventQueue(times: 50);
    expect(h.gateway.finalizes.length, before + 1);
  });

  test('a cold start with someone signed in drains without opening Conversations',
      () async {
    final h = outboxHarness(extra: [
      chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
    ]);
    addTearDown(h.container.dispose);
    await h.store.put(outboxUserId, outboxRecord(dir));
    h.container.read(storyOutboxTriggersProvider); // what App.initState does
    await pumpEventQueue(times: 50);
    expect(h.gateway.finalizes, hasLength(1));
  });

  test('a user-metadata change keeps the same controller', () async {
    final user = StateProvider<User?>((_) => outboxUser());
    final h = outboxHarness(
      user: currentUserProvider.overrideWith((ref) => ref.watch(user)),
    );
    addTearDown(h.container.dispose);
    final first = h.controller();
    h.container.read(user.notifier).state = User(
      id: outboxUserId,
      appMetadata: const {},
      userMetadata: const {'name': 'renamed'},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
    );
    expect(identical(h.controller(), first), isTrue);
  });

  test('a disposed controller cancels its retry timer and writes nothing',
      () async {
    final h = outboxHarness();
    h.gateway.intentScript.add(StoryApiError.network());
    final controller = h.controller();
    await controller.enqueue(outboxRecord(dir));
    expect(controller.debugHasRetryTimer, isTrue);
    h.container.dispose();
    expect(controller.debugHasRetryTimer, isFalse);
    await controller.flush(); // must not throw (StateError) or touch the store
    expect(h.gateway.intentCalls, isEmpty);
  });

  test('a wipe mid-upload: the in-flight drive never writes the row back '
      '(Review Focus 2)', () async {
    final h = outboxHarness();
    addTearDown(h.container.dispose);
    h.gateway.uploadGate = Completer<void>();
    final drive = h.controller().enqueue(outboxRecord(dir));
    await pumpEventQueue();
    await h.store.wipeAll();
    h.gateway.uploadGate!.complete();
    await drive;
    expect(await h.store.readAll(outboxUserId), isEmpty);
    expect(h.gateway.finalizes, isEmpty);
  });

  test('App starts the story outbox triggers (01 #9)', () {
    final src = File('lib/app/app.dart').readAsStringSync();
    expect(src, contains('ref.read(storyOutboxTriggersProvider)'));
  });
}
```

- [ ] **Step 2: Run and see them fail**

Run: `flutter test test/features/stories/story_outbox_triggers_test.dart`
Expected: compile failure (`story_outbox_triggers.dart`, `wipeAll`, `debugHasRetryTimer`).

- [ ] **Step 3: Implement the store epoch.** In `story_outbox_store.dart` add:

```dart
  int _epoch = 0;

  /// Bumped by every wipe. A drive that started before a wipe compares its
  /// captured epoch before each write, so a sign-out mid-upload can never
  /// write the previous person's row back (01 #11, Review Focus 2).
  int get epoch => _epoch;

  /// Every row of every user, gone. Used by sign-out and quick exit.
  Future<void> wipeAll() async {
    _epoch++;
    await clearAll();
  }
```

- [ ] **Step 4: Implement the controller guards.** In `story_outbox_controller.dart`:

```dart
  StoryOutboxController(this._ref, this._userId) : super(const []) {
    if (_userId.isNotEmpty) unawaited(flush());
  }

  bool _disposed = false;
  Timer? _retryTimer;

  @visibleForTesting
  bool get debugHasRetryTimer => _retryTimer?.isActive ?? false;

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    super.dispose();
  }

  /// Nothing may be written once disposed or once a wipe has landed since
  /// [epoch] was captured.
  bool _stale(int epoch) => _disposed || _store.epoch != epoch;
```

Then:
- `_refreshState`: `if (_disposed) return;` before reading, and again before `state =`.
- `flush({bool force = false})`: return at once if `_disposed || _userId.isEmpty`. Capture `final epoch = _store.epoch;`. When `force`, first re-put every non-failed row with `clearNextAttemptAt: true` (skipped if `_stale(epoch)`). Pass `epoch` into `_drive(record, epoch)`.
- `_drive(StoryOutboxRecord record, int epoch)` and `_persist(record, epoch)`: `_persist` returns `record` unchanged without writing when `_stale(epoch)`, and `_drive` checks `if (_stale(epoch)) return;` after **every** `await` (each upload, intent mint and finalize). On success, also skip `_store.remove` and file deletion when stale (the wiper owns them then).
- `_handleFailure(original, error, epoch)`: `if (_stale(epoch)) return;` first. Replace the bare `Timer(...)` with:

```dart
      _retryTimer?.cancel();
      _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
        _retryTimer = null;
        if (!_disposed) unawaited(flush());
      });
```

Pass `_store.epoch` from `enqueue`, `enqueueLocally`, `retry` and `discard` through `flush`.

Key the provider on the id only:

```dart
final storyOutboxProvider =
    StateNotifierProvider<StoryOutboxController, List<StoryOutboxRecord>>((ref) {
  // Keyed on the id, not the User: a metadata update must not spin up a
  // second controller driving the same record (01 #12).
  final userId = ref.watch(currentUserProvider.select((u) => u?.id)) ?? '';
  return StoryOutboxController(ref, userId);
});
```

- [ ] **Step 5: Implement the triggers.** Create `lib/features/stories/presentation/state/story_outbox_triggers.dart`:

```dart
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Posts what is waiting without anyone opening Conversations (01 #9), the
/// story twin of `ChatOutboxDrainer`: on app resume, on connectivity
/// returning, and once for whoever is signed in (cold start and every later
/// sign-in). Warmed once from `App.initState`.
final storyOutboxTriggersProvider = Provider<StoryOutboxTriggers>((ref) {
  final triggers = StoryOutboxTriggers(ref);
  ref.onDispose(triggers.dispose);
  return triggers;
});

class StoryOutboxTriggers {
  StoryOutboxTriggers(this._ref) {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(poke()));
    _ref.listen<AsyncValue<bool>>(chatConnectivityProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        unawaited(poke());
      }
    });
    _ref.listen<User?>(currentUserProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        scheduleMicrotask(() => unawaited(_onSignedIn(next.id)));
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  /// A forced pass: backoff timers paused while backgrounded, or waiting on
  /// a network that is now back, go now.
  Future<void> poke() async {
    if (_disposed || _ref.read(currentUserProvider) == null) return;
    await _ref.read(storyOutboxProvider.notifier).flush(force: true);
  }

  Future<void> _onSignedIn(String userId) async {
    if (_disposed) return;
    // Task 9 adds the account-switch wipe here, before the flush.
    await poke();
  }

  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
```

Run `dart format` on this new file only.

In `lib/app/app.dart`, add `import 'package:attune/features/stories/presentation/state/story_outbox_triggers.dart';` and, directly after the chat drainer microtask (`:49-52`):

```dart
    // Posts queued stories on resume, reconnect and sign-in, without waiting
    // for Conversations to mount (stories Wave 2, P1).
    Future.microtask(() {
      if (!mounted) return;
      ref.read(storyOutboxTriggersProvider);
    });
```

Regression note: `app.dart` is the app root. The change is one extra provider read in its own microtask, mirroring the chat drainer's. Re-run `test/app` after.

- [ ] **Step 6: Run and see them pass**

Run: `flutter test test/features/stories/story_outbox_triggers_test.dart test/features/stories/story_outbox_policy_test.dart test/features/stories/story_outbox_controller_test.dart`
Expected: all pass.

- [ ] **Step 7: Run tests:** `flutter test test/features/stories test/app test/features/chat/chat_outbox_triggers_test.dart`. Expected: all pass.

---

### Task 7: Queued media in app-private storage (`StoryMediaVault`)

Fixes 01 #10 (purgeable `tmp/` and absolute paths that break on app update), part of 05 #2 (backup exclusion of the folder) and Review Focus 3 (legacy paths).

**Files:**
- Create: `lib/features/stories/data/story_media_vault.dart`
- Create: `test/features/stories/story_media_vault_test.dart`
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart`: `_refreshState`, `_drive` (resolve before upload), success cleanup, `discard`, `_deleteLocalFile`.
- Test: `test/features/stories/story_outbox_policy_test.dart` (append).

**Interfaces:**
- Produces:

```dart
class StoryMediaVault {
  StoryMediaVault({Future<Directory> Function()? supportDirectory});
  static const String folderName = 'story_outbox';
  Future<({String media, String thumbnail})> adopt({
    required String userId,
    required String clientStoryId,
    required String mediaPath,
    required String thumbnailPath,
  }); // moves both files in; returns paths RELATIVE to Application Support
  Future<String> resolve(String stored); // absolute passes through
  Future<StoryOutboxRecord> resolveRecord(StoryOutboxRecord record);
  Future<void> deleteFor(StoryOutboxRecord record);
  Future<void> wipeAll();
  Future<void> wipeExcept(String userId);
}
final storyMediaVaultProvider = Provider<StoryMediaVault>((ref) => StoryMediaVault());
```

- [ ] **Step 1: Write the failing vault tests.** Create `test/features/stories/story_media_vault_test.dart`:

```dart
import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/outbox_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late Directory tmp;
  late List<String> excluded;
  late StoryMediaVault vault;

  setUp(() {
    support = Directory.systemTemp.createTempSync('vault_support');
    tmp = Directory.systemTemp.createTempSync('vault_tmp');
    excluded = [];
    BackupExclusion.debugIsIOS = true;
    BackupExclusion.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, (call) async {
      excluded.add(call.arguments as String);
      return true;
    });
    vault = StoryMediaVault(supportDirectory: () async => support);
  });
  tearDown(() {
    BackupExclusion.debugIsIOS = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, null);
    support.deleteSync(recursive: true);
    tmp.deleteSync(recursive: true);
  });

  File tmpFile(String name) =>
      File(p.join(tmp.path, name))..writeAsBytesSync([1, 2, 3]);

  test('adopt moves both files out of tmp into a per-user, per-story folder', () async {
    final media = tmpFile('capture.mp4');
    final thumb = tmpFile('thumb.jpg');
    final stored = await vault.adopt(
      userId: 'u1',
      clientStoryId: 'cid-1',
      mediaPath: media.path,
      thumbnailPath: thumb.path,
    );
    expect(stored.media, 'story_outbox/u1/cid-1/media.mp4');
    expect(stored.thumbnail, 'story_outbox/u1/cid-1/thumb.jpg');
    expect(p.isRelative(stored.media), isTrue);
    expect(media.existsSync(), isFalse, reason: 'moved, not copied');
    expect(File(await vault.resolve(stored.media)).existsSync(), isTrue);
    await pumpEventQueue(); // the exclusion is sent unawaited
    expect(await vault.resolve(stored.media),
        p.join(support.path, 'story_outbox/u1/cid-1/media.mp4'));
    expect(excluded, contains(p.join(support.path, 'story_outbox')),
        reason: 'the folder is kept out of iOS/iCloud backups');
  });

  test('a legacy absolute path resolves to itself (Review Focus 3)', () async {
    final legacy = tmpFile('old.jpg').path;
    expect(await vault.resolve(legacy), legacy);
  });

  test('deleteFor removes the files and the story folder, never outside it', () async {
    final stored = await vault.adopt(
      userId: 'u1', clientStoryId: 'cid-2',
      mediaPath: tmpFile('a.jpg').path, thumbnailPath: tmpFile('b.jpg').path,
    );
    final record = outboxRecord(tmp, id: 'cid-2');
    final adopted = StoryRecordPaths.withPaths(record, stored.media, stored.thumbnail);
    await vault.deleteFor(adopted);
    expect(Directory(p.join(support.path, 'story_outbox/u1/cid-2')).existsSync(), isFalse);

    // A legacy record: its absolute files go, nothing else is touched.
    final legacy = outboxRecord(tmp, id: 'cid-3');
    await vault.deleteFor(legacy);
    expect(File(legacy.localMediaPath).existsSync(), isFalse);
    expect(tmp.existsSync(), isTrue);
  });

  test('wipeExcept keeps only the signed-in person\'s folder', () async {
    for (final user in ['u1', 'u2']) {
      await vault.adopt(
        userId: user, clientStoryId: 'c',
        mediaPath: tmpFile('$user-m.jpg').path,
        thumbnailPath: tmpFile('$user-t.jpg').path,
      );
    }
    await vault.wipeExcept('u2');
    expect(Directory(p.join(support.path, 'story_outbox/u1')).existsSync(), isFalse);
    expect(Directory(p.join(support.path, 'story_outbox/u2')).existsSync(), isTrue);
    await vault.wipeAll();
    expect(Directory(p.join(support.path, 'story_outbox')).existsSync(), isFalse);
  });
}
```

(`StoryRecordPaths.withPaths` is a small extension the vault file exports, because `copyWith` deliberately does not take paths.)

- [ ] **Step 2: Write the failing controller tests.** Append to `story_outbox_policy_test.dart`:

```dart
  group('vault paths (01 #10)', () {
    test('a relative record resolves against the vault before upload, and its '
        'folder goes on success', () async {
      final support = Directory.systemTemp.createTempSync('policy_support');
      addTearDown(() => support.deleteSync(recursive: true));
      final vault = StoryMediaVault(supportDirectory: () async => support);
      final h = outboxHarness(extra: [
        storyMediaVaultProvider.overrideWithValue(vault),
      ]);
      addTearDown(h.container.dispose);
      final raw = outboxRecord(dir);
      final stored = await vault.adopt(
        userId: outboxUserId, clientStoryId: raw.clientStoryId,
        mediaPath: raw.localMediaPath, thumbnailPath: raw.localThumbnailPath,
      );
      await h.controller().enqueue(
        StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail),
      );
      expect(h.gateway.uploads.first.path,
          '${support.path}/story_outbox/$outboxUserId/cid-1/media.jpg');
      expect(Directory('${support.path}/story_outbox/$outboxUserId/cid-1').existsSync(),
          isFalse);
    });

    test('the controller exposes resolved (absolute) paths for the ring', () async {
      final support = Directory.systemTemp.createTempSync('policy_support2');
      addTearDown(() => support.deleteSync(recursive: true));
      final vault = StoryMediaVault(supportDirectory: () async => support);
      final h = outboxHarness(extra: [
        storyMediaVaultProvider.overrideWithValue(vault),
      ]);
      addTearDown(h.container.dispose);
      h.gateway.intentScript.add(StoryApiError.network());
      final raw = outboxRecord(dir);
      final stored = await vault.adopt(
        userId: outboxUserId, clientStoryId: raw.clientStoryId,
        mediaPath: raw.localMediaPath, thumbnailPath: raw.localThumbnailPath,
      );
      await h.controller().enqueue(
        StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail),
      );
      final shown = h.container.read(storyOutboxProvider).single;
      expect(p.isAbsolute(shown.localThumbnailPath), isTrue);
      // The store still holds the relative form.
      expect((await h.store.readAll(outboxUserId)).single.localThumbnailPath,
          stored.thumbnail);
    });
  });
```

(Add imports for `story_media_vault.dart` and `package:path/path.dart` as `p`.)

- [ ] **Step 3: Run and see them fail**

Run: `flutter test test/features/stories/story_media_vault_test.dart test/features/stories/story_outbox_policy_test.dart`
Expected: compile failure.

- [ ] **Step 4: Implement the vault.** Create `lib/features/stories/data/story_media_vault.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where a queued story's media waits (spec §6.1: "app-private storage
/// until success or explicit discard"): Application Support, never the
/// purgeable tmp/ the preparers write to (01 #10). Layout:
/// `story_outbox/<userId>/<clientStoryId>/{media.<ext>,thumb.jpg}`.
///
/// Records store paths RELATIVE to Application Support, because the iOS
/// container path changes on an app update. A legacy absolute path (queued
/// by an older build) resolves to itself.
class StoryMediaVault {
  StoryMediaVault({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const String folderName = 'story_outbox';

  final Future<Directory> Function() _supportDirectory;
  String? _supportPath;

  Future<String> _support() async =>
      _supportPath ??= p.normalize((await _supportDirectory()).path);

  Future<Directory> _root({bool create = false}) async {
    final root = Directory(p.join(await _support(), folderName));
    if (create) {
      await root.create(recursive: true);
      // iOS: Application Support is backed up unless excluded (05 #2).
      unawaited(BackupExclusion.exclude(root.path));
    }
    return root;
  }

  Future<({String media, String thumbnail})> adopt({
    required String userId,
    required String clientStoryId,
    required String mediaPath,
    required String thumbnailPath,
  }) async {
    final root = await _root(create: true);
    final folder = Directory(p.join(root.path, userId, clientStoryId));
    await folder.create(recursive: true);
    final ext = p.extension(mediaPath).isEmpty ? '.bin' : p.extension(mediaPath);
    final media = p.join(folder.path, 'media$ext');
    final thumb = p.join(folder.path, 'thumb.jpg');
    await _move(mediaPath, media);
    await _move(thumbnailPath, thumb);
    final support = await _support();
    return (
      media: p.relative(media, from: support),
      thumbnail: p.relative(thumb, from: support),
    );
  }

  /// Rename when on the same volume; copy then delete otherwise.
  static Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      try {
        await File(from).delete();
      } catch (_) {}
    }
  }

  Future<String> resolve(String stored) async =>
      p.isAbsolute(stored) ? stored : p.join(await _support(), stored);

  Future<StoryOutboxRecord> resolveRecord(StoryOutboxRecord record) async {
    if (p.isAbsolute(record.localMediaPath) &&
        p.isAbsolute(record.localThumbnailPath)) {
      return record;
    }
    return StoryRecordPaths.withPaths(
      record,
      await resolve(record.localMediaPath),
      await resolve(record.localThumbnailPath),
    );
  }

  /// The record's files and, for a vault record, its story folder. Never
  /// deletes anything outside `story_outbox/` other than the record's own
  /// two legacy files.
  Future<void> deleteFor(StoryOutboxRecord record) async {
    for (final stored in [record.localMediaPath, record.localThumbnailPath]) {
      try {
        final file = File(await resolve(stored));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (!p.isAbsolute(record.localMediaPath)) {
      final folder = Directory(p.dirname(await resolve(record.localMediaPath)));
      final root = (await _root()).path;
      if (p.isWithin(root, folder.path)) {
        try {
          if (await folder.exists()) await folder.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> wipeAll() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<void> wipeExcept(String userId) async {
    final root = await _root();
    if (!await root.exists()) return;
    await for (final entry in root.list()) {
      if (entry is Directory && p.basename(entry.path) != userId) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

/// Paths are fixed for a record's life except when the vault resolves or
/// adopts them, so they are not part of `copyWith`.
extension StoryRecordPaths on StoryOutboxRecord {
  static StoryOutboxRecord withPaths(
    StoryOutboxRecord r,
    String media,
    String thumbnail,
  ) => StoryOutboxRecord.fromJson({
    ...r.toJson(),
    'localMediaPath': media,
    'localThumbnailPath': thumbnail,
  });
}

final storyMediaVaultProvider = Provider<StoryMediaVault>(
  (ref) => StoryMediaVault(),
);
```

Run `dart format` on this new file.

- [ ] **Step 5: Wire the controller.** In `story_outbox_controller.dart`:
- Add `StoryMediaVault get _vault => _ref.read(storyMediaVaultProvider);`.
- `_refreshState`: `final rows = await _store.readAll(_userId); final shown = await Future.wait(rows.map(_vault.resolveRecord)); if (!_disposed) state = shown;`.
- In the media and thumbnail upload steps, pass `localPath: await _vault.resolve(current.localMediaPath)` (and the thumbnail equivalent).
- Success and `discard`: replace the two `_deleteLocalFile` calls with `await _vault.deleteFor(current)`. Delete `_deleteLocalFile`.
- `flush`'s `state = queue;` becomes `await _refreshState();`.

- [ ] **Step 6: Run and see them pass:** `flutter test test/features/stories/story_media_vault_test.dart test/features/stories/story_outbox_policy_test.dart test/features/stories/story_outbox_controller_test.dart`. Expected: all pass. The old "discard deletes the local files" passes because its absolute paths go through `deleteFor`.

- [ ] **Step 7: Run tests:** `flutter test test/features/stories`. Expected: all pass. `story_rings_test` uses absolute `/tmp/...` paths, which pass straight through.

---

### Task 8: Cancel an in-flight post, and byte progress

Fixes 01 #13 (no cancel; step-based progress). The UI is Task 18.

**Files:**
- Modify: `lib/features/stories/presentation/state/story_outbox_controller.dart`
- Test: `test/features/stories/story_outbox_policy_test.dart` (append)

**Interfaces:**
- Consumes: `ChatUploadCancelToken`, `raceUploadCancel` (chat uploader, read-only).
- Produces:
  - `enum StoryCancelOutcome { cancelled, alreadyPosting, notFound }`
  - `Future<StoryCancelOutcome> StoryOutboxController.cancel(String clientStoryId)`
  - `final storyUploadProgressProvider = StateProvider<Map<String, double>>((ref) => const {});` (0..1 media-upload fraction per `clientStoryId`; not persisted)

- [ ] **Step 1: Write the failing tests.** Append:

```dart
  group('cancel and progress (01 #13)', () {
    test('cancel mid-upload aborts, removes the row and its files', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.uploadGate = Completer<void>();
      final record = outboxRecord(dir);
      final drive = h.controller().enqueue(record);
      await pumpEventQueue();
      expect(h.container.read(storyUploadProgressProvider)['cid-1'], 0.5);

      final outcome = await h.controller().cancel('cid-1');
      await drive;

      expect(outcome, StoryCancelOutcome.cancelled);
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(File(record.localMediaPath).existsSync(), isFalse);
      expect(h.gateway.finalizes, isEmpty);
      expect(h.container.read(storyUploadProgressProvider), isEmpty);
    });

    test('once finalize is sent, cancel says it is already posting', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.finalizeGate = Completer<void>();
      final drive = h.controller().enqueue(outboxRecord(dir));
      await pumpEventQueue(times: 20);
      expect((await h.store.readAll(outboxUserId)).single.state,
          StoryOutboxState.finalizing);

      expect(await h.controller().cancel('cid-1'), StoryCancelOutcome.alreadyPosting);
      h.gateway.finalizeGate!.complete();
      await drive;
      expect(h.gateway.finalizes, hasLength(1));
    });

    test('cancelling a story waiting on its backoff needs no network', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript.add(StoryApiError.network());
      await h.controller().enqueue(outboxRecord(dir));
      expect(await h.controller().cancel('cid-1'), StoryCancelOutcome.cancelled);
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.controller().debugHasRetryTimer, isFalse);
    });
  });
```

(Add `import 'dart:async';` to the file.)

- [ ] **Step 2: Run and see them fail**

Run: `flutter test test/features/stories/story_outbox_policy_test.dart --plain-name "cancel and progress"`
Expected: compile failure.

- [ ] **Step 3: Implement.** In the controller:

```dart
enum StoryCancelOutcome { cancelled, alreadyPosting, notFound }

final storyUploadProgressProvider = StateProvider<Map<String, double>>(
  (ref) => const {},
);
```

State: `final Map<String, ChatUploadCancelToken> _tokens = {};` and `final Set<String> _cancelled = {};`.
- In `_drive`, create `final token = _tokens[id] = ChatUploadCancelToken();` at the start and remove it in a `finally`. Wrap each intent call as `await raceUploadCancel(_gateway.createUploadIntent(...), token)`. Pass `cancelToken: token` to `uploadObject`. For the media upload, pass:

```dart
onProgress: (sent, total) {
  if (total <= 0 || _disposed) return;
  final fraction = (sent / total).clamp(0.0, 1.0);
  final progress = _ref.read(storyUploadProgressProvider.notifier);
  final previous = progress.state[current.clientStoryId] ?? -1;
  if (fraction - previous < 0.01 && fraction < 1) return; // ~100 updates max
  progress.state = {...progress.state, current.clientStoryId: fraction};
},
```

- After each await in `_drive`, `if (_cancelled.contains(id)) return;` (alongside the epoch check). `_persist` also refuses when `_cancelled.contains(record.clientStoryId)`.
- In `_drive`'s `finally`: drop the id from the progress map.
- `_handleFailure` already returns for `cancelled` (Task 4).

```dart
  /// Stops a story before it posts (01 #13). Refused once finalize has been
  /// sent: the post may already exist, and Delete-from-reel owns that case.
  Future<StoryCancelOutcome> cancel(String clientStoryId) async {
    final rows = await _store.readAll(_userId);
    final record = rows.where((r) => r.clientStoryId == clientStoryId).firstOrNull;
    if (record == null) return StoryCancelOutcome.notFound;
    if (record.state == StoryOutboxState.finalizing &&
        _inFlight.contains(clientStoryId)) {
      return StoryCancelOutcome.alreadyPosting;
    }
    _cancelled.add(clientStoryId);
    _tokens[clientStoryId]?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    await _vault.deleteFor(record);
    await _store.remove(_userId, clientStoryId);
    final progress = _ref.read(storyUploadProgressProvider.notifier);
    progress.state = {...progress.state}..remove(clientStoryId);
    await _refreshState();
    // Other rows may still be waiting on the timer just cancelled.
    unawaited(flush());
    return StoryCancelOutcome.cancelled;
  }
```

`_inFlight` already exists. Make sure the finalize step is reached with `_inFlight` still holding the id (it does: `flush` adds it around `_drive`).

- [ ] **Step 4: Run and see them pass:** `flutter test test/features/stories/story_outbox_policy_test.dart`. Expected: PASS.

- [ ] **Step 5: Run tests:** `flutter test test/features/stories`. Expected: all pass.

---

### Task 9: Wipe the story outbox on sign-out, quick exit and account switch

Fixes 01 #11, 05 #2 and 07b V9 / G9.

**Files:**
- Create: `lib/features/stories/data/story_outbox_wipe.dart`
- Create: `test/features/stories/story_outbox_sign_out_test.dart`
- Modify: `lib/features/stories/data/story_outbox_backend_base.dart`, `story_outbox_backend_io.dart`, `story_outbox_backend_stub.dart` (`removeOtherUsers`)
- Modify: `lib/features/stories/data/story_outbox_store.dart` (`removeOtherUsers`)
- Modify: `lib/features/auth/providers/auth_provider.dart:157-216` (additive)
- Modify: `lib/features/safety/data/safety_sign_out.dart:36-42` (additive)
- Modify: `lib/features/stories/presentation/state/story_outbox_triggers.dart` (`_onSignedIn`)
- Test: `test/features/stories/story_outbox_triggers_test.dart` (append)

**Interfaces:**
- Consumes: `StoryOutboxStore.wipeAll` (Task 6); `StoryMediaVault.wipeAll` / `wipeExcept` (Task 7).
- Produces:

```dart
class StoryOutboxWiper {
  StoryOutboxWiper(this._ref, {this.bound = const Duration(seconds: 3)});
  final Duration bound;
  Future<void> wipeAll();            // never throws; holds the caller at most [bound]
  Future<void> wipeExcept(String userId);
}
final storyOutboxWiperProvider = Provider<StoryOutboxWiper>((ref) => StoryOutboxWiper(ref));
```

`Future<void> StoryOutboxBackend.removeOtherUsers(String keepUserId)` and the matching `StoryOutboxStore.removeOtherUsers` (bumps `epoch`).

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_outbox_sign_out_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/services/auth_service.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_outbox_wipe.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/outbox_fakes.dart';

class _FakeAuth implements AuthService {
  bool signedOut = false;
  @override
  Future<void> signOut() async => signedOut = true;
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache implements ChatCacheService {
  @override
  Future<void> clearAll() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The chat stores sign-out also wipes, faked so the suite never touches a
// plugin (same posture as auth_sign_out_media_wipe_test.dart).
class _NoopImageCache implements ChatImageCache {
  @override
  Future<void> clear() async {}
  @override
  Future<void> removeKeys(Iterable<String> keys) async {}
}

class _NoopMediaCache implements ChatMediaCache {
  @override
  Future<void> clear() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StuckVault extends StoryMediaVault {
  _StuckVault(Directory d) : super(supportDirectory: () async => d);
  @override
  Future<void> wipeAll() => Completer<void>().future; // never finishes
}

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late Directory tmp;
  setUp(() {
    support = Directory.systemTemp.createTempSync('wipe_support');
    tmp = Directory.systemTemp.createTempSync('wipe_tmp');
  });
  tearDown(() {
    support.deleteSync(recursive: true);
    tmp.deleteSync(recursive: true);
  });

  Future<({ProviderContainer container, StoryOutboxStore store, _FakeAuth auth, String folder})>
      seeded({StoryMediaVault? vault, List<Override> extra = const []}) async {
    final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
    final v = vault ?? StoryMediaVault(supportDirectory: () async => support);
    final auth = _FakeAuth();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox()),
      GoRoute(path: RouteNames.intro, builder: (_, __) => const SizedBox()),
    ]);
    addTearDown(router.dispose);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(null),
      storyOutboxStoreProvider.overrideWithValue(store),
      storyMediaVaultProvider.overrideWithValue(v),
      authServiceProvider.overrideWithValue(auth),
      chatCacheServiceProvider.overrideWithValue(_FakeCache()),
      chatImagePickerProvider.overrideWithValue(
        ChatImagePicker(stagingDirectory: () async => support),
      ),
      chatMediaCacheProvider.overrideWithValue(_NoopMediaCache()),
      chatImageCacheProvider.overrideWithValue(_NoopImageCache()),
      signOutHooksProvider.overrideWithValue(const SignOutHooks()),
      routingNotifierProvider.overrideWith((ref) => RoutingNotifier()),
      appRouterProvider.overrideWithValue(router),
      ...extra,
    ]);
    addTearDown(container.dispose);
    final raw = outboxRecord(tmp);
    final stored = await StoryMediaVault(supportDirectory: () async => support).adopt(
      userId: outboxUserId, clientStoryId: raw.clientStoryId,
      mediaPath: raw.localMediaPath, thumbnailPath: raw.localThumbnailPath,
    );
    await store.put(outboxUserId,
        StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail));
    return (
      container: container, store: store, auth: auth,
      folder: '${support.path}/story_outbox/$outboxUserId/cid-1',
    );
  }

  test('sign-out leaves no queued story row or capture on the phone', () async {
    final t = await seeded();
    await t.container.read(authOperationsProvider).signOut();
    expect(await t.store.readAll(outboxUserId), isEmpty);
    expect(Directory(t.folder).existsSync(), isFalse);
    expect(t.auth.signedOut, isTrue);
  });

  test('quick-exit sign-out wipes too, even when AuthOperations is busy', () async {
    final t = await seeded(extra: [
      authOperationsProvider.overrideWith((ref) => _BusyAuthOps(ref)),
    ]);
    await safetySignOut(t.container.read(_refProvider));
    expect(await t.store.readAll(outboxUserId), isEmpty);
    expect(Directory(t.folder).existsSync(), isFalse);
  });

  test('a stuck wipe never holds sign-out past its bound', () async {
    final t = await seeded(
      vault: _StuckVault(support),
      extra: [
        storyOutboxWiperProvider.overrideWith(
          (ref) => StoryOutboxWiper(ref, bound: const Duration(milliseconds: 100)),
        ),
      ],
    );
    await t.container.read(authOperationsProvider).signOut().timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('a stuck story wipe held the sign-out'),
    );
    expect(t.auth.signedOut, isTrue);
    expect(await t.store.readAll(outboxUserId), isEmpty,
        reason: 'the rows go even when the file wipe is stuck');
  });
}

class _BusyAuthOps extends AuthOperations {
  _BusyAuthOps(super.ref);
  @override
  Future<void> signOut() async =>
      throw StateError('Another auth operation is already in progress.');
}
```

Append to `story_outbox_triggers_test.dart`:

```dart
  test('an account switch wipes the other person\'s queued stories and files',
      () async {
    final support = Directory.systemTemp.createTempSync('switch_support');
    addTearDown(() => support.deleteSync(recursive: true));
    final vault = StoryMediaVault(supportDirectory: () async => support);
    final user = StateProvider<User?>((_) => outboxUser('previous'));
    final h = outboxHarness(
      user: currentUserProvider.overrideWith((ref) => ref.watch(user)),
      extra: [
        storyMediaVaultProvider.overrideWithValue(vault),
        chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(h.container.dispose);
    h.gateway.intentScript.add(StoryApiError.network()); // keep it queued
    final raw = outboxRecord(dir);
    final stored = await vault.adopt(
      userId: 'previous', clientStoryId: raw.clientStoryId,
      mediaPath: raw.localMediaPath, thumbnailPath: raw.localThumbnailPath,
    );
    await h.store.put('previous',
        StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail));
    h.container.read(storyOutboxTriggersProvider);
    await pumpEventQueue(times: 20);

    h.container.read(user.notifier).state = outboxUser('next');
    await pumpEventQueue(times: 50);

    expect(await h.store.readAll('previous'), isEmpty);
    expect(Directory('${support.path}/story_outbox/previous').existsSync(), isFalse);
  });
```

(Add imports for `story_media_vault.dart` to that file.)

- [ ] **Step 2: Run and see them fail**

Run: `flutter test test/features/stories/story_outbox_sign_out_test.dart test/features/stories/story_outbox_triggers_test.dart`
Expected: compile failure (`story_outbox_wipe.dart`), then the wipe assertions FAIL.

- [ ] **Step 3: Implement the backend and store.** In `story_outbox_backend_base.dart`, add `Future<void> removeOtherUsers(String keepUserId);`. In the io backend:

```dart
  @override
  Future<void> removeOtherUsers(String keepUserId) => _database.customStatement(
    'DELETE FROM story_outbox WHERE user_id <> ?',
    [keepUserId],
  );
```

In the stub: `_rows.removeWhere((key, _) => !key.startsWith('$keepUserId:'));`. In the store:

```dart
  /// Account switch: every row not belonging to [keepUserId] goes.
  Future<void> removeOtherUsers(String keepUserId) async {
    await _ensureInitialized();
    _epoch++;
    await _backend.removeOtherUsers(keepUserId);
  }
```

- [ ] **Step 4: Implement the wiper.** Create `lib/features/stories/data/story_outbox_wipe.dart`:

```dart
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Spec §6.1: "logout/account removal clears them." Rows first (their own
/// try, so a stuck file wipe never leaves a row that would auto-post on the
/// next sign-in), then the capture files. Never throws; holds the caller at
/// most [bound], like chat's staging wipe.
class StoryOutboxWiper {
  StoryOutboxWiper(this._ref, {this.bound = const Duration(seconds: 3)});

  final Ref _ref;
  final Duration bound;

  Future<void> wipeAll() => _run(
    rows: () => _ref.read(storyOutboxStoreProvider).wipeAll(),
    files: () => _ref.read(storyMediaVaultProvider).wipeAll(),
  );

  Future<void> wipeExcept(String userId) => _run(
    rows: () => _ref.read(storyOutboxStoreProvider).removeOtherUsers(userId),
    files: () => _ref.read(storyMediaVaultProvider).wipeExcept(userId),
  );

  Future<void> _run({
    required Future<void> Function() rows,
    required Future<void> Function() files,
  }) async {
    try {
      await rows().timeout(bound);
    } catch (e) {
      debugPrint('⚠️ [STORIES] outbox row wipe failed: ${e.runtimeType}');
    }
    try {
      await files().timeout(bound);
    } catch (e) {
      debugPrint('⚠️ [STORIES] outbox file wipe failed: ${e.runtimeType}');
    }
  }
}

final storyOutboxWiperProvider = Provider<StoryOutboxWiper>(
  (ref) => StoryOutboxWiper(ref),
);
```

Run `dart format` on this new file.

- [ ] **Step 5: Wire sign-out (shared file, additive).** In `auth_provider.dart` add `import 'package:attune/features/stories/data/story_outbox_wipe.dart';`. Inside `signOut`, after `wipeImages()` is declared, add:

```dart
      Future<void> wipeStories() async {
        try {
          // Story outbox rows and queued captures (stories Wave 2, P2):
          // spec §6.1 "logout/account removal clears them". Bounded by its
          // owner (3 s); its own try so nothing else is skipped.
          await ref.read(storyOutboxWiperProvider).wipeAll();
        } catch (e) {
          debugPrint('⚠️ [AUTH] story outbox wipe failed on sign-out: ${e.runtimeType}');
        }
      }
```

and change only the `wipe()` line to `Future.wait([wipeQueue(), wipeMedia(), wipeImages(), wipeStories()]);`. Nothing else in `signOut` changes. Regression note: `auth_provider.dart` is shared. The story wipe runs side by side and is bounded, so the sign-out bound is unchanged. Re-run `test/features/auth`.

In `safety_sign_out.dart`, add the import and, as the first statement inside the existing `try {` at `:36` (before `clearTogetherDeviceSurfaces()`):

```dart
    // The AuthOperations path above may have been refused (busy); wipe the
    // story outbox here too. A repeat is a no-op.
    await ref.read(storyOutboxWiperProvider).wipeAll();
```

The wiper never throws, so it cannot skip the clears after it.

- [ ] **Step 6: Wire the account switch.** In `StoryOutboxTriggers._onSignedIn`, before `await poke();`:

```dart
    // Account switch: any sign-in (cold start included) wipes every OTHER
    // person's queued stories and captures, so a session that ended
    // without a sign-out never leaves them behind (05 #2).
    await _ref.read(storyOutboxWiperProvider).wipeExcept(userId);
```

- [ ] **Step 7: Run and see them pass:** `flutter test test/features/stories/story_outbox_sign_out_test.dart test/features/stories/story_outbox_triggers_test.dart`. Expected: PASS.

- [ ] **Step 8: Run tests:** `flutter test test/features/stories test/features/auth test/features/safety`. Expected: all pass. In `auth_sign_out_media_wipe_test`, the default `StoryOutboxStore()` throws `MissingPluginException` at once, which is caught and bounded, so the timing assertions hold. If a timing assertion there fails, override `storyOutboxWiperProvider` in that suite's container with `StoryOutboxWiper(ref, bound: Duration.zero)`. That is an allowed harness-only edit; report it.

---

### Task 10: Keep the outbox out of backups (iOS and Android)

Fixes 05 #2 and 07b G9 (the backup half).

**Files:**
- Modify: `lib/features/stories/data/story_outbox_backend_io.dart:44-64` (exclude the DB files after open)
- Modify: `android/app/src/main/res/xml/backup_rules.xml`, `data_extraction_rules.xml`
- Create: `test/features/stories/story_outbox_backup_test.dart`
- Modify: `test/core/android_manifest_test.dart` (add one test)

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_outbox_backup_test.dart`:

```dart
import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/stories/data/story_outbox_backend_io.dart' as io;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late List<String> excluded;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('story_outbox_backup');
    excluded = [];
    BackupExclusion.debugIsIOS = true;
    BackupExclusion.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, (call) async {
      excluded.add(call.arguments as String);
      return true;
    });
  });
  tearDown(() {
    BackupExclusion.debugIsIOS = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, null);
    dir.deleteSync(recursive: true);
  });

  test('opening the outbox keeps its database files out of iOS backups', () async {
    final file = File('${dir.path}/attune_story_outbox.sqlite');
    final backend = io.createStoryOutboxBackend(file: file);
    await backend.init();
    await backend.put('u1', 'c1', 'payload', 1);
    await backend.close();
    final reopened = io.createStoryOutboxBackend(file: file);
    await reopened.init();
    await pumpEventQueue();
    expect(excluded, contains(file.path));
    expect(excluded, contains('${file.path}-wal'));
    await reopened.close();
  });
}
```

Add to `test/core/android_manifest_test.dart`:

```dart
  test('backups never carry the story outbox or its queued captures', () {
    for (final path in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      final sections = path.contains('extraction')
          ? [
              xml.substring(xml.indexOf('<cloud-backup>'), xml.indexOf('</cloud-backup>')),
              xml.substring(xml.indexOf('<device-transfer>'), xml.indexOf('</device-transfer>')),
            ]
          : [xml];
      for (final section in sections) {
        for (final entry in [
          'attune_story_outbox.sqlite',
          'attune_story_outbox.sqlite-wal',
          'attune_story_outbox.sqlite-shm',
          'story_outbox/',
        ]) {
          expect(section, contains('<exclude domain="file" path="$entry" />'),
              reason: '$path must exclude $entry');
        }
      }
    }
  });
```

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/stories/story_outbox_backup_test.dart test/core/android_manifest_test.dart`. Expected: FAIL (nothing is excluded; the XML entries are missing).

- [ ] **Step 3: Implement.** In `story_outbox_backend_io.dart`, import `dart:async` and `package:attune/core/services/storage/backup_exclusion.dart`. At the end of `init()`:

```dart
    // iOS backs up Application Support: keep the queue out of device and
    // iCloud backups (Android: backup_rules.xml / data_extraction_rules.xml).
    // Defence in depth — payloads are already AES-GCM encrypted (05 #2).
    for (final suffix in const ['', '-wal', '-shm']) {
      final path = '${file.path}$suffix';
      if (File(path).existsSync()) {
        unawaited(BackupExclusion.exclude(path, once: false));
      }
    }
```

In **both** Android XMLs, in every section (`full-backup-content`; `cloud-backup`; `device-transfer`), add after the `chat_prepared/` line:

```xml
        <exclude domain="file" path="attune_story_outbox.sqlite" />
        <exclude domain="file" path="attune_story_outbox.sqlite-wal" />
        <exclude domain="file" path="attune_story_outbox.sqlite-shm" />
        <exclude domain="file" path="story_outbox/" />
```

Extend each file's header comment by one clause: "and the story outbox and its queued captures (STORIES.md §6.1)". `getApplicationSupportDirectory()` is `filesDir` on Android, the same domain the chat entries rely on.

- [ ] **Step 4: Run and see them pass:** the same command as Step 2. Expected: PASS.

- [ ] **Step 5: Run tests:** `flutter test test/core test/features/stories test/features/safety/quick_exit_wiring_test.dart test/features/chat/chat_backup_exclusion_test.dart`. Expected: all pass.

---
### Task 11: Embedder-chosen resolution (stories `veryHigh`, streaks unchanged)

Fixes 01 #5 / V15 (stories capture at 640×480 on iOS).

**Files:**
- Create: `test/features/stories/support/capture_fakes.dart` (shared camera/preparer fakes and the story-camera harness for the new suites)
- Create: `test/features/stories/story_camera_config_test.dart`
- Modify: `lib/features/chat/presentation/screens/capture_camera_screen.dart`: constructor and fields at `:52-96`; `_startPreview` at `:198-213`.
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart:383-390` (pass the preset).
- Modify (allowed edit): `test/features/stories/capture_camera_test.dart`: `_FakeCameraPlatform` records `MediaSettings`; one new test.

**Interfaces:**
- Produces: `CaptureCameraScreen({..., ResolutionPreset resolutionPreset = ResolutionPreset.medium})`. Support file: `FakeCameraPlatform`, `FakeVideoPreparer`, `FakeImagePreparer`, `writeJpeg`, `StoryCameraHarness`, `storyCameraContainer`, `pumpStoryCamera`, `tapShutterOnly`, `settleIo`.

- [ ] **Step 1: Write the shared fakes.** Create `test/features/stories/support/capture_fakes.dart`:

```dart
// Camera and preparer doubles for the Wave 2 story-camera suites. The older
// capture_camera_test.dart / story_camera_test.dart keep their own.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'outbox_fakes.dart';

class FakeCameraPlatform extends CameraPlatform {
  FakeCameraPlatform({required this.videoPath, required this.photoPath});

  final String videoPath;
  final String photoPath;
  int _nextCameraId = 0;
  int createCalls = 0;
  int disposeCalls = 0;
  int takePictureCalls = 0;
  int startVideoCalls = 0;
  int stopVideoCalls = 0;
  final settings = <MediaSettings>[];

  /// Thrown from create when the settings ask for audio (mic denied).
  CameraException? audioDenied;

  /// Thrown from create always (camera denied).
  CameraException? cameraDenied;

  /// Thrown from stopVideoRecording.
  CameraException? stopError;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'fake-back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async {
    createCalls++;
    settings.add(mediaSettings);
    if (cameraDenied != null) throw cameraDenied!;
    if (mediaSettings.enableAudio && audioDenied != null) throw audioDenied!;
    return _nextCameraId++;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
        cameraId, 720, 1280, ExposureMode.auto, false, FocusMode.auto, false,
      ));

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    startVideoCalls++;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopVideoCalls++;
    if (stopError != null) throw stopError!;
    return XFile(videoPath);
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCalls++;
    return XFile(photoPath);
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

/// Sync file I/O on purpose: testWidgets' FakeAsync zone never completes an
/// async dart:io future without runAsync (story_camera_test.dart header).
class FakeImagePreparer extends CaptureImagePreparer {
  FakeImagePreparer({this.suffix = 'prepared', this.gate, this.rejectWith});
  final String suffix;
  final Completer<void>? gate;
  final String? rejectWith;
  int calls = 0;

  @override
  Future<PreparedCaptureImage> prepare(String localPath) async {
    calls++;
    await gate?.future;
    if (rejectWith != null) throw CaptureImageRejected(rejectWith!);
    final bytes = File(localPath).readAsBytesSync();
    final out = File('$localPath.$suffix.jpg')..writeAsBytesSync(bytes);
    return PreparedCaptureImage(
      file: out, mimeType: 'image/jpeg', byteSize: bytes.length, width: 32, height: 32,
    );
  }
}

class FakeVideoPreparer extends ChatVideoPreparer {
  FakeVideoPreparer({this.rejectWith});
  final String? rejectWith;

  @override
  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
    void Function(String posterPath)? onPosterReady,
    Duration? maxDuration,
    int? maxBytes,
  }) async {
    if (rejectWith != null) throw ChatVideoRejected(rejectWith!);
    final out = File('$localPath.out.mp4')
      ..writeAsBytesSync(File(localPath).readAsBytesSync());
    return PreparedChatVideo(
      file: out, mimeType: 'video/mp4', byteSize: 1024, durationMs: 4000,
      thumbnailFile: out, thumbnailMimeType: 'image/jpeg', thumbnailByteSize: 1,
      width: 720, height: 1280,
    );
  }
}

Future<String> writeJpeg(WidgetTester tester, Directory dir, String name) async {
  final path = '${dir.path}/$name';
  await tester.runAsync(() async {
    final image = img.Image(width: 32, height: 32);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 90));
  });
  return path;
}

typedef StoryCameraHarness = ({
  ProviderContainer container,
  StoryOutboxStore store,
  ScriptedStoryGateway gateway,
  Directory support,
});

/// A signed-in container whose uploads are held open (so queued rows stay
/// put), with the vault rooted under [root]/support and the couple map off.
StoryCameraHarness storyCameraContainer(
  Directory root, {
  bool cipherUnavailable = false,
  List<Override> extra = const [],
}) {
  final support = Directory('${root.path}/support')..createSync(recursive: true);
  final store = StoryOutboxStore.forTesting(
    stub.createStoryOutboxBackend(),
    cipherUnavailable: cipherUnavailable,
  );
  final gateway = ScriptedStoryGateway()..uploadGate = Completer<void>();
  final container = ProviderContainer(overrides: [
    currentUserProvider.overrideWithValue(outboxUser()),
    storyOutboxStoreProvider.overrideWithValue(store),
    storyGatewayProvider.overrideWithValue(gateway),
    storyMediaVaultProvider.overrideWithValue(
      StoryMediaVault(supportDirectory: () async => support),
    ),
    coupleMapEnabledProvider.overrideWith((ref) async => false),
    ...extra,
  ]);
  addTearDown(container.dispose);
  return (container: container, store: store, gateway: gateway, support: support);
}

/// Opens [screen] through go_router, the way the app does, and settles the
/// camera's async init with bounded pumps (an indeterminate spinner would
/// hang pumpAndSettle).
Future<void> pumpStoryCamera(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => context.push('/camera'),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/camera', builder: (context, state) => screen),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> tapShutterOnly(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(StreakRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Lets the real file I/O a Share does (vault create/rename, raw delete)
/// complete. Inside testWidgets' FakeAsync zone each sequential dart:io
/// await needs a real-time wait (the callback arrives) AND a pump (the fake
/// zone's microtasks run), so this alternates the two. If a test still
/// stalls at the vault move, raise [cycles]; do not make the vault sync.
Future<void> settleIo(WidgetTester tester, [int cycles = 10]) async {
  for (var i = 0; i < cycles; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 50));
}
```

Run `dart format` on this new file.

- [ ] **Step 2: Write the failing tests.** In `capture_camera_test.dart`'s `_FakeCameraPlatform`, add `final settings = <MediaSettings>[];` and `settings.add(mediaSettings);` inside `createCameraWithSettings` (allowed edit). Then add:

```dart
  testWidgets('the sensor preset is the embedder\'s; the default is streak\'s medium',
      (tester) async {
    final platform = _FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;

    await pumpToReady(tester, const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo));
    expect(platform.settings.last.resolutionPreset, ResolutionPreset.medium);
    expect(platform.settings.last.enableAudio, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpToReady(
      tester,
      const CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        resolutionPreset: ResolutionPreset.veryHigh,
      ),
    );
    expect(platform.settings.last.resolutionPreset, ResolutionPreset.veryHigh);
  });
```

Create `test/features/stories/story_camera_config_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/stories/presentation/screens/story_camera_screen.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/capture_fakes.dart';

void main() {
  late Directory dir;
  late CameraPlatform original;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('story_camera_config');
    original = CameraPlatform.instance;
  });
  tearDown(() {
    CameraPlatform.instance = original;
    dir.deleteSync(recursive: true);
  });

  testWidgets('stories capture at veryHigh (01 #5)', (tester) async {
    final platform = FakeCameraPlatform(
      videoPath: '${dir.path}/clip.mp4',
      photoPath: await writeJpeg(tester, dir, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;
    final h = storyCameraContainer(dir);
    await pumpStoryCamera(tester, h.container, const StoryCameraScreen(relationshipId: 'rel-1'));
    expect(platform.settings.last.resolutionPreset, ResolutionPreset.veryHigh);
  });
}
```

- [ ] **Step 3: Run and see them fail**

Run: `flutter test test/features/stories/capture_camera_test.dart test/features/stories/story_camera_config_test.dart`
Expected: compile failure (`resolutionPreset` is not a parameter).

- [ ] **Step 4: Implement.** In `CaptureCameraScreen`, add the constructor parameter `this.resolutionPreset = ResolutionPreset.medium,` and the field:

```dart
  /// The sensor preset. Defaults to the streak camera's shipped `medium`
  /// (§6.4: streaks byte-identical); stories pass `veryHigh` (1080p video,
  /// 1920-px photos) because a 640×480 frame is visibly soft full screen.
  final ResolutionPreset resolutionPreset;
```

In `_startPreview`, replace `ResolutionPreset.medium,` with `widget.resolutionPreset,` and keep `enableAudio: true,` literally (`streak_camera_test.dart` pins that string). In `story_camera_screen.dart`, add `resolutionPreset: ResolutionPreset.veryHigh,` to the embedded `CaptureCameraScreen(...)` and `import 'package:camera/camera.dart' show ResolutionPreset;`.

- [ ] **Step 5: Run and see them pass:** the same command as Step 3. Expected: PASS.

- [ ] **Step 6: Run tests (regression gate):**

```bash
flutter test test/features/stories/capture_camera_test.dart test/features/chat/streak_camera_contract_test.dart \
  test/features/chat/streak_camera_test.dart test/features/chat/streak_camera_photo_test.dart \
  test/features/chat/streak_lock_test.dart test/features/stories/story_camera_test.dart
```
Expected: all pass.

---

### Task 12: A denied microphone still takes photos; embedder copy; an error screen with a way out

Fixes 01 #6 / V16 and 06 #13 (the "streak" copy, and the dead-end error screen).

**Files:**
- Modify: `lib/features/chat/presentation/screens/capture_camera_screen.dart`: add `CaptureCameraCopy` (top of file); constructor params; `_initCamera` (`:179-196`); `_startPreview` (`:198-213`); `_flipCamera` (`:236-238`); `_beginRecording` (`:285-299`); `build`'s error branch (`:707-709`).
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart` (pass `microphoneOptional: true, copy: CaptureCameraCopy.story`).
- Test: `test/features/stories/capture_camera_test.dart` (new tests use `support/capture_fakes.dart`'s `FakeCameraPlatform`, which can deny); `story_camera_config_test.dart` (append).

**Interfaces:**
- Produces:

```dart
@immutable
class CaptureCameraCopy {
  const CaptureCameraCopy({
    this.cameraDenied = 'Attune needs camera access to record a streak.',
    this.noCamera = 'No camera available.',
    this.videoNeedsMicrophone = 'Video needs microphone access.',
    this.shutterLabel,
  });
  static const story = CaptureCameraCopy(
    cameraDenied: 'Attune needs camera access to share a story.',
    videoNeedsMicrophone:
        'Video needs microphone access. Tap for a photo, or allow the microphone in Settings.',
  );
  final String cameraDenied;
  final String noCamera;
  final String videoNeedsMicrophone;
  final String? shutterLabel; // used by Task 13
}
```

and `CaptureCameraScreen({..., bool microphoneOptional = false, CaptureCameraCopy copy = const CaptureCameraCopy(), Future<void> Function()? openSettings})`.

- [ ] **Step 1: Write the failing tests.** Add to `capture_camera_test.dart` (import `support/capture_fakes.dart` with `as fakes` to avoid clashing with the file's private fake):

```dart
  group('permissions (01 #6, 06 #13)', () {
    testWidgets('microphone denied + microphoneOptional: photos still work, a hold '
        'says video needs the mic', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      CameraPlatform.instance = platform;
      CapturedMedia? captured;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          microphoneOptional: true,
          copy: const CaptureCameraCopy(videoNeedsMicrophone: 'MIC NEEDED'),
          onCaptured: (m) => captured = m,
        ),
      );
      expect(platform.settings.map((s) => s.enableAudio), [true, false]);
      expect(find.byType(StreakRecordButton), findsOneWidget);

      // Tap: a photo.
      final tap = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump(const Duration(milliseconds: 100));
      await tap.up();
      await tester.pump();
      expect(captured?.type, CapturedMediaType.image);

      // Hold: no recording, and the reason.
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await hold.up();
      await tester.pump();
      expect(platform.startVideoCalls, 0);
      expect(find.text('MIC NEEDED'), findsOneWidget);
    });

    testWidgets('microphone denied without opting in: today\'s streak behaviour',
        (tester) async {
      CameraPlatform.instance = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      await pumpToReady(tester, const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo));
      expect(find.text('Attune needs camera access to record a streak.'), findsOneWidget);
    });

    testWidgets('the error screen offers Close and Open Settings', (tester) async {
      CameraPlatform.instance = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..cameraDenied = CameraException('CameraAccessDenied', 'denied');
      var settingsOpened = 0;
      var cancelled = 0;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          copy: CaptureCameraCopy.story,
          openSettings: () async => settingsOpened++,
          onCaptured: (_) {},
          onCancelled: () => cancelled++,
        ),
      );
      expect(find.text('Attune needs camera access to share a story.'), findsOneWidget);
      expect(find.textContaining('streak'), findsNothing);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(settingsOpened, 1);
      await tester.tap(find.byTooltip('Close camera'));
      await tester.pump();
      expect(cancelled, 1);
    });
  });
```

Append to `story_camera_config_test.dart`:

```dart
  testWidgets('the story camera never says "streak", and photos survive a denied mic',
      (tester) async {
    final platform = FakeCameraPlatform(
      videoPath: '${dir.path}/clip.mp4',
      photoPath: await writeJpeg(tester, dir, 'photo.jpg'),
    )..audioDenied = CameraException('AudioAccessDeniedWithoutPrompt', 'denied');
    CameraPlatform.instance = platform;
    final h = storyCameraContainer(dir);
    await pumpStoryCamera(tester, h.container, const StoryCameraScreen(relationshipId: 'rel-1'));
    expect(platform.settings.last.enableAudio, isFalse);
    expect(find.textContaining('streak'), findsNothing);
  });
```

- [ ] **Step 2: Run and see them fail**

Run: `flutter test test/features/stories/capture_camera_test.dart --plain-name permissions` and `flutter test test/features/stories/story_camera_config_test.dart`
Expected: compile failure (`CaptureCameraCopy`, `microphoneOptional`, `openSettings`).

- [ ] **Step 3: Implement.** In `capture_camera_screen.dart`, add `import 'package:permission_handler/permission_handler.dart' show openAppSettings;`, the `CaptureCameraCopy` class above, and the three constructor params with docs:

```dart
  /// When the microphone is refused, re-initialise without audio so photos
  /// still work (01 #6); a hold then explains that video needs the mic.
  /// Off by default: the streak camera's shipped behaviour is unchanged.
  final bool microphoneOptional;

  /// Destination copy (spec §6: each adapter owns its copy). The defaults
  /// are the streak camera's shipped strings.
  final CaptureCameraCopy copy;

  /// Test seam for the error screen's Open Settings; defaults to
  /// permission_handler's openAppSettings.
  final Future<void> Function()? openSettings;
```

State: `bool _audioUnavailable = false;` and `bool _settingsHelps = false;`.

```dart
  static const _audioDeniedCodes = {
    'AudioAccessDenied',
    'AudioAccessDeniedWithoutPrompt',
    'AudioAccessRestricted',
  };

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _permissionError = widget.copy.noCamera);
        return;
      }
      await _startPreview();
    } on CameraException catch (error) {
      if (widget.microphoneOptional && _audioDeniedCodes.contains(error.code)) {
        try {
          _audioUnavailable = true;
          await _startPreview();
          return;
        } on CameraException {
          // Fall through: the camera itself is refused too.
        }
      }
      if (mounted) {
        setState(() {
          _permissionError = widget.copy.cameraDenied;
          _settingsHelps = true;
        });
      }
    }
  }

  Future<void> _startPreview() async {
    if (_cameras.isEmpty) return;
    final controller = _audioUnavailable
        ? CameraController(
            _cameras[_cameraIndex],
            widget.resolutionPreset,
            // Microphone refused (microphoneOptional): photos only.
            enableAudio: false,
          )
        : CameraController(
            _cameras[_cameraIndex],
            widget.resolutionPreset,
            // A streak is someone talking to their partner: a muted format
            // removes most of what makes it worth sending.
            enableAudio: true,
          );
    try {
      await controller.initialize();
    } catch (_) {
      // Never leak a half-initialised controller (a failed init used to).
      try {
        await controller.dispose();
      } catch (_) {}
      rethrow;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }
```

At the top of `_beginRecording`, after the `controller == null` guard:

```dart
    if (_audioUnavailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.copy.videoNeedsMicrophone),
        action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
      ));
      return;
    }
```

Add `void _openSettings() => unawaited((widget.openSettings ?? () async { await openAppSettings(); })());`. Replace the error branch in `build`:

```dart
    if (_permissionError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: Spacing.md,
                left: Spacing.md,
                child: IconButton(
                  iconSize: IconSizes.lg,
                  tooltip: 'Close camera',
                  onPressed: _reportCancelled,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              Center(
                child: Padding(
                  padding: Spacing.allLg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined,
                          size: IconSizes.xl, color: Colors.white70),
                      const SizedBox(height: Spacing.md),
                      Text(
                        _permissionError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: Colors.white),
                      ),
                      if (_settingsHelps) ...[
                        const SizedBox(height: Spacing.lg),
                        FilledButton(
                          onPressed: _openSettings,
                          child: const Text('Open Settings'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
```

`_flipCamera` already calls `_startPreview()`, which now honours `_audioUnavailable`. In `story_camera_screen.dart`, pass `microphoneOptional: true, copy: CaptureCameraCopy.story,`.

- [ ] **Step 4: Run and see them pass:** the commands from Step 2. Expected: PASS.

- [ ] **Step 5: Run tests:** the regression gate command from Task 11 Step 6. Expected: all pass. `streak_camera_test`'s `enableAudio: true` source pin still matches.

---

### Task 13: Accessibility labels; recover when stopping a recording fails

Fixes 06 #12 (no labels on the shutter or flip) and 01 #15's stop-error half.

**Files:**
- Modify: `lib/features/chat/presentation/screens/capture_camera_screen.dart`: the flip `IconButton` (`:841-856`, add `tooltip`); wrap the record-button `Listener` (`:905-940`) in `Semantics`; `_splitSegment` (`:367-398`) and `_endRecording` (`:400-440`) catch stop failures.
- Test: `test/features/stories/capture_camera_test.dart`

**Interfaces:**
- Consumes: Task 12's `CaptureCameraCopy.shutterLabel`.
- Produces: shutter semantics label = `copy.shutterLabel ?? (allow == photoAndVideo ? 'Take photo, hold for video' : 'Hold to record')`; flip tooltip `'Switch camera'`; snackbar `'Could not save that recording.'`.

- [ ] **Step 1: Write the failing tests.** Add to `capture_camera_test.dart`:

```dart
  testWidgets('the shutter and flip are labelled, and a screen-reader tap takes '
      'a photo (06 #12)', (tester) async {
    final handle = tester.ensureSemantics();
    final platform = _FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;
    CapturedMedia? captured;
    await pumpToReady(
      tester,
      CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        onCaptured: (m) => captured = m,
      ),
    );
    expect(find.byTooltip('Switch camera'), findsOneWidget);
    final shutter = find.bySemanticsLabel('Take photo, hold for video');
    expect(shutter, findsOneWidget);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      tester.getSemantics(shutter).id,
      SemanticsAction.tap,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.takePictureCalls, 1);
    expect(captured?.type, CapturedMediaType.image);
    handle.dispose();
  });

  testWidgets('a failed stop resets the camera instead of freezing it (01 #15)',
      (tester) async {
    final platform = fakes.FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    )..stopError = CameraException('IOError', 'AVAssetWriter could not finish writing');
    CameraPlatform.instance = platform;
    var captured = 0;
    await pumpToReady(
      tester,
      CaptureCameraScreen(allow: CaptureKinds.videoOnly, onCaptured: (_) => captured++),
    );
    final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(captured, 0);
    expect(find.text('Could not save that recording.'), findsOneWidget);
    expect(find.byTooltip('Close camera'), findsOneWidget,
        reason: 'Close must come back, the only way out before this fix was the edge swipe');
    expect(find.byKey(const ValueKey('streak-elapsed')), findsNothing,
        reason: 'the counter must not stay frozen on screen');
  });
```

(Add `import 'package:flutter/rendering.dart' show SemanticsAction;` if not covered by `material.dart`.)

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/stories/capture_camera_test.dart --plain-name "labelled"` and `--plain-name "failed stop"`. Expected: FAIL (no tooltip or label; an uncaught `CameraException`).

- [ ] **Step 3: Implement.** On the flip `IconButton`, add `tooltip: 'Switch camera',`. Wrap the record-button `Listener(...)` in:

```dart
                      : Semantics(
                        button: true,
                        label: widget.copy.shutterLabel ??
                            (widget.allow == CaptureKinds.photoAndVideo
                                ? 'Take photo, hold for video'
                                : 'Hold to record'),
                        // The button is a raw Listener, which a screen
                        // reader's double-tap never reaches: give it a tap.
                        onTap: widget.allow == CaptureKinds.photoAndVideo
                            ? () => unawaited(_takePicture())
                            : null,
                        child: Listener(/* unchanged */),
                      ),
```

Add a recovery helper:

```dart
  /// stopVideoRecording threw (low storage, an interrupted writer): put the
  /// screen back to a live viewfinder instead of leaving it "recording"
  /// with Close hidden (01 #15).
  Future<void> _recoverFromFailedStop(Object error) async {
    ChatLog.diagnostic('capture stop failed', error);
    _ticker?.cancel();
    await _discardAll();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _lockDrag = 0;
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save that recording.')),
    );
  }
```

In `_endRecording`, replace `final file = await controller.stopVideoRecording();` with:

```dart
    final XFile file;
    try {
      file = await controller.stopVideoRecording();
    } on CameraException catch (error) {
      await _recoverFromFailedStop(error);
      return;
    }
```

In `_splitSegment`, wrap both the stop and the restart the same way: catch `CameraException` around `controller.stopVideoRecording()` and around `controller.startVideoRecording()`, calling `_recoverFromFailedStop`. For the restart case, report the segment already saved first: `if (_segments.isNotEmpty) _reportCaptured();`, then recover the UI.

- [ ] **Step 4: Run and see them pass:** the commands from Step 2. Expected: PASS.

- [ ] **Step 5: Run tests:** the Task 11 regression gate command. Expected: all pass.

---

### Task 14: Camera lifecycle: release on inactive, re-initialise on resume, keep an interrupted take

Fixes 01 #15's lifecycle half, 07b G7 regression risk 1, and Review Focus 4.

**Files:**
- Modify: `lib/features/chat/presentation/screens/capture_camera_screen.dart`: `CaptureCameraScreenState` mixes in `WidgetsBindingObserver`; `initState` / `dispose`; new `didChangeAppLifecycleState`, `_suspend`, `_resume`; `_startPreview` checks `_suspended`.
- Test: `test/features/stories/capture_camera_test.dart`

**Interfaces:** none new (internal behaviour).

- [ ] **Step 1: Write the failing tests.** Add to `capture_camera_test.dart`:

```dart
  group('lifecycle (01 #15, Review Focus 4)', () {
    void background(WidgetTester tester) =>
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    void foreground(WidgetTester tester) =>
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    testWidgets('inactive releases the camera; resumed brings it back', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(tester, const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo));
      expect(platform.createCalls, 1);

      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCalls, 1);

      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, 2);
      expect(find.byType(StreakRecordButton), findsOneWidget);
    });

    testWidgets('a call mid-hold keeps the take recorded so far', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      CapturedMedia? captured;
      await pumpToReady(
        tester,
        CaptureCameraScreen(allow: CaptureKinds.videoOnly, onCaptured: (m) => captured = m),
      );
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      background(tester); // the phone rings
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await hold.cancel();

      expect(platform.stopVideoCalls, 1);
      expect(captured?.type, CapturedMediaType.video);
      expect(captured!.durationMs, greaterThanOrEqualTo(500));
    });

    testWidgets('an inactive during the first permission prompt does not start '
        'two cameras', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo)),
      ));
      background(tester); // iOS shows the camera prompt: willResignActive
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls - platform.disposeCalls, 1,
          reason: 'exactly one live controller');
    });
  });
```

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/stories/capture_camera_test.dart --plain-name lifecycle`. Expected: FAIL (`disposeCalls` stays 0; nothing is captured on inactive).

- [ ] **Step 3: Implement.** Make the state `class CaptureCameraScreenState extends ConsumerState<CaptureCameraScreen> with WidgetsBindingObserver`. Call `WidgetsBinding.instance.addObserver(this);` in `initState` and `WidgetsBinding.instance.removeObserver(this);` first in `dispose`. Add:

```dart
  /// The camera is released while the app is not in front (the camera
  /// plugin's documented lifecycle handling), and comes back on resume.
  /// Applies to every embedder: without it an interrupted session leaves a
  /// black or frozen preview, and Wave 3 keeps this screen mounted behind
  /// the privacy cover, where that would show (07b G7, risk 1).
  bool _suspended = false;
  bool _initInFlight = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_suspend());
      case AppLifecycleState.resumed:
        unawaited(_resume());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _suspend() async {
    if (_suspended) return;
    _suspended = true;
    _holdThresholdTimer?.cancel();
    _holdThresholdTimer = null;
    if (_isRecording) {
      // A call or Control Centre mid-hold: keep what was recorded. A locked
      // take ends the same way; Close and review follow on return.
      _isLocked = false;
      await _endRecording();
    }
    final controller = _controller;
    if (controller == null) return; // still initialising: see _startPreview
    if (mounted) setState(() => _controller = null);
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<void> _resume() async {
    if (!_suspended) return;
    _suspended = false;
    if (!mounted || _permissionError != null || _cameras.isEmpty) return;
    if (_controller != null || _initInFlight) return;
    try {
      await _startPreview();
    } on CameraException {
      if (mounted) {
        setState(() {
          _permissionError = widget.copy.cameraDenied;
          _settingsHelps = true;
        });
      }
    }
  }
```

In `_startPreview`, set `_initInFlight = true;` before `initialize()` and clear it in a `finally`. After a successful init, replace `if (!mounted) {` with `if (!mounted || _suspended) {` (dispose and return). An init that finished while backgrounded is released, and `_resume` builds a fresh one. `_endRecording` already reports the take through `_reportCaptured` when it is at least the minimum length, and `stopVideoRecording` failures go through Task 13's recovery.

- [ ] **Step 4: Run and see them pass:** `flutter test test/features/stories/capture_camera_test.dart`. Expected: all pass.

- [ ] **Step 5: Run tests:** the Task 11 regression gate command, plus `test/features/chat/streak_preview_test.dart`. Expected: all pass. If a streak suite now sees an unexpected `dispose` because its harness sends lifecycle events, stop and report it. Do not edit streak tests.

---

### Task 15: The 60 s edge and fractional trims (opt-in on `ChatVideoPreparer`)

Fixes 01 #4 / V14 (a full 60 s take is likely rejected) and 01 #16 (a 0.8 s clip is trimmed to a zero range on iOS), for stories only.

**Files:**
- Modify: `lib/features/chat/domain/services/chat_video_preparer.dart`: constructor at `:57`; new static helpers after `debugResolveMaxBytes` (`:157`); `prepare` at `:210-237` and `:294-302`, `:339-349`.
- Test: `test/features/chat/chat_video_preparer_test.dart` (append a group).

**Interfaces:**
- Produces:
  - `const ChatVideoPreparer({Duration? boundaryTolerance})`. A constructor field, not a `prepare` parameter, because three test fakes (`streak_camera_contract_test`, `story_camera_test`, `capture_camera_test`) override `prepare` and must not change.
  - `@visibleForTesting static ({Duration start, Duration end, int? startSeconds, int? durationSeconds}) debugExportWindow({required Duration source, Duration? trimStart, Duration? trimEnd, required Duration maxDuration, Duration? boundaryTolerance})`
  - `@visibleForTesting static int debugReportedDurationMs({required Duration window, double? exportedMs, required Duration maxDuration, required bool precise})`

- [ ] **Step 1: Write the failing tests.** Append to `chat_video_preparer_test.dart`'s `main()`:

```dart
  group('precise export window (stories Wave 2, opt-in)', () {
    const max = Duration(seconds: 60);
    const tol = Duration(seconds: 2);

    test('without a tolerance the window is exactly today\'s', () {
      final w = ChatVideoPreparer.debugExportWindow(
        source: const Duration(milliseconds: 59700), maxDuration: max,
      );
      expect(w.end, const Duration(milliseconds: 59700));
      expect(w.startSeconds, 0);
      expect(w.durationSeconds, 59, reason: 'unchanged legacy truncation');
    });

    test('a take that overshoots the minute by the stop latency is clamped to 60 s', () {
      final w = ChatVideoPreparer.debugExportWindow(
        source: const Duration(milliseconds: 60240),
        maxDuration: max,
        boundaryTolerance: tol,
      );
      expect(w.end - w.start, max);
      expect(w.startSeconds, 0);
      expect(w.durationSeconds, 60);
    });

    test('beyond the tolerance it is not clamped (still too long)', () {
      final w = ChatVideoPreparer.debugExportWindow(
        source: const Duration(milliseconds: 63000),
        maxDuration: max,
        boundaryTolerance: tol,
      );
      expect(w.end - w.start, const Duration(milliseconds: 63000));
    });

    test('an untrimmed short or fractional clip is exported whole', () {
      for (final ms in [800, 59700]) {
        final w = ChatVideoPreparer.debugExportWindow(
          source: Duration(milliseconds: ms),
          maxDuration: max,
          boundaryTolerance: tol,
        );
        expect(w.startSeconds, isNull, reason: '$ms ms');
        expect(w.durationSeconds, isNull,
            reason: 'never duration: 0 (01 #16) and never a lost fraction');
        expect(w.end, Duration(milliseconds: ms));
      }
    });

    test('a precise duration is min(exported, 60000); legacy keeps the window', () {
      expect(
        ChatVideoPreparer.debugReportedDurationMs(
          window: const Duration(seconds: 60), exportedMs: 60031.0,
          maxDuration: max, precise: true,
        ),
        60000,
      );
      expect(
        ChatVideoPreparer.debugReportedDurationMs(
          window: const Duration(milliseconds: 800), exportedMs: 812.4,
          maxDuration: max, precise: true,
        ),
        812,
      );
      expect(
        ChatVideoPreparer.debugReportedDurationMs(
          window: const Duration(milliseconds: 59700), exportedMs: 59000,
          maxDuration: max, precise: false,
        ),
        59700,
      );
    });

    test('prepare() uses the window helper (the plugin args come from it)', () {
      final src = File('lib/features/chat/domain/services/chat_video_preparer.dart')
          .readAsStringSync();
      expect(src, contains('debugExportWindow('));
      expect(src, contains('startTime: window.startSeconds'));
      expect(src, contains('duration: window.durationSeconds'));
    });
  });
```

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/chat/chat_video_preparer_test.dart --plain-name "precise export window"`. Expected: compile failure.

- [ ] **Step 3: Implement.** Replace `const ChatVideoPreparer();` with:

```dart
  const ChatVideoPreparer({this.boundaryTolerance});

  /// Opt-in (stories only; chat and streaks pass nothing and are
  /// byte-identical). A camera take that overshoots [maxDuration] by up to
  /// this much (stop latency) is clamped to exactly the max, an untrimmed
  /// source is exported whole instead of through a whole-second window,
  /// and `durationMs` is the exported length capped at the max (01 #4, #16).
  final Duration? boundaryTolerance;
```

Add the helpers:

```dart
  @visibleForTesting
  static ({Duration start, Duration end, int? startSeconds, int? durationSeconds})
      debugExportWindow({
    required Duration source,
    Duration? trimStart,
    Duration? trimEnd,
    required Duration maxDuration,
    Duration? boundaryTolerance,
  }) {
    final start = trimStart ?? Duration.zero;
    var end = trimEnd ?? source;
    if (boundaryTolerance == null) {
      return (
        start: start,
        end: end,
        startSeconds: start.inSeconds,
        durationSeconds: (end - start).inSeconds,
      );
    }
    final untrimmed = trimStart == null && trimEnd == null;
    if (untrimmed && source <= maxDuration) {
      return (start: Duration.zero, end: source, startSeconds: null, durationSeconds: null);
    }
    if (untrimmed && source <= maxDuration + boundaryTolerance) end = maxDuration;
    final window = end - start;
    return (
      start: start,
      end: end,
      startSeconds: start.inSeconds,
      // Rounded UP so a fractional window is never cut short or to zero.
      durationSeconds: (window.inMilliseconds / 1000).ceil(),
    );
  }

  @visibleForTesting
  static int debugReportedDurationMs({
    required Duration window,
    double? exportedMs,
    required Duration maxDuration,
    required bool precise,
  }) {
    if (!precise) return window.inMilliseconds;
    final actual = exportedMs?.round() ?? window.inMilliseconds;
    return actual < maxDuration.inMilliseconds ? actual : maxDuration.inMilliseconds;
  }
```

In `prepare`, replace `:212-214` with:

```dart
    final window = debugExportWindow(
      source: sourceDuration,
      trimStart: trimStart,
      trimEnd: trimEnd,
      maxDuration: effectiveMaxDuration,
      boundaryTolerance: boundaryTolerance,
    );
    final effectiveStart = window.start;
    final effectiveDuration = window.end - window.start;
```

In `compressVideo(...)`, replace the two arguments with `startTime: window.startSeconds,` and `duration: window.durationSeconds,`. In the returned `PreparedChatVideo`, replace `durationMs: effectiveDuration.inMilliseconds,` with:

```dart
      durationMs: debugReportedDurationMs(
        window: effectiveDuration,
        exportedMs: compressed.duration,
        maxDuration: effectiveMaxDuration,
        precise: boundaryTolerance != null,
      ),
```

With `boundaryTolerance == null`, `window.startSeconds` / `durationSeconds` equal the old `effectiveStart.inSeconds` / `effectiveDuration.inSeconds`, and the reported duration equals the old one. Chat behaviour is unchanged. (`MediaInfo.duration` is a `double?` in milliseconds in video_compress 3.1.4; if it is not, convert accordingly.)

- [ ] **Step 4: Run and see them pass:** `flutter test test/features/chat/chat_video_preparer_test.dart`. Expected: all pass.

- [ ] **Step 5: Run tests (chat regression gate):**

```bash
flutter test test/features/chat/chat_video_preparer_test.dart test/features/chat/chat_state_send_video_message_test.dart \
  test/features/chat/chat_state_send_ephemeral_video_message_test.dart test/features/chat/video_trim_screen_test.dart \
  test/features/chat/streak_camera_contract_test.dart test/features/stories
```
Expected: all pass. Device check (recorded in Task 19's checklist): hold the story shutter for the full minute, then confirm it reaches review, shares, and finalizes with `duration_ms = 60000`; record a 0.8 s clip and confirm it shares.

---
### Task 16: `StoryPostPipeline`: posting a take no longer depends on the camera staying mounted

Fixes 01 #14 (closing between shutter and enqueue silently drops the story; `ref.read` after dispose throws), 07b G7's "make `_prepareAndEnqueue` enqueue without `mounted`", the place lookup that holds the shutter for up to 30 s, and 01 #19's raw-file leak. The UI that calls it is Task 17.

**Files:**
- Create: `lib/features/stories/presentation/state/story_post_pipeline.dart`
- Create: `lib/features/stories/domain/story_post_copy.dart`
- Create: `test/features/stories/story_post_pipeline_test.dart`
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart`: move `StoryThumbnailFailed` (`:77-86`) and the thumbnail constants (`:73-75`) into the pipeline; keep `export 'package:attune/features/stories/presentation/state/story_post_pipeline.dart' show StoryThumbnailFailed;` at the top so any importer still compiles. The rest of the screen changes in Task 17.

**Interfaces:**
- Consumes: Task 7's `storyMediaVaultProvider`; `storyOutboxProvider.notifier.enqueueLocally`; Task 15's `ChatVideoPreparer(boundaryTolerance:)`; `kStreakSegmentDuration`.
- Produces:

```dart
@immutable
class StoryPostRequest {
  const StoryPostRequest({
    required this.raw,
    required this.relationshipId,
    required this.utcOffsetMinutes,
    this.place,
    this.videoPreparer,
    this.imagePreparer,
    this.thumbnailPreparer,
    this.thumbnailGrabber,
  });
  final CapturedMedia raw;
  final String relationshipId;
  final int utcOffsetMinutes;
  final Future<StoryPlaceDraft?> Function()? place;
  final ChatVideoPreparer Function()? videoPreparer;
  final CaptureImagePreparer Function()? imagePreparer;
  final CaptureImagePreparer Function()? thumbnailPreparer;
  final Future<Uint8List?> Function(String videoPath)? thumbnailGrabber;
}

sealed class StoryPostOutcome { const StoryPostOutcome(); }
final class StoryPostQueued extends StoryPostOutcome {
  const StoryPostQueued({required this.clientStoryId, required this.placeDropped});
  final String clientStoryId;
  final bool placeDropped;
}
final class StoryPostNotSaved extends StoryPostOutcome { const StoryPostNotSaved(); }
final class StoryPostRejected extends StoryPostOutcome {
  const StoryPostRejected(this.code);
  final String code;
}

@immutable
class StoryPostNotice {
  const StoryPostNotice({required this.code, required this.mediaType});
  final String code;
  final CapturedMediaType mediaType;
}

class StoryPostPipeline {
  StoryPostPipeline(this._ref, {this.placeBound = const Duration(seconds: 3)});
  static const Duration videoBoundaryTolerance = Duration(seconds: 2);
  final Duration placeBound;
  Future<StoryPostOutcome> post(StoryPostRequest request, {bool Function()? callerListening});
}

final storyPostPipelineProvider = Provider<StoryPostPipeline>((ref) => StoryPostPipeline(ref));
final storyPostNoticeProvider = StateProvider<StoryPostNotice?>((ref) => null);

// story_post_copy.dart
String storyPrepareFailureMessage(String code, CapturedMediaType type);
```

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_post_pipeline_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/capture_fakes.dart';
import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('story_pipeline'));
  tearDown(() => dir.deleteSync(recursive: true));

  StoryPostRequest photo(File raw, {
    FakeImagePreparer? main,
    Future<StoryPlaceDraft?> Function()? place,
  }) => StoryPostRequest(
    raw: CapturedMedia(path: raw.path, type: CapturedMediaType.image, width: 720, height: 1280),
    relationshipId: 'rel-1',
    utcOffsetMinutes: 60,
    place: place,
    imagePreparer: () => main ?? FakeImagePreparer(),
    thumbnailPreparer: () => FakeImagePreparer(suffix: 'thumb'),
  );

  File rawPhoto() => File('${dir.path}/raw.jpg')..writeAsBytesSync([1, 2, 3, 4]);

  test('a photo is prepared, moved into the vault and queued; the raw file goes',
      () async {
    final h = storyCameraContainer(dir);
    final raw = rawPhoto();
    final outcome = await h.container.read(storyPostPipelineProvider).post(photo(raw));

    expect(outcome, isA<StoryPostQueued>());
    final row = (await h.store.readAll(outboxUserId)).single;
    expect(row.localMediaPath, startsWith('story_outbox/$outboxUserId/${row.clientStoryId}/'));
    expect(File('${h.support.path}/${row.localMediaPath}').existsSync(), isTrue);
    expect(File('${h.support.path}/${row.localThumbnailPath}').existsSync(), isTrue);
    expect(row.width, 32, reason: 'the PREPARED size, not the raw preview size');
    expect(row.utcOffsetMinutes, 60);
    expect(raw.existsSync(), isFalse, reason: 'no raw capture left in tmp (01 #19)');
  });

  test('a slow place lookup is bounded: it posts without a place and says so',
      () async {
    final h = storyCameraContainer(dir, extra: [
      storyPostPipelineProvider.overrideWith(
        (ref) => StoryPostPipeline(ref, placeBound: const Duration(milliseconds: 50)),
      ),
    ]);
    final outcome = await h.container.read(storyPostPipelineProvider).post(
      photo(rawPhoto(), place: () => Completer<StoryPlaceDraft?>().future),
    );
    expect(outcome, isA<StoryPostQueued>()
        .having((o) => o.placeDropped, 'placeDropped', isTrue));
    expect((await h.store.readAll(outboxUserId)).single.place, isNull);
  });

  test('a pin that resolves in time is kept', () async {
    final h = storyCameraContainer(dir);
    const here = StoryPlaceDraft(lat: 5.5, lng: -0.2, label: 'Near Osu, Accra');
    final outcome = await h.container.read(storyPostPipelineProvider).post(
      photo(rawPhoto(), place: () async => here),
    );
    expect(outcome, isA<StoryPostQueued>()
        .having((o) => o.placeDropped, 'placeDropped', isFalse));
    expect((await h.store.readAll(outboxUserId)).single.place?.label, 'Near Osu, Accra');
  });

  test('a rejection after the camera is gone is surfaced, not swallowed (01 #14)',
      () async {
    final h = storyCameraContainer(dir);
    final outcome = await h.container.read(storyPostPipelineProvider).post(
      photo(rawPhoto(), main: FakeImagePreparer(rejectWith: 'media_decode_failed')),
      callerListening: () => false,
    );
    expect(outcome, isA<StoryPostRejected>()
        .having((o) => o.code, 'code', 'media_decode_failed'));
    final notice = h.container.read(storyPostNoticeProvider);
    expect(notice?.code, 'media_decode_failed');
    expect(await h.store.readAll(outboxUserId), isEmpty);
  });

  test('a rejection the camera is still showing raises no notice', () async {
    final h = storyCameraContainer(dir);
    await h.container.read(storyPostPipelineProvider).post(
      photo(rawPhoto(), main: FakeImagePreparer(rejectWith: 'media_compress_failed')),
      callerListening: () => true,
    );
    expect(h.container.read(storyPostNoticeProvider), isNull);
  });

  test('keystore unavailable: not saved, the raw take kept for another Share, '
      'nothing left in the vault', () async {
    final h = storyCameraContainer(dir, cipherUnavailable: true);
    final raw = rawPhoto();
    final outcome = await h.container.read(storyPostPipelineProvider).post(photo(raw));
    expect(outcome, isA<StoryPostNotSaved>());
    expect(raw.existsSync(), isTrue);
    final mine = Directory('${h.support.path}/story_outbox/$outboxUserId');
    expect(mine.existsSync() ? mine.listSync() : const [], isEmpty);
  });

  test('stories prepare video with the 60 s tolerance (Task 15)', () {
    final src = File('lib/features/stories/presentation/state/story_post_pipeline.dart')
        .readAsStringSync();
    expect(src, contains('ChatVideoPreparer(boundaryTolerance: videoBoundaryTolerance)'));
  });

  test('prepare failures carry a reason', () {
    expect(storyPrepareFailureMessage('media_too_long', CapturedMediaType.video),
        'That video is longer than a minute.');
    expect(storyPrepareFailureMessage('anything-else', CapturedMediaType.image),
        'That could not be posted.');
    expect(storyPrepareFailureMessage('media_decode_failed', CapturedMediaType.image),
        contains('photo'));
  });
}
```

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/stories/story_post_pipeline_test.dart`. Expected: compile failure.

- [ ] **Step 3: Implement the copy.** Create `lib/features/stories/domain/story_post_copy.dart`:

```dart
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
    'media_compress_failed' => "That $noun couldn't be prepared. Try again.",
    'media_missing' || 'media_empty' => "That $noun wasn't saved. Try again.",
    'media_decode_failed' ||
    'media_type_unsupported' => "That $noun couldn't be read. Try again.",
    'thumbnail_failed' ||
    'thumbnail_frame_failed' => "That $noun couldn't be prepared. Try again.",
    'signed_out' => 'Sign in again to share a story.',
    _ => 'That could not be posted.',
  };
}
```

- [ ] **Step 4: Implement the pipeline.** Create `lib/features/stories/presentation/state/story_post_pipeline.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart'
    show kStreakSegmentDuration;
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumb;

// StoryPostRequest, StoryPostOutcome (+3 subclasses) and StoryPostNotice
// exactly as in this task's Interfaces block, with doc comments.

/// The story thumbnail policy (spec §4.3): 400px long edge, JPEG q75, at
/// most 800KB. Moved from story_camera_screen.dart unchanged.
const int _thumbnailMaxDimension = 400;
const int _thumbnailQuality = 75;
const int _thumbnailMaxBytes = 800 * 1024;

class StoryThumbnailFailed implements Exception {
  const StoryThumbnailFailed(this.code);
  final String code;
  @override
  String toString() => 'StoryThumbnailFailed($code)';
}

/// Everything between Share and the outbox: prepare to the main-media
/// policy, build the required thumbnail, read the pin (bounded), move both
/// files into the vault, enqueue. Runs on a provider Ref, not a widget's, so
/// a camera that unmounts mid-prepare (back, the privacy cover, a route
/// change) never drops the take (01 #14, 07b G7). [callerListening] says
/// whether the camera is still there to show a failure; if not, the
/// failure goes to [storyPostNoticeProvider] for the rings row.
class StoryPostPipeline {
  StoryPostPipeline(this._ref, {this.placeBound = const Duration(seconds: 3)});

  final Ref _ref;
  final Duration placeBound;

  /// A camera take overshoots the minute by its stop latency (01 #4).
  static const Duration videoBoundaryTolerance = Duration(seconds: 2);
  static const int _maxVideoBytes = 25 * 1024 * 1024;

  Future<StoryPostOutcome> post(
    StoryPostRequest request, {
    bool Function()? callerListening,
  }) async {
    // Read up front: nothing below may depend on the caller still existing.
    final userId = _ref.read(currentUserProvider)?.id;
    final outbox = _ref.read(storyOutboxProvider.notifier);
    final vault = _ref.read(storyMediaVaultProvider);
    final raw = request.raw;
    if (userId == null || userId.isEmpty) {
      return _rejected('signed_out', raw, callerListening);
    }
    try {
      final prepared = await _prepare(request);
      final thumbnailPath = await _thumbnail(request, prepared);
      final (place, placeDropped) = await _place(request);
      final clientStoryId = newClientStoryId();
      final stored = await vault.adopt(
        userId: userId,
        clientStoryId: clientStoryId,
        mediaPath: prepared.path,
        thumbnailPath: thumbnailPath,
      );
      final record = StoryOutboxRecord(
        clientStoryId: clientStoryId,
        relationshipId: request.relationshipId,
        localMediaPath: stored.media,
        localThumbnailPath: stored.thumbnail,
        mediaType: prepared.type,
        mimeType: prepared.type == CapturedMediaType.image ? 'image/jpeg' : 'video/mp4',
        width: prepared.width,
        height: prepared.height,
        durationMs: prepared.durationMs,
        utcOffsetMinutes: request.utcOffsetMinutes,
        createdAt: DateTime.now(),
        place: place,
      );
      final queued = await outbox.enqueueLocally(record);
      if (!queued) {
        // Keystore refused (fail closed): nothing queued. Keep the raw take
        // so the review can offer Share again; drop the prepared copies.
        await vault.deleteFor(record);
        return const StoryPostNotSaved();
      }
      await _deleteQuietly(raw.path);
      return StoryPostQueued(clientStoryId: clientStoryId, placeDropped: placeDropped);
    } catch (error, stack) {
      ChatLog.diagnostic('story post prepare failed', '$error\n$stack');
      final code = switch (error) {
        ChatVideoRejected(:final code) => code,
        CaptureImageRejected(:final code) => code,
        StoryThumbnailFailed(:final code) => code,
        _ => 'capture_failed',
      };
      return _rejected(code, raw, callerListening);
    }
  }

  Future<StoryPostOutcome> _rejected(
    String code,
    CapturedMedia raw,
    bool Function()? callerListening,
  ) async {
    await _deleteQuietly(raw.path);
    if (callerListening != null && !callerListening()) {
      _ref.read(storyPostNoticeProvider.notifier).state =
          StoryPostNotice(code: code, mediaType: raw.type);
    }
    return StoryPostRejected(code);
  }

  Future<CapturedMedia> _prepare(StoryPostRequest r) async {
    final raw = r.raw;
    if (raw.type == CapturedMediaType.image) {
      final image = await (r.imagePreparer ?? CaptureImagePreparer.new)().prepare(raw.path);
      return CapturedMedia(
        path: image.file.path,
        type: CapturedMediaType.image,
        width: image.width,
        height: image.height,
      );
    }
    final video = await (r.videoPreparer ??
            () => const ChatVideoPreparer(boundaryTolerance: videoBoundaryTolerance))()
        .prepare(
          localPath: raw.path,
          maxDuration: kStreakSegmentDuration,
          maxBytes: _maxVideoBytes,
        );
    return CapturedMedia(
      path: video.file.path,
      type: CapturedMediaType.video,
      width: video.width,
      height: video.height,
      durationMs: video.durationMs,
    );
  }

  /// Moved verbatim from story_camera_screen.dart `_buildThumbnail`.
  Future<String> _thumbnail(StoryPostRequest r, CapturedMedia prepared) async {
    final preparer = (r.thumbnailPreparer ??
        () => const CaptureImagePreparer(
              maxDimension: _thumbnailMaxDimension,
              maxBytes: _thumbnailMaxBytes,
              qualityLadder: [_thumbnailQuality],
              fallbackQuality: _thumbnailQuality,
            ))();
    if (prepared.type == CapturedMediaType.image) {
      return (await preparer.prepare(prepared.path)).file.path;
    }
    final grab = r.thumbnailGrabber ??
        (path) => video_thumb.VideoThumbnail.thumbnailData(
              video: path, timeMs: 0, quality: 90,
            );
    final bytes = await grab(prepared.path);
    if (bytes == null) throw const StoryThumbnailFailed('thumbnail_frame_failed');
    final frame = await _tempPath('story_thumb_frame', 'jpg');
    await File(frame).writeAsBytes(bytes, flush: true);
    try {
      return (await preparer.prepare(frame)).file.path;
    } finally {
      await _deleteQuietly(frame);
    }
  }

  /// The pin, bounded (01 #14: a slow fix used to hold the shutter up to
  /// 20 s + 10 s). Past the bound the story posts without a place.
  Future<(StoryPlaceDraft?, bool)> _place(StoryPostRequest r) async {
    final lookup = r.place;
    if (lookup == null) return (null, false);
    try {
      return (await lookup().timeout(placeBound), false);
    } on TimeoutException {
      return (null, true);
    } catch (_) {
      return (null, false);
    }
  }

  static Future<String> _tempPath(String prefix, String ext) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    return p.join(dir.path, '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$ext');
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

final storyPostPipelineProvider = Provider<StoryPostPipeline>(
  (ref) => StoryPostPipeline(ref),
);

final storyPostNoticeProvider = StateProvider<StoryPostNotice?>((ref) => null);
```

Run `dart format` on both new files. In `story_camera_screen.dart`, delete the moved constants and class, and add the `export ... show StoryThumbnailFailed;` line. `_buildThumbnail` and `_thumbnailPreparer` stay until Task 17 replaces `_prepareAndEnqueue` (they may then be deleted).

- [ ] **Step 5: Run and see them pass:** `flutter test test/features/stories/story_post_pipeline_test.dart`. Expected: PASS.

- [ ] **Step 6: Run tests:** `flutter test test/features/stories`. Expected: all pass (the screen still uses its own path until Task 17).

---

### Task 17: Review before posting: Share / Retake (owner ruling 1)

Fixes 01 #7 / V17 / 06 #5a / 07b V5 / G5, plus 01 #14's window (Close is visible while a take is being prepared) and Review Focus 5.

**Files:**
- Create: `lib/features/stories/presentation/widgets/story_review_layer.dart`
- Create: `test/features/stories/story_review_test.dart`
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart`: library doc (`:1-43`); state (`:147-162`); replace `_onCaptured` / `_prepareAndEnqueue` / `_stayOnCameraAfterFailure` (`:174-285`) and remove the now-unused `_buildThumbnail` / `_thumbnailPreparer` / `_defaultThumbnailGrabber` / `_tempTargetPath` / `_mimeTypeFor`; `build` (`:373-416`).
- Modify (allowed edits): `test/features/stories/story_camera_test.dart`:
  - `buildContainer` (`:348-365`) adds a vault override;
  - `tapShutter` (`:414-428`) also taps Share;
  - the thumbnail-exists assertion (`:760-761`) resolves the now-relative path.

**Interfaces:**
- Consumes: Task 16's `storyPostPipelineProvider`, `StoryPostRequest`, the outcomes and `storyPrepareFailureMessage`; `CaptureCameraScreen.isReviewing` / `reset()` (unchanged contract).
- Produces:

```dart
class StoryReviewLayer extends StatelessWidget {
  const StoryReviewLayer({
    super.key,
    required this.media,
    required this.videoController,
    required this.posting,
    required this.onShare,
    required this.onRetake,
    required this.onClose,
  });
}
```

Keys: `story-review-share`, `story-review-retake`, `story-review-close`, `story-review-image`.

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_review_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/stories/presentation/screens/story_camera_screen.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/capture_fakes.dart';
import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  late CameraPlatform original;
  late String photoPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('story_review');
    original = CameraPlatform.instance;
  });
  tearDown(() {
    CameraPlatform.instance = original;
    dir.deleteSync(recursive: true);
  });

  final share = find.byKey(const ValueKey('story-review-share'));
  final retake = find.byKey(const ValueKey('story-review-retake'));
  final close = find.byKey(const ValueKey('story-review-close'));

  Future<({StoryCameraHarness h, FakeImagePreparer main})> open(
    WidgetTester tester, {
    Completer<void>? gate,
    String? rejectWith,
  }) async {
    photoPath = await writeJpeg(tester, dir, 'photo.jpg');
    CameraPlatform.instance =
        FakeCameraPlatform(videoPath: '${dir.path}/clip.mp4', photoPath: photoPath);
    final h = storyCameraContainer(dir);
    final main = FakeImagePreparer(gate: gate, rejectWith: rejectWith);
    await pumpStoryCamera(
      tester,
      h.container,
      StoryCameraScreen(
        relationshipId: 'rel-1',
        imagePreparerFactory: () => main,
        thumbnailPreparerFactory: () => FakeImagePreparer(suffix: 'thumb'),
      ),
    );
    return (h: h, main: main);
  }

  testWidgets('the shutter opens a review; nothing is queued until Share',
      (tester) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    expect(share, findsOneWidget);
    expect(retake, findsOneWidget);
    expect(find.byKey(const ValueKey('story-review-image')), findsOneWidget);
    expect(find.byType(StreakRecordButton), findsNothing,
        reason: 'the shared camera hides its controls while reviewing');
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
    expect(t.main.calls, 0, reason: 'nothing is prepared before Share');

    await tester.tap(share);
    await tester.pump();
    await settleIo(tester);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(StoryCameraScreen), findsNothing, reason: 'Share leaves');
  });

  testWidgets('Retake deletes the take and returns to a live camera', (tester) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    await tester.tap(retake);
    await tester.pump();
    await settleIo(tester);
    expect(share, findsNothing);
    expect(find.byType(StreakRecordButton), findsOneWidget);
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
    expect(await tester.runAsync(() => File(photoPath).exists()), isFalse);
  });

  testWidgets('closing the review asks first: Keep stays, Discard leaves',
      (tester) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    await tester.tap(close);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(share, findsOneWidget);

    await tester.tap(close);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Discard'));
    await tester.pump(const Duration(milliseconds: 300));
    await settleIo(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StoryCameraScreen), findsNothing);
    expect(await t.h.store.readAll(outboxUserId), isEmpty);
  });

  testWidgets('Share tapped twice queues once (Review Focus 5)', (tester) async {
    final t = await open(tester);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.tap(share, warnIfMissed: false);
    await tester.pump();
    await settleIo(tester);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
    expect(t.main.calls, 1);
  });

  testWidgets('while sharing, Close is hidden and back does not leave', (tester) async {
    final gate = Completer<void>();
    await open(tester, gate: gate);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    expect(close, findsNothing);
    expect(find.text('Sharing…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StoryCameraScreen), findsOneWidget);
    gate.complete();
    await settleIo(tester);
  });

  testWidgets('the camera unmounting mid-prepare still queues the story '
      '(01 #14, 07b G7)', (tester) async {
    final gate = Completer<void>();
    final t = await open(tester, gate: gate);
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    // The privacy cover (Wave 3 not yet fixed) or any teardown: gone.
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await settleIo(tester, 20);
    expect(await t.h.store.readAll(outboxUserId), hasLength(1));
  });

  testWidgets('a rejected take says why and returns to the live camera',
      (tester) async {
    await open(tester, rejectWith: 'media_decode_failed');
    await tapShutterOnly(tester);
    await tester.tap(share);
    await tester.pump();
    await settleIo(tester);
    expect(find.text("That photo couldn't be read. Try again."), findsOneWidget);
    expect(share, findsNothing);
    expect(find.byType(StreakRecordButton), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/stories/story_review_test.dart`. Expected: FAIL (no review keys; the shutter enqueues at once).

- [ ] **Step 3: Implement the review layer.** Create `lib/features/stories/presentation/widgets/story_review_layer.dart`:

```dart
import 'dart:io';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The take, full bleed, with Retake and Share (owner ruling 1, overriding
/// spec §6.1's "the outbox is the review"). A fixed black media surface in
/// both themes: literal white foreground, as the camera itself uses.
class StoryReviewLayer extends StatelessWidget {
  const StoryReviewLayer({
    super.key,
    required this.media,
    required this.videoController,
    required this.posting,
    required this.onShare,
    required this.onRetake,
    required this.onClose,
  });

  final CapturedMedia media;
  final VideoPlayerController? videoController;
  final bool posting;
  final VoidCallback onShare;
  final VoidCallback onRetake;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final video = videoController;
    final Widget preview = media.type == CapturedMediaType.image
        ? Image.file(
            File(media.path),
            key: const ValueKey('story-review-image'),
            fit: BoxFit.cover,
          )
        : video != null && video.value.isInitialized
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              )
            : const Center(
                // A preview that will not open must not block Share.
                child: Icon(Icons.videocam_rounded,
                    size: IconSizes.xl, color: Colors.white70),
              );

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(child: preview),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 200,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          if (!posting)
            Positioned(
              top: Spacing.xxl,
              left: Spacing.md,
              child: IconButton(
                key: const ValueKey('story-review-close'),
                iconSize: IconSizes.lg,
                tooltip: 'Discard',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          Positioned(
            left: Spacing.lg,
            right: Spacing.lg,
            bottom: Spacing.xxl,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('story-review-retake'),
                      onPressed: posting ? null : onRetake,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: IconSizes.md),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('story-review-share'),
                      onPressed: posting ? null : onShare,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: posting
                          ? const SizedBox.square(
                              dimension: IconSizes.sm,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: IconSizes.md),
                      label: Text(posting ? 'Sharing…' : 'Share'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Run `dart format` on this new file. The bottom scrim is a fixed media overlay (not a themed surface), so it uses alpha-black literals, as the camera does.

- [ ] **Step 4: Rewire the screen.** In `story_camera_screen.dart`:

```dart
  CapturedMedia? _review;
  VideoPlayerController? _preview;
  bool _posting = false;

  void _onCaptured(CapturedMedia raw) {
    // One take at a time (Review Focus 5): a second report while a review
    // is up is dropped and its file deleted, never leaked.
    if (_review != null || _posting || !mounted) {
      unawaited(_deleteQuietly(raw.path));
      return;
    }
    setState(() => _review = raw);
    unawaited(_startPreview(raw));
  }

  Future<void> _startPreview(CapturedMedia raw) async {
    if (raw.type != CapturedMediaType.video) return;
    final controller = VideoPlayerController.file(File(raw.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    } catch (error) {
      ChatLog.diagnostic('story review preview failed', error);
      await controller.dispose();
      return;
    }
    if (!mounted || !identical(_review, raw)) {
      await controller.dispose();
      return;
    }
    setState(() => _preview = controller);
  }

  Future<void> _disposePreview() async {
    final controller = _preview;
    _preview = null;
    await controller?.dispose();
  }

  Future<void> _retake() async {
    final raw = _review;
    if (raw == null || _posting) return;
    await _disposePreview();
    await _deleteQuietly(raw.path);
    if (!mounted) return;
    setState(() => _review = null);
    await _captureKey.currentState?.reset();
  }

  /// Close or back during review: the take has not been shared, so ask.
  Future<void> _closeFromReview() async {
    final raw = _review;
    if (raw == null || _posting) return;
    final noun = raw.type == CapturedMediaType.image ? 'photo' : 'video';
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Discard this $noun?'),
        content: const Text("It hasn't been shared."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _disposePreview();
    await _deleteQuietly(raw.path);
    if (!mounted) return;
    setState(() => _review = null);
    context.pop();
  }

  Future<void> _share() async {
    final raw = _review;
    if (raw == null || _posting) return; // Review Focus 5
    // Captured before the first await: the camera may unmount below.
    final pipeline = ref.read(storyPostPipelineProvider);
    final messenger = ScaffoldMessenger.of(context);
    final pin = _pin;
    setState(() => _posting = true);
    final outcome = await pipeline.post(
      StoryPostRequest(
        raw: raw,
        relationshipId: widget.relationshipId,
        utcOffsetMinutes:
            (widget.utcOffsetMinutesReader ?? _defaultUtcOffsetMinutesReader)(),
        place: pin?.placeForPost,
        videoPreparer: widget.videoPreparerFactory,
        imagePreparer: widget.imagePreparerFactory,
        thumbnailPreparer: widget.thumbnailPreparerFactory,
        thumbnailGrabber: widget.thumbnailGrabber,
      ),
      callerListening: () => mounted,
    );
    if (!mounted) return; // the pipeline already queued it or raised a notice
    switch (outcome) {
      case StoryPostQueued(:final placeDropped):
        await _disposePreview();
        if (!mounted) return;
        setState(() {
          _review = null;
          _posting = false;
        });
        context.pop();
        if (placeDropped) {
          messenger.showSnackBar(const SnackBar(
            content: Text("Shared without a place. We couldn't find where you are in time."),
          ));
        }
      case StoryPostNotSaved():
        setState(() => _posting = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('That could not be saved. Try again.')),
        );
      case StoryPostRejected(:final code):
        messenger.showSnackBar(
          SnackBar(content: Text(storyPrepareFailureMessage(code, raw.type))),
        );
        await _disposePreview();
        if (!mounted) return;
        setState(() {
          _review = null;
          _posting = false;
        });
        await _captureKey.currentState?.reset();
    }
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }
```

Keep `_defaultUtcOffsetMinutesReader` and `_deleteQuietly`. Delete `_handled`, `_enqueuing`, `_prepareAndEnqueue`, `_stayOnCameraAfterFailure`, `_buildThumbnail`, `_thumbnailPreparer`, `_defaultThumbnailGrabber`, `_mimeTypeFor`, `_tempTargetPath` and their now-unused imports (`path`, `path_provider`, `video_thumbnail`, `dart:typed_data` if unused, `story_outbox_record`, `story_outbox_controller`). Add imports for `video_player`, `story_post_pipeline.dart`, `story_post_copy.dart` and `story_review_layer.dart`. `build`:

```dart
  @override
  Widget build(BuildContext context) {
    final review = _review;
    return PopScope(
      canPop: review == null && !_posting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _posting) return;
        unawaited(_closeFromReview());
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: CaptureCameraScreen(
              key: _captureKey,
              allow: CaptureKinds.photoAndVideo,
              resolutionPreset: ResolutionPreset.veryHigh,
              microphoneOptional: true,
              copy: CaptureCameraCopy.story,
              isReviewing: review != null,
              videoPreparerFactory: widget.videoPreparerFactory,
              imagePreparerFactory: widget.imagePreparerFactory,
              onCaptured: _onCaptured,
              onCancelled: _onCaptureCancelled,
            ),
          ),
          if (review != null)
            Positioned.fill(
              child: StoryReviewLayer(
                media: review,
                videoController: _preview,
                posting: _posting,
                onShare: () => unawaited(_share()),
                onRetake: () => unawaited(_retake()),
                onClose: () => unawaited(_closeFromReview()),
              ),
            ),
          // "Pin to our map" (couple map): on the live camera and on the
          // review, read when Share is tapped. Kept mounted while sharing
          // (hidden and inert), so a failed share brings back the same
          // switch with no second lookup or prompt.
          Positioned(
            top: Spacing.xxl,
            left: 64,
            right: 64,
            child: Offstage(
              offstage: _posting,
              child: IgnorePointer(
                ignoring: _posting,
                child: Center(
                  child: StoryPinToggle(
                    relationshipId: widget.relationshipId,
                    onController: (c) => _pin = c,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
```

Rewrite the library doc's steps 1–4 (`:24-42`) to describe the flow: shutter → review (Retake / Share) → `StoryPostPipeline` → pop. Also replace the "there is no review layer" comments.

- [ ] **Step 5: Update `story_camera_test.dart` (allowed edits only).**
  - At the top, add `import 'package:attune/features/stories/data/story_media_vault.dart';` and `import 'package:path/path.dart' as p;`.
  - In `buildContainer`, add `storyMediaVaultProvider.overrideWithValue(StoryMediaVault(supportDirectory: () async => Directory(p.join(tempDir.path, 'support'))..createSync(recursive: true))),` to the overrides.
  - In `tapShutter`, after the existing `await tester.pump(const Duration(milliseconds: 50));` that follows `gesture.up()`, insert:

```dart
    // Owner ruling 1: the shutter opens a review; Share posts.
    final share = find.byKey(const ValueKey('story-review-share'));
    if (share.evaluate().isNotEmpty) {
      await tester.tap(share);
      await tester.pump();
    }
```

  - Replace the existing single `await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));` in `tapShutter` with a loop. The vault move is several sequential real file operations, and each one needs a real wait plus a pump:

```dart
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
```
  - In "a photo generates a thumbnail before enqueueing", replace `final thumbFile = File(record.localThumbnailPath);` with `final thumbFile = File(p.join(tempDir.path, 'support', record.localThumbnailPath));`. The record now stores the vault-relative path (Task 7).

- [ ] **Step 6: Run and see everything pass**

Run: `flutter test test/features/stories/story_review_test.dart test/features/stories/story_camera_test.dart test/features/stories/story_camera_config_test.dart`
Expected: all pass. That includes the four couple-map tests (the pill hides when sharing, not at the shutter) and "a capture that cannot be queued keeps the user on the camera" (it now stays on the review with the same message).

- [ ] **Step 7: Run tests:** `flutter test test/features/stories test/features/couple_map` plus the Task 11 regression gate. Expected: all pass.

---

### Task 18: The rings row says what is happening: Cancel, reasons, a confirmed Discard

Fixes 01 #13 (UI), 01 #20 (failure copy with no reason; Retry on hopeless errors), 06 #14 (one-tap Discard of the only copy), and the notice path for Task 16.

**Files:**
- Create: `lib/features/stories/presentation/widgets/story_outbox_notices.dart`
- Create: `test/features/stories/story_outbox_notices_test.dart`
- Modify: `lib/features/stories/domain/story_post_copy.dart` (add `storyOutboxFailureCopy`, `storyPendingStatus`)
- Modify: `lib/features/stories/presentation/widgets/story_rings_row.dart`: `_pendingProgressFor` (`:51-64`); `build` (`:99-260`) uses the notices; delete `_FailedStoryNotice` (`:327-380`).

**Interfaces:**
- Consumes: Task 8's `cancel` / `StoryCancelOutcome` / `storyUploadProgressProvider`; Task 16's `storyPostNoticeProvider`; Task 1's `StoryApiError.kindForCode`.
- Produces:
  - `({String message, bool canRetry}) storyOutboxFailureCopy(String? code, CapturedMediaType type)`
  - `String storyPendingStatus(StoryOutboxRecord record)`
  - `StoryPendingNotice({required StoryOutboxRecord record})`, `StoryFailedNotice({required StoryOutboxRecord record})`, `StoryPrepareFailedNotice()`

- [ ] **Step 1: Write the failing tests.** Create `test/features/stories/story_outbox_notices_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:attune/features/stories/presentation/widgets/story_outbox_notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('notices'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Real file I/O (vault deletes) under FakeAsync: wait, then pump, repeatedly.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
  }

  Future<OutboxHarness> pump(WidgetTester tester, Widget notice, {OutboxHarness? harness}) async {
    final h = harness ?? outboxHarness();
    addTearDown(h.container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp(home: Scaffold(body: notice)),
    ));
    await tester.pump();
    return h;
  }

  test('failure copy carries the reason, and Retry only where it can help', () {
    var c = storyOutboxFailureCopy(StoryErrorCodes.mediaMissing, CapturedMediaType.image);
    expect(c.message, 'This photo is no longer on this phone.');
    expect(c.canRetry, isFalse);
    c = storyOutboxFailureCopy(StoryErrorCodes.mediaTooLarge, CapturedMediaType.video);
    expect(c.message, 'This video is too large to post.');
    expect(c.canRetry, isFalse);
    c = storyOutboxFailureCopy('FORBIDDEN', CapturedMediaType.image);
    expect(c.canRetry, isFalse);
    c = storyOutboxFailureCopy(null, CapturedMediaType.image);
    expect(c.message, 'Your story could not be posted.');
    expect(c.canRetry, isTrue);
  });

  test('a story waiting on the network says so', () {
    final waiting = outboxRecord(dir).copyWith(
      lastErrorCode: StoryErrorCodes.network,
      nextAttemptAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    expect(storyPendingStatus(waiting),
        "Waiting for a connection. Your story will post when you're back online.");
    expect(storyPendingStatus(outboxRecord(dir)), 'Posting your story…');
  });

  testWidgets('Discard asks first and names what is lost (06 #14)', (tester) async {
    final failed = outboxRecord(dir).copyWith(
      state: StoryOutboxState.failedPermanent,
      lastErrorCode: StoryErrorCodes.mediaTooLarge,
    );
    final h = outboxHarness();
    await h.store.put(outboxUserId, failed);
    await pump(tester, StoryFailedNotice(record: failed), harness: h);
    expect(find.text('Retry'), findsNothing, reason: 'hopeless: no Retry');

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this photo?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(await h.store.readAll(outboxUserId), hasLength(1));

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => h.store.readAll(outboxUserId)), isEmpty);
  });

  testWidgets('Cancel on a posting story asks, then stops it', (tester) async {
    final h = outboxHarness();
    h.gateway.uploadGate = Completer<void>();
    final record = outboxRecord(dir);
    unawaited(h.controller().enqueue(record));
    await pump(tester, StoryPendingNotice(record: record), harness: h);
    await settle(tester); // the drive reaches the held upload
    expect(find.text('Posting your story…'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this story?'), findsOneWidget);
    await tester.tap(find.text('Cancel story'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => h.store.readAll(outboxUserId)), isEmpty);
  });

  testWidgets('a take that failed after the camera closed is shown once, then '
      'dismissed', (tester) async {
    final h = await pump(tester, const StoryPrepareFailedNotice());
    expect(find.byType(StoryPrepareFailedNotice), findsOneWidget);
    expect(find.textContaining("couldn't"), findsNothing);
    h.container.read(storyPostNoticeProvider.notifier).state = const StoryPostNotice(
      code: 'media_too_long',
      mediaType: CapturedMediaType.video,
    );
    await tester.pump();
    expect(find.text("Your story wasn't shared. That video is longer than a minute."),
        findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(h.container.read(storyPostNoticeProvider), isNull);
  });

  test('the rings row uses the notices', () {
    final src = File('lib/features/stories/presentation/widgets/story_rings_row.dart')
        .readAsStringSync();
    expect(src, contains('StoryPendingNotice('));
    expect(src, contains('StoryFailedNotice('));
    expect(src, contains('StoryPrepareFailedNotice('));
    expect(src, contains('storyUploadProgressProvider'));
  });
}
```

- [ ] **Step 2: Run and see them fail:** `flutter test test/features/stories/story_outbox_notices_test.dart`. Expected: compile failure.

- [ ] **Step 3: Implement the copy.** Append to `story_post_copy.dart` (add imports for `story_outbox_record.dart` and `story_repository.dart`):

```dart
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
    'UNAUTHORIZED' => (
        message: 'Sign in again to post your story.',
        canRetry: true,
      ),
    _ => (message: 'Your story could not be posted.', canRetry: true),
  };
}

/// The pending line under the ring.
String storyPendingStatus(StoryOutboxRecord record) {
  final code = record.lastErrorCode;
  final waiting = code != null &&
      record.nextAttemptAt != null &&
      switch (StoryApiError.kindForCode(code)) {
        StoryFailureKind.offline || StoryFailureKind.rateLimited => true,
        _ => false,
      };
  return waiting
      ? "Waiting for a connection. Your story will post when you're back online."
      : 'Posting your story…';
}
```

- [ ] **Step 4: Implement the notices.** Create `lib/features/stories/presentation/widgets/story_outbox_notices.dart`:

```dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _noun(CapturedMediaType t) => t == CapturedMediaType.image ? 'photo' : 'video';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String keep,
  required String destroy,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(keep)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: Text(destroy),
        ),
      ],
    ),
  );
  return result == true;
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.icon, required this.color, required this.text, required this.actions});
  final IconData icon;
  final Color color;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Spacing.sm),
    child: MergeSemantics(
      child: Row(
        children: [
          Icon(icon, size: IconSizes.sm, color: color),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );
}

/// The story on its way: what it is waiting for, and Cancel (01 #13).
class StoryPendingNotice extends ConsumerWidget {
  const StoryPendingNotice({super.key, required this.record});
  final StoryOutboxRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return _NoticeRow(
      icon: Icons.cloud_upload_outlined,
      color: colors.onSurfaceVariant,
      text: storyPendingStatus(record),
      actions: [
        TextButton(
          onPressed: () => unawaited(_cancel(context, ref)),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(storyOutboxProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      context,
      title: 'Cancel this story?',
      body: "It hasn't been posted yet.",
      keep: 'Keep posting',
      destroy: 'Cancel story',
    );
    if (!ok) return;
    final outcome = await notifier.cancel(record.clientStoryId);
    if (outcome == StoryCancelOutcome.alreadyPosting) {
      messenger.showSnackBar(const SnackBar(
        content: Text('It has already posted. You can delete it from your story.'),
      ));
    }
  }
}

/// A story that will not post on its own: why, Retry when it can help,
/// and a Discard that asks first (06 #14).
class StoryFailedNotice extends ConsumerWidget {
  const StoryFailedNotice({super.key, required this.record});
  final StoryOutboxRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final notifier = ref.read(storyOutboxProvider.notifier);
    final copy = storyOutboxFailureCopy(record.lastErrorCode, record.mediaType);
    return _NoticeRow(
      icon: Icons.error_outline_rounded,
      color: colors.error,
      text: copy.message,
      actions: [
        if (copy.canRetry)
          TextButton(
            onPressed: () => unawaited(notifier.retry(record.clientStoryId)),
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: 'Discard this ${_noun(record.mediaType)}?',
              body: "It hasn't been posted, and it can't be recovered.",
              keep: 'Keep',
              destroy: 'Discard',
            );
            if (ok) await notifier.discard(record.clientStoryId);
          },
          child: const Text('Discard'),
        ),
      ],
    );
  }
}

/// A take that failed to prepare after its camera had closed (Task 16).
class StoryPrepareFailedNotice extends ConsumerWidget {
  const StoryPrepareFailedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(storyPostNoticeProvider);
    if (notice == null) return const SizedBox.shrink();
    return _NoticeRow(
      icon: Icons.error_outline_rounded,
      color: Theme.of(context).colorScheme.error,
      text: "Your story wasn't shared. "
          '${storyPrepareFailureMessage(notice.code, notice.mediaType)}',
      actions: [
        TextButton(
          onPressed: () => ref.read(storyPostNoticeProvider.notifier).state = null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
```

Run `dart format` on this new file.

- [ ] **Step 5: Wire the rings row.** In `story_rings_row.dart`:
  - Import the notices file and `story_outbox_controller.dart` (already imported).
  - Change `_pendingProgressFor` to:

```dart
double _pendingProgressFor(StoryOutboxState state, {double? mediaFraction}) {
  switch (state) {
    case StoryOutboxState.queued:
      return 0.05;
    case StoryOutboxState.uploadingMedia:
      // Byte-accurate while the media streams (Task 8), step-based otherwise.
      return mediaFraction == null ? 0.35 : 0.05 + 0.6 * mediaFraction;
    case StoryOutboxState.uploadingThumbnail:
      return 0.7;
    case StoryOutboxState.finalizing:
      return 0.9;
    case StoryOutboxState.failedPermanent:
      return 1.0;
  }
}
```

  - In `build`, add `final progress = ref.watch(storyUploadProgressProvider);` and pass `mediaFraction: progress[myPending.clientStoryId]` in the pending `StoryRing` call.
  - Replace the `for (final failed in myFailed) _FailedStoryNotice(...)` with:

```dart
          if (myPending != null)
            StoryPendingNotice(
              key: ValueKey('pending-${myPending.clientStoryId}'),
              record: myPending,
            ),
          for (final failed in myFailed)
            StoryFailedNotice(key: ValueKey(failed.clientStoryId), record: failed),
          const StoryPrepareFailedNotice(),
```

  - Delete the `_FailedStoryNotice` class. Keep its doc paragraph (spec §6.1, "never silently disappears") by moving it onto `StoryFailedNotice`.

Regression note: this row is the Conversations header (Wave 4 owns its ring geometry; this task does not touch `story_ring.dart`). The golden fixture has no outbox records, so `story_rings_light/dark.png` must be unchanged. If a golden differs, stop and report; do not regenerate.

- [ ] **Step 6: Run and see them pass:** `flutter test test/features/stories/story_outbox_notices_test.dart test/features/stories/story_rings_test.dart`. Expected: all pass. The existing "a failedPermanent record IS surfaced, with Retry and Discard" test still finds its three strings, because a record with no code gets the default copy and Retry.

- [ ] **Step 7: Run tests:** `flutter test test/features/stories test/features/conversations 2>/dev/null || flutter test test/features/stories`. Expected: all pass.

---

### Task 19: Amend STORIES.md §6, and the whole-wave regression run

**Files:**
- Modify: `lib/architecture/STORIES.md`, only these regions (Wave 1 has uncommitted edits elsewhere in this file; touch nothing else):
  - §5.1's pending-tile sentence;
  - §6 (`:886-893`, "owns capture, review…");
  - §6.1 (`:913-962`);
  - §6.4 (`:1040-1046`).

- [ ] **Step 1: Amend §6.** Replace "that owns capture, review, permissions, switching and media preparation" with "that owns capture, permissions, switching and media preparation; each adapter owns its own review". After the "Two thin adapters consume it" paragraph, add:

```markdown
**Owner ruling (2026-10-23 review): stories review before posting.** The
story adapter shows the take full screen with **Retake** and **Share**; the
shutter no longer posts on its own. This overrides §6.1's earlier "the
outbox queue is the review". The review is built in the story adapter on
the shared module's existing `isReviewing` contract, so the module and the
streak adapter are unchanged. Posting a take after Share runs in
`StoryPostPipeline` (a provider), not in the widget, so a camera that
unmounts mid-prepare still queues the story; a failure it cannot show on
the camera is shown under the rings instead. Closing the review asks
before discarding the take.
```

- [ ] **Step 2: Amend §6.1.** Replace the record field block with:

```
clientStoryId, relationshipId, localMediaPath, localThumbnailPath,
mediaType, mimeType, width, height, durationMs, utcOffsetMinutes,
state, attempts, strikes, nextAttemptAt, lastErrorCode, createdAt,
mediaIntent, thumbnailIntent, place
```

Replace the paragraph "States are … safe to retry." with:

```markdown
States are `queued`, `uploading_media`, `uploading_thumbnail`,
`finalizing`, and `failed_permanent`. Every failure is classified
(`StoryFailureKind`) the way chat's outbox classifies its own:

- **Offline-class** (no answer, a stalled or dropped upload, Storage
  5xx/408/401) and `RATE_LIMITED` never count toward the cap: they retry at
  chat's equal-jitter backoff capped at 64 s for as long as it takes, and
  the queue is flushed at once when connectivity returns, when the app
  comes back to the foreground, and on every sign-in.
- **Unknown-shape** failures and **stale intents** (Storage 403, finalize
  `UNAVAILABLE`) are strikes; five strikes is `failed_permanent`. A stale
  intent also drops the pair and re-queues, so the next attempt mints a
  fresh pair and re-uploads.
- **Storage 409** on the record's own key means an earlier attempt's
  upload landed: the step is complete (finalize re-verifies size and MIME).
- **Permanent at once, with a reason:** 413 (`media_too_large`), 415/MIME
  (`media_type_rejected`), a missing local file (`media_missing`, Discard
  only), `UNAUTHORIZED`/`FORBIDDEN`/`INVALID_INPUT`, and `UNAVAILABLE`
  outside finalize.

Uploads stream through the same uploader chat uses (20 s stall bound, 60 s
response bound, abort on cancel, byte progress). Intents are persisted in
the encrypted record, so a restart resumes the same keys; both are
re-minted, without a strike, when either is within 2 minutes of
`expires_at`. The outbox starts with the app (not with the rings row).
```

Replace "The Mine ring shows a local pending tile with progress; a permanent failure exposes Retry and Discard (§5.1). Local files remain in app-private storage until success or explicit discard, and logout/account removal clears them." with:

```markdown
The Mine ring shows a local pending tile with byte progress while the
media streams, and a line beneath it saying what it is waiting for, with
**Cancel** (offered until finalize has been sent). A permanent failure says
why, offers Retry only where retrying can help, and asks before Discard
(§5.1). Local files live in app-private storage,
`Application Support/story_outbox/<userId>/<clientStoryId>/`, stored as
paths relative to Application Support (the iOS container path changes on
update), until success, Cancel or Discard. Sign-out and quick-exit sign-out
wipe every row and file; any sign-in wipes every other account's. The
outbox database (+`-wal`/`-shm`) and the folder are excluded from iOS and
Android backups.
```

- [ ] **Step 3: Amend §6.4 and §5.1.** Append to §6.4:

```markdown
Wave 2 (2026-10-23) added module parameters that default to the streak
camera's shipped behaviour: `resolutionPreset` (streaks `medium`; stories
`veryHigh`), `microphoneOptional` (stories: a refused microphone still
takes photos), and `copy` (stories never say "streak"). Applied to both
adapters deliberately: Close and Open Settings on the permission screen,
screen-reader labels on the shutter and flip, recovery when stopping a
recording fails, and camera release on inactive / re-initialise on resume
(an interrupted take is kept). The 60 s tolerance and whole-clip export
are opt-in on `ChatVideoPreparer(boundaryTolerance:)` and used by stories
only. `streak_camera_contract_test.dart` stayed green unchanged.
```

In §5.1, change the sentence describing the pending tile so it matches §6.1's new wording ("…a local pending tile with byte progress and a status line with Cancel…").

- [ ] **Step 4: Run the whole-wave regression.**

```bash
cd /Users/user/attune
flutter analyze lib/features/stories lib/features/chat/presentation/screens/capture_camera_screen.dart \
  lib/features/chat/domain/services/chat_video_preparer.dart lib/features/auth/providers/auth_provider.dart \
  lib/features/safety/data/safety_sign_out.dart lib/app/app.dart
flutter test test/features/stories test/features/timeline test/features/couple_map \
  test/features/chat/streak_camera_contract_test.dart test/features/chat/streak_camera_test.dart \
  test/features/chat/streak_camera_photo_test.dart test/features/chat/streak_lock_test.dart \
  test/features/chat/streak_preview_test.dart test/features/chat/chat_video_preparer_test.dart \
  test/features/chat/chat_state_send_video_message_test.dart \
  test/features/chat/chat_state_send_ephemeral_video_message_test.dart \
  test/features/chat/video_trim_screen_test.dart test/features/chat/chat_media_uploader_test.dart \
  test/features/chat/chat_backup_exclusion_test.dart test/features/chat/chat_outbox_triggers_test.dart \
  test/features/auth test/features/safety test/core test/app
```
Expected: analyze is clean for these paths (no new warnings), and every test passes. Then run the full suite once: `flutter test`. Compare its failures (if any) with the baseline from "Before you start". Report any new failure; do not fix unrelated ones.

- [ ] **Step 5: Confirm nothing outside scope moved.** `git status --porcelain` must show only:
  - the files this plan names;
  - the user's pre-existing entries;
  - Wave 1's pre-existing entries.

  `git diff --stat lib/architecture/STORIES.md` must show changes inside §5.1/§6 only. Spot-check it with `git diff lib/architecture/STORIES.md | grep '^@@'`: the hunks must sit in the §5.1 and §6 line ranges, plus Wave 1's own pre-existing hunks.

- [ ] **Step 6: Device checklist (for the owner; not automatable).** Record the results in `docs/reviews/2026-10-23-stories-review/` alongside the review:
  1. Airplane mode → take a photo → Share → the ring line says "Waiting for a connection…". After 5 minutes it is still queued. Turn the network on → it posts within seconds without opening Conversations.
  2. Post a 60 s video on a throttled uplink (Network Link Conditioner, 1 Mbps). It posts; the ring shows byte progress; there is no permanent failure.
  3. Background the app for 20 minutes mid-upload, then return → it re-mints and posts (Storage 403 on the old key, then success).
  4. Deny the microphone in Settings → the story camera takes photos; a hold says video needs the mic; Settings opens. Do the same in the streak camera: today's behaviour is unchanged.
  5. A full-minute hold reaches review and shares (`duration_ms = 60000`). A 0.8 s clip shares.
  6. Mid-hold phone call → the take is kept and reviewed; the preview is live on return.
  7. Sign out with a story queued → nothing in `Application Support/story_outbox/` and no row. Sign back in → nothing auto-posts.
  8. iOS: `xattr -p com.apple.metadata:com_apple_backup_excludeItem` on `story_outbox/` and `attune_story_outbox.sqlite` (or check iCloud backup size). Android: `adb shell bmgr backupnow` excludes them.
  9. VoiceOver: "Take photo, hold for video, button", and a double-tap takes a photo; "Switch camera".
  10. Photos are 1920 px on the long edge, not 640.

---

## Self-review (done while writing; the executor need not repeat it)

- **Spec coverage.**
  - **P1:**
    - network and RATE_LIMITED never strike (T4);
    - capped backoff with jitter (T4);
    - flush on resume, reconnect and sign-in (T6);
    - classify StorageException: 403 (T1, T4), 409 (T1, T4), 413/MIME (T1, T4), missing file (T1, T4, T7);
    - re-mint near expiry (T5);
    - abort- and stall-aware upload (T2);
    - persist intents (T3, T5);
    - app-level start (T6);
    - app-private media (T7);
    - cancel in flight (T8, T18);
    - confirm Discard (T18);
    - reasoned copy (T16, T18);
    - dispose and epoch guards (T6).
  - **P2:**
    - sign-out, quick exit and account switch (T9);
    - BackupExclusion for the DB, -wal and -shm, plus both XMLs (T10);
    - the folder (T7);
    - `auth_provider` change is additive, in its own try, and bounded (T9).
  - **P3:**
    - the resolution preset (T11);
    - mic re-init without audio, plus the "needs the mic" copy (T12);
    - embedder copy, Close and Open Settings (T12);
    - accessibility labels (T13);
    - lifecycle (T14);
    - stopVideoRecording errors (T13);
    - the 60 s tolerance and the fractional trim (T15).
  - **P4:**
    - the review in the adapter only (T17);
    - enqueue survives unmount (T16, T17);
    - closing between shutter and enqueue (T17: close confirm, Close hidden while sharing, PopScope).
  - STORIES.md amendment (T19).
- **Placeholders:** none. Every code step has code.
- **Type consistency:** these names were checked across tasks:
  - `StoryFailureKind`, `StoryErrorCodes`, `StoryApiError.fromFailure` and `.kind` / `.kindForCode`;
  - `strikes`, `mediaIntent` / `thumbnailIntent` / `hasIntents` / `clearIntents`;
  - `maxStrikes`, `backoffWindowFor`, `remintMargin`;
  - `flush({force})`, `debugHasRetryTimer`, `StoryOutboxStore.epoch` / `wipeAll` / `removeOtherUsers`;
  - `StoryMediaVault.adopt` / `resolve` / `resolveRecord` / `deleteFor` / `wipeAll` / `wipeExcept`, `StoryRecordPaths.withPaths`;
  - `StoryCancelOutcome`, `storyUploadProgressProvider`;
  - `StoryOutboxWiper`, `storyOutboxWiperProvider`, `storyOutboxTriggersProvider`;
  - `CaptureCameraCopy(.story)`, `resolutionPreset`, `microphoneOptional`, `openSettings`;
  - `ChatVideoPreparer(boundaryTolerance:)`, `debugExportWindow`, `debugReportedDurationMs`;
  - `StoryPostRequest`, `StoryPostQueued` / `NotSaved` / `Rejected`, `StoryPostNotice`, `storyPostPipelineProvider` / `storyPostNoticeProvider`;
  - `storyPrepareFailureMessage`, `storyOutboxFailureCopy`, `storyPendingStatus`;
  - `StoryReviewLayer`, `StoryPendingNotice` / `StoryFailedNotice` / `StoryPrepareFailedNotice`.
- **Review Focus:**
  1. clock skew: T5 test;
  2. sign-out mid-upload: T6 epoch test and T9;
  3. legacy record: T3 and T7;
  4. interrupted hold: T14;
  5. double taps: T17.
