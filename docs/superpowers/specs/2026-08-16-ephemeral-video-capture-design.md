# Ephemeral Video Capture — Design Spec (Video Sharing Part 2)

**Status:** Approved for planning
**Depends on:** Part 1, WhatsApp-style gallery-pick/trim/send video sharing (merged to `main`, commit `dd90d85b`) — this spec reuses its media pipeline, `ChatVideoPreparer`, and upload-intent infrastructure directly. Read `docs/superpowers/specs/2026-08-15-video-sharing-design.md` for that foundation; this spec does not re-derive it.

## 1. Summary

A press-and-hold, in-app camera capture that sends a short (≤10s) video message the receiver can view exactly once. The sender can also view their own sent clip, but only until the receiver views it — at that point the video is genuinely deleted (not just hidden) for both sides, and a "Video expired" tombstone remains in its place. Matches the user's own framing: "exactly like snapchat streak. You access camera tap and hold, release and send. then the receiver can view it once, the sender can also view it until the receiver views it then it disappears."

This is explicitly the second and final planned video feature. No further video-sharing work is anticipated after this ships.

## 2. Reused Infrastructure (from Part 1, unchanged)

- `message-media` Storage bucket, `create_chat_media_upload_intent` RPC, `validate_message_media_before_insert` trigger, server-authoritative `feature_flags` gating — all reused as-is.
- `ChatVideoPreparer` (`lib/features/chat/domain/services/chat_video_preparer.dart`) — reused directly, with two new optional parameters (Section 4).
- `video_player`, `video_compress`, `video_thumbnail` packages — already dependencies, reused as-is.
- The chat screen's existing Postgres-changes subscription on `messages` (`supabase_chat_repository.dart:481-505`), filtered by `relationship_id`, firing on all insert/update/delete — this is the delivery mechanism for revocation (Section 6) and screenshot notices (Section 8). No new realtime channel.
- `messages.media_type = 'video'` — reused as-is; no new media type value (Section 3).

## 3. Data Model

One new column:

```sql
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_view_once boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS viewed_at timestamptz;
```

`is_view_once = true` marks a message as ephemeral. `media_type` stays `'video'` — an ephemeral capture and a gallery-pick video are the same underlying media type with a different lifecycle flag, not a new type. This means every existing constraint, RPC branch, and trigger check that already handles `media_type = 'video'` continues to apply unchanged; only the new view/deletion RPC (Section 5) and the client's rendering branch (Section 7) are genuinely new.

`viewed_at IS NULL` is the single source of truth for "is this clip still viewable." Once set (by the RPC in Section 5, in the same statement that nulls the media keys), the clip is gone. There is no backup or soft-delete column: `media_url` and `media_thumbnail_url` are set to `NULL` and the underlying Storage objects are deleted in the same RPC call (Section 5). The row itself is never deleted — it remains as a permanent tombstone, so message ordering/history/counts stay intact. `content` stays empty (matching every other media message type); the client renders the tombstone purely from `is_view_once = true AND viewed_at IS NOT NULL AND media_url IS NULL`.

This is a genuine privacy guarantee, not client-side hiding: after `viewed_at` is set, the video and thumbnail no longer exist anywhere in Storage, recoverable by no one — not an admin, not a future bug, not a subpoena against the bucket.

## 4. `ChatVideoPreparer` Extension

`prepare()` gains two new optional parameters, both defaulting to Part 1's existing constants so every Part 1 call site is unaffected:

```dart
Future<PreparedChatVideo> prepare({
  required String localPath,
  Duration? trimStart,
  Duration? trimEnd,
  void Function(double)? onProgress,
  Duration? maxDuration,   // NEW — defaults to ChatVideoPreparer.maxDuration (3 min) if omitted
  int? maxBytes,           // NEW — defaults to ChatVideoPreparer.maxBytes (25MB) if omitted
})
```

The ephemeral capture flow calls `prepare()` with no `trimStart`/`trimEnd` (there is no trim step — the whole captured clip, already bounded to ≤10s by the recording UI itself, is what gets prepared) and passes:

