# Stories — Plan B: Capture and Posting

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A story can be captured (photo or video) and posted, surviving
a restart and a bad network, without changing how streaks behave.

**Architecture:** The streak camera's capture half is EXTRACTED into a
destination-neutral module that returns a `CapturedMedia` result. Two
thin adapters consume it — a streak adapter preserving today's exact
behaviour, and a story adapter that queues to a durable local outbox.
Photo capture is added to the shared camera; streaks keep using video
only.

**Tech Stack:** Flutter, Riverpod, `camera`, Drift/SQLite (the chat
outbox's persistence), Supabase RPCs from Plan A.

**Spec:** `docs/superpowers/specs/2026-09-11-stories-design.md`
**Depends on:** Plan A (merged or on this branch). Its RPCs are live.

## Global Constraints

- **The streak path's behaviour must not change.** Its capture, review
  sheet, sounds, replay preference, view budget and outbox handoff are
  covered by tests BEFORE anything is extracted (§6.3).
- Capture is **extracted, not branched**. A destination enum scattering
  `if (isStory)` through a 760-line shipped module is the thing this
  plan exists to avoid (§6).
- Photo capture is **new work**: no in-app camera calls `takePicture()`
  today, and no viewer renders an image (§6.2).
- Stories post through **their own durable queue**. Calling a repository
  inherits nothing from the chat outbox (§6.1).
- Outbox states, verbatim: `queued`, `uploading_media`,
  `uploading_thumbnail`, `finalizing`, `failed_permanent` (§6.1).
- **`clientStoryId` makes a lost finalize response safe to retry** — the
  server's `create_story_item` is idempotent on `(author_id,
  client_story_id)` (§6.1).
- **Finalization time is posting time**: it sets the 24-hour window and
  `occurred_on`, even if an offline capture waited in the queue (§6.1).
- A permanent failure **exposes Retry and Discard; it never silently
  disappears** (§6.1).
- Thumbnails: **400px long edge, JPEG, quality 75**, generated
  client-side before finalizing. `thumbnail_key` is NOT NULL server-side,
  so a story without one cannot be created (§4.3).
- Media limits: image JPEG ≤ 5MB / 2560px long edge; video MP4 ≤ 25MB,
  500ms–60000ms. `kStreakSegmentDuration` is 60s and already the capture
  ceiling (§4.2, §8).
- Local files stay in app-private storage until success or explicit
  discard; logout and account removal clear them (§6.1).
- The `stories` feature flag gates new upload intents server-side. The
  client must handle a `rate_limited` or flag-off refusal as retryable
  without losing the capture.

## The server contract (Plan A, live and verified)

```
create_story_upload_intent(p_relationship_id uuid, p_object_kind text,
                           p_media_type text, p_mime_type text)
  -> jsonb {intent_id, storage_key, bucket, expires_at}
     or {error:true, code, message}
  p_object_kind: 'media' | 'thumbnail'
  thumbnail MUST be image/jpeg; media MUST be image/jpeg or video/mp4
  15-minute expiry. 120 calls/hour/user; refuses at 20 live unused intents.

create_story_item(p_relationship_id uuid, p_client_story_id uuid,
                  p_media_intent_id uuid, p_thumbnail_intent_id uuid,
                  p_media_width int, p_media_height int,
                  p_duration_ms int, p_utc_offset_minutes int)
  -> jsonb {story_id, existing}
     Idempotent on (author_id, client_story_id): a retry returns the
     SAME story with existing=true.
```

Upload is **intent → upload → finalize**. The intent returns a KEY, not a
signed URL; the client uploads normally and Storage RLS authorizes it
(§4.2). Bucket `story-media`, private.

## File structure

| File | Responsibility |
|---|---|
| `lib/features/stories/domain/captured_media.dart` | The camera's result type |
| `lib/features/stories/data/story_outbox_record.dart` | The queued record + its states |
| `lib/features/stories/data/story_outbox_store.dart` | Drift-backed persistence |
| `lib/features/stories/data/story_repository.dart` | The three RPC calls + uploads |
| `lib/features/stories/presentation/state/story_outbox_controller.dart` | The retry state machine |
| `lib/features/chat/presentation/screens/capture_camera_screen.dart` | The EXTRACTED camera |
| `lib/features/chat/presentation/screens/streak_camera_screen.dart` | Becomes the streak ADAPTER |
| `lib/features/stories/presentation/screens/story_camera_screen.dart` | The story adapter |
| `test/features/chat/streak_camera_contract_test.dart` | The regression harness (Task 1) |

## Test commands

```bash
flutter test test/features/chat/streak_camera_contract_test.dart
flutter test test/features/stories
flutter analyze lib test    # must stay at 0 errors
```

---

### Task 1: Lock down streak behaviour BEFORE touching it

**Files:**
- Create: `test/features/chat/streak_camera_contract_test.dart`

**Interfaces:**
- Produces: a characterization suite that must pass unchanged after
  every later task in this plan.

This task exists because the next four tasks edit a **shipped feature's**
camera. Without a harness pinning today's behaviour, a regression is
invisible until a user reports it.

- [ ] **Step 1: Read the camera and list what it does**

```bash
sed -n '1,200p' lib/features/chat/presentation/screens/streak_camera_screen.dart
grep -nE "widget.conversation|streakReplayPreferenceProvider|chatControllerProvider|AppSound.streak|streakViewBudget" \
  lib/features/chat/presentation/screens/streak_camera_screen.dart