- `maxDuration: Duration(seconds: 10)` — mirrors `ChatVideoPreparer.maxDuration`'s existing name/type, just a different value at the call site.
- `maxBytes: 2 * 1024 * 1024` (2MB) — proportional to Part 1's 800kbps target scaled to a 10-second clip (`800kbps × 10s ≈ 1MB` video, plus audio and container overhead → 2MB gives real headroom without abandoning Part 1's quality target).

The trim-window byte-estimate guard (`debugEstimateWindowBytes`) still runs internally when `trimStart`/`trimEnd` are omitted — it degrades to comparing the full source against the (now smaller) `maxBytes`/`maxDuration`, which is exactly the desired behavior: an oversized or unexpectedly-long capture file is still rejected before the expensive compress step, using the same guard-order Part 1 already established (existence → emptiness → absolute source-size guard → MIME sniff → probe → duration bounds → window-estimate guard → compress → post-compress size check → thumbnail). `ChatVideoRejected`'s existing error codes (`media_too_long`, `media_too_large`, etc.) are reused unchanged; the ephemeral flow's error-message mapping (Section 9) uses the same codes with capture-specific copy.

## 5. `mark_video_viewed` RPC — Atomic View-and-Delete

```sql
CREATE OR REPLACE FUNCTION public.mark_video_viewed(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_message public.messages%ROWTYPE;
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Atomic guard: only the FIRST call (from any device, sender or receiver)
  -- that finds viewed_at still NULL performs the real work. Every
  -- subsequent call — whether a genuine second view attempt, a retry
  -- after a network failure, or a race from two devices open
  -- simultaneously — is a safe no-op that returns normally, since the
  -- caller's intent ("make sure this is marked viewed and gone") is
  -- already satisfied.
  UPDATE public.messages
  SET viewed_at = now()
  WHERE id = p_message_id
    AND is_view_once = true
    AND viewed_at IS NULL
    AND media_url IS NOT NULL
    -- Only a relationship member may mark a message viewed — this is
    -- deliberately NOT restricted to "only the receiver," since the
    -- sender viewing their own clip does not consume it (Section 6), and
    -- the sender's client never calls this RPC for their own unviewed
    -- send. Restricting at the RPC layer to "any relationship member" is
    -- simpler and no less safe than trying to distinguish sender/receiver
    -- here, since the client-side access-gating logic (Section 7) is what
    -- actually decides when this RPC gets called.
    AND relationship_id IN (
      SELECT id FROM public.relationships
      WHERE status = 'active' AND (user_a = v_user_id OR user_b = v_user_id)
    )
  RETURNING * INTO v_message;

  IF v_message.id IS NULL THEN
    -- Either already viewed (safe no-op, matches header comment above) or
    -- the message doesn't exist / isn't view-once / caller isn't a member.
    -- No way to distinguish these from here without leaking existence —
    -- and the caller doesn't need to distinguish them: "not viewable
    -- anymore" is the only actionable outcome either way.
    RETURN;
  END IF;

  DELETE FROM storage.objects
  WHERE bucket_id = 'message-media'
    AND name IN (v_message.media_url, v_message.media_thumbnail_url);

  UPDATE public.messages
  SET media_url = NULL, media_thumbnail_url = NULL
  WHERE id = p_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_video_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_video_viewed(uuid) TO authenticated;
```

**Client contract:** the client calls `mark_video_viewed(messageId)` once, when full-screen playback completes (reaches the end) or the viewer explicitly dismisses the full-screen viewer mid-playback (both count as "viewed" — there is no partial-view distinction; Snapchat's own behavior is the same). The client retries this call on network failure (standard retry/backoff, no new infrastructure) until it succeeds — because the RPC is idempotent-safe by construction, a retry after a transient failure can never double-delete or mis-fire; it either performs the real deletion (if it's genuinely the first successful call) or safely no-ops (if an earlier attempt actually landed server-side despite the client not receiving a success response).

## 6. Revocation Delivery (No New Realtime Infrastructure)

`mark_video_viewed`'s two `UPDATE`s to the `messages` row (setting `viewed_at`, then nulling the media keys) fire through the chat's existing Postgres-changes subscription (`event: PostgresChangeEvent.all` on `messages`, filtered by `relationship_id` — `supabase_chat_repository.dart:481-491`), which every chat screen already listens to for ordinary message sync. No new channel, no new subscription setup.

**Concretely:** if the sender is actively viewing their own sent clip full-screen at the exact moment the receiver's `mark_video_viewed` call lands, the sender's client receives the same `events.add(null)` signal it already receives for any message change, triggers its normal re-fetch/hydrate cycle, sees `viewed_at IS NOT NULL` and `media_url IS NULL` on that message, and the full-screen viewer should close (or show an "expired" state) rather than continue playing already-revoked content. This is a UI-layer responsibility of the full-screen viewer widget (Section 7), not a new server mechanism.

**Offline sender:** if the sender's app is closed/offline when the receiver views the clip, nothing special happens server-side or client-side — the sender's client simply reflects the new (tombstoned) state whenever it next syncs, exactly like any other message the sender missed while offline. No push notification.

## 7. Client UX

### 7.1 Capture Entry Point

`ChatTextField` gains a third leading icon (alongside the existing Photo/Video attach icon), gated by its own feature flag (Section 10). Tapping it pushes a new full-screen route, `EphemeralCameraScreen` (`lib/features/chat/presentation/screens/`), mirroring `VideoTrimScreen`'s established "full-screen route via `Navigator.push`, not GoRouter" pattern from Part 1.

**Confirmed, explicit consequence of the symmetric design above:** because `mark_video_viewed` treats any relationship member's completed view identically (Section 5), and the sender's own full-screen viewing of their just-sent clip uses the exact same viewer screen and calls the exact same RPC on completion (Section 7.4), a sender who opens and fully watches their own sent clip revokes it for the receiver too — even if the receiver never opened it. This is intentional: full symmetry, no sender/receiver distinction anywhere in the RPC or client. A sender re-opening their own sent clip to check it will burn the receiver's only chance to view it, exactly as it would if the receiver had opened it first.

### 7.2 `EphemeralCameraScreen`