```

The six coupling points are at lines 31, 250, 303, 372, 410, 414.

- [ ] **Step 2: Write the characterization tests**

Cover, at minimum:

```dart
testWidgets('a completed recording sends through the chat controller', (
  tester,
) async {
  // The streak path's contract: capture -> ChatVideoPreparer ->
  // sendStreakMessage with the view budget from the replay preference.
  // This is what must still be true after the extraction.
});

testWidgets('the replay preference decides the view budget', (tester) async {
  // streakViewBudget(allowReplays: true) vs false must reach
  // sendStreakMessage unchanged.
});

testWidgets('capture-ready and send play the streak sounds', (tester) async {
  // AppSound.streakCaptureReady on ready, AppSound.streakSend on send.
});

testWidgets('a rejected transcode shows the streak message and stays', (
  tester,
) async {
  // ChatVideoRejected -> "That streak could not be sent." and the
  // camera does NOT pop.
});
```

Use a fake `ChatController` and a fake recorder so no real camera is
needed — follow the fake-gateway pattern in
`test/features/games/snakes_test.dart`.

- [ ] **Step 3: Run them against UNCHANGED code**

Run: `flutter test test/features/chat/streak_camera_contract_test.dart`
Expected: PASS. They characterize what exists; a failure here means the
test is wrong, not the code.

- [ ] **Step 4: Commit**

```bash
git add test/features/chat/streak_camera_contract_test.dart
git commit -m "test(streak): characterize the camera before extracting it"
```

---

### Task 2: Extract the camera, video only, streak unchanged

**Files:**
- Create: `lib/features/stories/domain/captured_media.dart`
- Create: `lib/features/chat/presentation/screens/capture_camera_screen.dart`
- Modify: `lib/features/chat/presentation/screens/streak_camera_screen.dart`

**Interfaces:**
- Produces:
```dart
enum CapturedMediaType { image, video }

class CapturedMedia {
  const CapturedMedia({
    required this.path,
    required this.type,
    required this.width,
    required this.height,
    this.durationMs,          // null for an image
  });
  final String path;
  final CapturedMediaType type;
  final int width;
  final int height;
  final int? durationMs;
}
```
- Produces: `CaptureCameraScreen` — owns permissions, camera switching,
  segment recording, the ticker, transcode and the 25MB ceiling. Knows
  NOTHING about destinations. Pops with a `CapturedMedia?`.

- [ ] **Step 1: Move capture into the new screen**

Everything EXCEPT the six coupling points moves verbatim. The new screen
takes no `Conversation`, reads no preference provider, plays no
streak-named sound, and calls no chat controller.

- [ ] **Step 2: Make the streak screen an adapter**

`StreakCameraScreen` keeps its `Conversation` and its `_send`, but gets
its clip by pushing `CaptureCameraScreen` and awaiting the result:

```dart
final captured = await Navigator.of(context).push<CapturedMedia>(
  MaterialPageRoute(builder: (_) => const CaptureCameraScreen(
    allow: CaptureKinds.videoOnly,
  )),
);
if (captured == null) return;           // cancelled
await _send(captured, allowReplays: ref.read(streakReplayPreferenceProvider));
```

Its sounds, review sheet, view budget and `chatControllerProvider` call
stay exactly where they are.

- [ ] **Step 3: Run the regression harness**

Run: `flutter test test/features/chat/streak_camera_contract_test.dart`
Expected: PASS, unchanged. **If any test fails, the extraction changed
behaviour — fix the extraction, never the test.**

- [ ] **Step 4: Commit**

```bash
git add lib/features/stories/domain/captured_media.dart \
        lib/features/chat/presentation/screens/capture_camera_screen.dart \
        lib/features/chat/presentation/screens/streak_camera_screen.dart