- Live camera preview via the new `camera` package dependency (first use of this package in the app — Part 1's `image_picker`/`video_player`/`video_compress`/`video_thumbnail` do not provide a live in-app viewfinder).
- Defaults to the front camera. A flip button switches between front/back **before** a recording starts; switching mid-recording is not supported (avoids a jarring exposure/resolution jump mid-clip).
- A large record button: press-and-hold starts recording (with audio), release stops and immediately sends — no preview/confirm step, true Snapchat parity, matching your explicit choice to accept the accidental-send risk this implies. A minimum hold duration (mirroring `VoiceRecorderService.minDuration`'s existing pattern) silently discards a hold shorter than the threshold rather than sending a near-zero-length clip.
- Recording auto-stops at 10 seconds (matching `maxDuration` passed to `ChatVideoPreparer.prepare()`, Section 4) if the user is still holding.
- A close button (no recording in progress) backs out with no send, same as declining to send anywhere else in the app.
- On release: the captured file is handed to `ChatVideoPreparer.prepare()` (no trim params, the 10s/2MB overrides from Section 4) behind the same `VideoPrepareProgressDialog` pattern Part 1 already built for the gallery flow (reused as-is, since it already takes a generic prepare-call). On success, `ChatController` sends the message with `is_view_once: true`. On `ChatVideoRejected`, the screen shows the error inline (not a snackbar after returning to the chat screen, since the user is still on the camera screen) and lets them try again — it does not silently return to the chat screen on failure the way a picker-cancel does, since a failed capture after actively recording is a different situation than backing out of a picker.

### 7.3 Sending: `ChatController.sendEphemeralVideoMessage`

A new method alongside `sendVideoMessage` (not a parameter on the existing one — the two have different validation, different `PendingSend` shape, and conflating them risks exactly the kind of accidental cross-contamination Part 1's plan was careful to avoid with `_attemptSend`'s branching). Mirrors `sendVideoMessage`'s structure (`canSend` check, user-null check, file-exists checks, duration-bounds check against the 10s cap, `PendingSend` construction, outbox write, optimistic `Message`, `_attemptSend` call) with one addition: the constructed `PendingSend`/`Message` carries `isViewOnce: true`, threaded through to `sendTextMessage`'s existing parameter list (widened with one new `bool isViewOnce = false` parameter, defaulting to `false` so every non-ephemeral call site is unaffected).

**Offline-outbox interaction:** an ephemeral message queued while offline behaves exactly like any other queued message until it successfully sends — `is_view_once`/`viewed_at` semantics only begin to matter once the row exists server-side. There is no tension with the offline-retry mechanism: a not-yet-sent ephemeral message has no "viewable until viewed" state yet, because it hasn't been delivered yet. This resolves the concern raised during scoping that ephemeral state might need new outbox tracking — it doesn't; the outbox's job ends at successful send, and everything ephemeral-specific happens after that point, server-side.

### 7.4 Bubble Rendering

`Message` gains `isViewOnce` (bool, persisted via `toJson`/`fromJson`, populated in `fromRow` from `is_view_once`) and `viewedAt` (`DateTime?`, same treatment, from `viewed_at`). A new getter:

```dart
bool get isEphemeralVideoAvailable =>
    isViewOnce && viewedAt == null && (localMediaPath != null || signedMediaUrl != null);
bool get isEphemeralVideoExpired =>
    isViewOnce && viewedAt != null;
```

`_BubbleBody` gains a new branch, checked **before** the existing `hasVideo` branch (an ephemeral video also has `mediaType == 'video'`, so ordering matters — `isViewOnce` messages must not fall into the gallery-video rendering path):

- `isEphemeralVideoAvailable` → renders a sealed/closed tile (not `VideoMessagePlayer`, not a poster thumbnail) — a fixed-size tile with a play icon and a "tap to view" affordance, no preview of the actual content, matching Snapchat's own closed-snap treatment. Symmetric for sender and receiver (Section 7.2 of the approved design: same widget regardless of `isMine`, gated only by whether `signedMediaUrl`/`localMediaPath` is currently non-null — which becomes null exactly when the sender's own clip is revoked, per Section 6, so the "can I currently see this" logic is already correctly encoded in the existing data, no new isMine-branching needed).
- `isEphemeralVideoExpired` → renders the tombstone: a small non-interactive row, "Video expired" with a closed/crossed-out icon (e.g. `Icons.videocam_off_outlined`), identical for both sender and receiver, no tap action.
- Tapping the sealed tile pushes a new full-screen route, `EphemeralVideoViewerScreen`, playing the video via `VideoPlayerController` (constructed fresh for this one-shot view — no lazy/eager distinction needed here since there's exactly one playback per screen instance, unlike `VideoMessagePlayer`'s list-reuse concern). On playback completion OR explicit dismissal, calls `mark_video_viewed` (Section 5) before popping the route. If the realtime revocation (Section 6) fires while this screen is open (a second device/second viewer beat this one to it), the screen should close itself with a brief "already viewed" indicator rather than continuing to show now-stale content — implemented via the same `ref.listen` pattern `VideoMessagePlayer`/`VoiceMessagePlayer` already use for cross-media coordination, listening here for a change to this specific message's `viewedAt`.

### 7.5 Screenshot Detection

Best-effort, both platforms, per your explicit choice to accept Android's unreliability rather than skip it:

- **iOS:** `UIApplication.userDidTakeScreenshotNotification` via a small platform channel (genuinely reliable — a real, documented system API). No screen-recording detection (not available via a comparably reliable API on either platform).
- **Android:** a `ContentObserver` on the device's screenshot media store path, best-effort — acknowledged as unreliable across OEMs/launchers and not surfaced to the user as a guarantee (no "screenshot protection is on" messaging anywhere in the UI; it either fires or it silently doesn't, same as it would silently not on iOS for screen recording).
- Both funnel through one Dart-side `ScreenshotDetectionService` (new, `lib/core/services/media/` alongside the existing `image_picker_service.dart`/`voice_recorder_service.dart`) exposing a single `Stream<void>` the ephemeral viewer screen listens to only while it's actively showing an ephemeral video (not globally — no reason to run detection outside that specific screen).
- On detection, the viewer screen inserts a system-style chat message ("`{sender}` took a screenshot") via the existing `sendTextMessage` path with a new lightweight `messageKind: 'system'`-style marker (or reuse of whatever system-message convention already exists in this codebase for non-user-authored rows — **verify against the actual current `messages` schema/rendering during planning**, since this spec does not assume one exists yet and the plan must check before inventing a new one). This message is authored as if from the viewer (the person who screenshotted), rides the same insert-then-realtime-notify path as any other message, and needs no new delivery mechanism per Section 6's reasoning.