git commit -m "refactor(camera): extract capture; streak becomes an adapter"
```

---

### Task 3: Photo capture

**Files:**
- Modify: `lib/features/chat/presentation/screens/capture_camera_screen.dart`
- Test: `test/features/stories/capture_camera_test.dart`

**Interfaces:**
- Consumes: `CapturedMedia` from Task 2.
- Produces: `CaptureKinds { videoOnly, photoAndVideo }` — the streak
  adapter passes `videoOnly`, so streaks stay video-only (§6.2.1).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('a tap takes a photo, a hold records video', (tester) async {
  // The idiom both reference apps use. A tap must NOT start a
  // recording, and a hold must NOT also fire the shutter.
});

testWidgets('videoOnly hides the shutter entirely', (tester) async {
  // The streak adapter passes videoOnly; a photo affordance there
  // would offer a capture streaks cannot send.
});

testWidgets('a photo carries no duration', (tester) async {
  // CapturedMedia.durationMs must be null for an image — the server
  // CHECK refuses an image row with a duration.
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/stories/capture_camera_test.dart`
Expected: FAIL — `CaptureKinds` does not exist.

- [ ] **Step 3: Implement**

Add the tap/hold gesture split and `takePicture()`. Prepare the image to
at most 2560px on the long edge and ≤5MB (§4.2). A photo's
`durationMs` is null.

- [ ] **Step 4: Run both suites**

```bash
flutter test test/features/stories/capture_camera_test.dart
flutter test test/features/chat/streak_camera_contract_test.dart
```
Expected: both PASS. The second proves streaks are untouched.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/capture_camera_screen.dart \
        test/features/stories/capture_camera_test.dart
git commit -m "feat(camera): tap for a photo, hold for video"
```

---

### Task 4: The story repository

**Files:**
- Create: `lib/features/stories/data/story_repository.dart`
- Test: `test/features/stories/story_repository_test.dart`

**Interfaces:**
- Produces:
```dart
abstract class StoryGateway {
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,     // 'media' | 'thumbnail'
    required String mediaType,      // 'image' | 'video'
    required String mimeType,
  });
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
  });
  Future<StoryFinalizeResult> finalizeStory({ /* the 8 RPC params */ });
}

class StoryFinalizeResult {
  const StoryFinalizeResult({required this.storyId, required this.existing});
  final String storyId;
  final bool existing;
}
```

- [ ] **Step 1: Write the failing tests**

```dart
test('an error jsonb becomes a typed error, never a raw exception', () {
  // Checklist 2.4/5.5: {error:true, code, message} -> StoryApiError
  // carrying the server's message. The code stays internal.
});

test('a rate_limited refusal is marked retryable', () {
  // The outbox must retry this rather than failing permanently.
});