## 8. Error Handling

| Failure | User-facing outcome |
|---|---|
| Camera permission denied | `EphemeralCameraScreen` shows a permission-rationale state (mirrors any existing permission-denial UI pattern in the app — check `VoiceRecorderService`'s established handling during planning) instead of a blank/crashed camera preview. |
| Hold shorter than minimum duration | Silently discarded, no error, no send — matches voice message's identical behavior. |
| `ChatVideoRejected` (any code) from `prepare()` | Inline error on `EphemeralCameraScreen` (not a snackbar after returning to chat), user can retry recording. |
| `mark_video_viewed` network failure | Client retries with backoff until success; the video remains playable locally (already downloaded/cached for this one playback) even if the "mark viewed" call hasn't landed yet — the viewer does not need to re-fetch to keep watching a clip it's already loaded, it only needs the RPC to eventually succeed so the *other* party's access gets revoked. |
| Sender revoked mid-view (Section 7.4) | Full-screen viewer closes with a brief "already viewed" message rather than continuing playback of stale content. |
| Screenshot detection platform-channel failure/unavailable | Silently no-ops — this is best-effort instrumentation, never a blocking failure path for the core capture/send/view flow. |

## 9. Explicitly Out of Scope

- Screen-recording detection (not reliably available on either platform without disproportionate platform-specific investment).
- Push notifications for revocation or screenshot events (both ride the existing in-app realtime/message pipeline only).
- Multi-recipient / group ephemeral sends (this app's chat model is 1:1 relationship-based; not applicable).
- Replaying, saving, or forwarding an ephemeral video before it's viewed (no such affordance is added anywhere in this spec — the sealed tile has exactly one action, tap-to-view-once).
- Any change to the gallery-pick video flow (Part 1) beyond the two new optional `prepare()` parameters (Section 4), which default to Part 1's exact existing behavior.

## 10. Feature Flag & Checklist Scope

New flag: `chat_ephemeral_video` (mirrors `chat_video_sharing`'s exact convention — default `false`, server-authoritative check in a new RPC path). Whether this needs its own paired-flag requirement (like `chat_video_sharing` requiring `chat_image_sharing`) is a planning-time question — **plan must check** whether ephemeral capture's upload intents flow through the same `create_chat_media_upload_intent` RPC as Part 1's video (in which case the existing `chat_video_sharing`-requires-`chat_image_sharing` pairing already applies and a third flag layering on top needs the same "AND" treatment applied to `chat_ephemeral_video`) or whether it's cleaner to give ephemeral video its own independent MIME/flag branch in that RPC.

Checklist scope: `[MOBILE][MUTATION]` — same as Part 1. No new scope tag; the existing `[MUTATION]` items (idempotency, race-safety) apply directly to `mark_video_viewed`'s atomic-guard design (Section 5), which is the one genuinely novel correctness-critical piece of state management in this feature.