test('uploads use upsert: false', () {
  // Spec §4.2. An upsert would let a second capture overwrite an
  // object another intent already claimed.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

Follow `snakes_service.dart`'s shape: an `_unwrap` that throws a typed
error on `{error:true}`, and a 30-second timeout on every call
(checklist 1.2).

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/stories/data/story_repository.dart \
        test/features/stories/story_repository_test.dart
git commit -m "feat(stories): the repository — intents, uploads, finalize"
```

---

### Task 5: The durable outbox

**Files:**
- Create: `lib/features/stories/data/story_outbox_record.dart`
- Create: `lib/features/stories/data/story_outbox_store.dart`
- Test: `test/features/stories/story_outbox_store_test.dart`

**Interfaces:**
- Produces the record, with the spec's fields verbatim (§6.1):
```dart
enum StoryOutboxState {
  queued, uploadingMedia, uploadingThumbnail, finalizing, failedPermanent,
}

class StoryOutboxRecord {
  final String clientStoryId;      // idempotency key, survives restart
  final String relationshipId;
  final String localMediaPath;
  final String localThumbnailPath;
  final CapturedMediaType mediaType;
  final String mimeType;
  final int width;
  final int height;
  final int? durationMs;
  final int utcOffsetMinutes;
  final StoryOutboxState state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final DateTime createdAt;
}
```

- [ ] **Step 1: Write the failing tests**

```dart
test('a queued story survives a restart', () async {
  // The whole reason this is durable. Write, dispose the store,
  // reopen it, and the record is still there with its clientStoryId.
});

test('clientStoryId is stable across retries', () async {
  // A new id per attempt would post twice — create_story_item is
  // idempotent on (author_id, client_story_id), and that is only
  // worth anything if the client keeps the id.
});

test('a permanent failure is retained, not dropped', () async {
  // Spec §6.1: "it never silently disappears." failed_permanent stays
  // readable so the UI can offer Retry and Discard.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

Follow `lib/features/chat/data/cache/chat_cache_backend_io.dart` — the
same Drift/SQLite backend that holds `chat_outbox`, with a separate
`story_outbox` table. Read that file first.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/stories/data/story_outbox_record.dart \
        lib/features/stories/data/story_outbox_store.dart \
        test/features/stories/story_outbox_store_test.dart
git commit -m "feat(stories): a durable outbox that survives restart"
```

---

### Task 6: The posting state machine

**Files:**
- Create: `lib/features/stories/presentation/state/story_outbox_controller.dart`
- Test: `test/features/stories/story_outbox_controller_test.dart`

**Interfaces:**
- Consumes: `StoryGateway` (Task 4), `StoryOutboxStore` (Task 5).
- Produces: `storyOutboxProvider` — enqueue, flush on start and on
  connectivity, retry, discard.

- [ ] **Step 1: Write the failing tests**

```dart
test('the happy path walks every state in order', () async {
  // queued -> uploadingMedia -> uploadingThumbnail -> finalizing -> gone
});

test('a dropped finalize response does not post twice', () async {
  // The gateway throws after the server committed. The retry sends the
  // SAME clientStoryId and the server returns existing:true. Exactly
  // one story exists.
});

test('an expired intent mints a new pair and re-uploads', () async {
  // Spec §6.1. The old unused objects are the server cleanup's problem,
  // not the client's.
});

test('a permanent failure stops retrying and stays visible', () async {
  // Bounded exponential backoff, then failedPermanent with Retry and
  // Discard available. It must not spin forever.
});

test('discard deletes the local files', () async {
  // Spec §6.1: local files live in app-private storage until success
  // or explicit discard.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

Bounded exponential backoff, following the chat outbox's cadence.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Mutation-test the idempotency**

Make the controller mint a fresh `clientStoryId` per attempt. The
double-post test MUST fail. Restore. A retry that posts twice is the
failure this whole design exists to prevent.

- [ ] **Step 6: Commit**

```bash
git add lib/features/stories/presentation/state/story_outbox_controller.dart \
        test/features/stories/story_outbox_controller_test.dart
git commit -m "feat(stories): the posting state machine, with safe retries"
```

---

### Task 7: The story camera adapter, and end-to-end verification

**Files:**
- Create: `lib/features/stories/presentation/screens/story_camera_screen.dart`
- Test: `test/features/stories/story_camera_test.dart`

**Interfaces:**
- Consumes: `CaptureCameraScreen` (Task 2), `storyOutboxProvider` (Task 6).

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('capturing enqueues, it does not upload inline', (tester) async {
  // The camera hands off and leaves. A capture must not hold the user
  // on a progress screen through a 25MB upload.
});

testWidgets('a photo generates a thumbnail before enqueueing', (tester) async {
  // 400px long edge, JPEG q75. thumbnail_key is NOT NULL server-side,
  // so a story without one cannot be finalized at all.
});
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

Pushes `CaptureCameraScreen(allow: CaptureKinds.photoAndVideo)`,
generates the thumbnail, enqueues, pops.

- [ ] **Step 4: Full verification**

```bash
flutter test test/features/stories
flutter test test/features/chat/streak_camera_contract_test.dart
flutter test test/features/chat
flutter analyze lib test
```
Expected: stories green; the streak harness unchanged; chat holds at its
19 known pre-existing failures; 0 analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/stories/presentation/screens/story_camera_screen.dart \
        test/features/stories/story_camera_test.dart
git commit -m "feat(stories): the story camera adapter"
```

---

## Plan B completion criteria

- [ ] A photo or video queued offline posts exactly once after
      connectivity returns, survives restart, and visibly fails if it
      cannot be posted.
- [ ] A retry after a dropped finalize response does NOT create a second
      story, verified against a mutant that mints a fresh id.
- [ ] Existing streak capture, replay preference, view budget and sounds
      pass the Task 1 harness unchanged.
- [ ] Streaks remain video-only; the photo path is stories-only.
- [ ] `flutter analyze` reports 0 errors.

**Not in this plan:** the rings, the reel, the calendar and replies are
Plan C. Nothing here is reachable from the app yet.
