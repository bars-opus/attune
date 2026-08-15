# Voice Messages — Design Spec

**Date:** 2026-08-15
**Status:** Approved by user, pending written-spec review
**Scope:** Voice (audio) messages for Attune chat, press-and-hold recording with a live waveform, playback in the message bubble. Video sharing is an explicitly separate, later spec — the two features share only the underlying storage/upload-intent infrastructure.

## Goal

Let two people in a relationship send short voice messages to each other in chat, to the same quality bar as the existing image-sharing feature: real client-side compression, server-authoritative upload validation, outbox-backed offline retry, and a polished recording/playback UI matching what users expect from WhatsApp/iMessage/Telegram. Held to this repo's [Algorithm Quality Review Checklist](../../../lib/architecture/algorithms/algorithm_quality_review_checklist.md) (scope tags `[MOBILE][MUTATION][ASYNC]`).

## Why extend the existing image pipeline rather than build new infrastructure

Attune's image-sharing feature already has a complete, working, server-enforced media pipeline: a private `message-media` Storage bucket, an upload-intent RPC (`create_chat_media_upload_intent`) that mints a time-boxed, relationship-scoped signed upload key, a DB trigger (`validate_message_media_before_insert`) that rejects any insert not backed by a valid intent, server-side post-upload re-validation of size/MIME (the "hardening" migration), and a feature-flag gate enforced *in the RPC itself*, not just the UI. All of this generalizes cleanly across media types — the RLS policies key off intent ownership and relationship membership, not file content — so voice messages extend this pipeline's allowlists rather than duplicating its SQL/RLS logic. This keeps the new attack surface to "wider allowlist," which is far easier to reason about and review than a second, parallel bucket/RPC/RLS stack doing the same job.

## Recording UX

Press-and-hold the mic icon (trailing slot in `ChatTextField`, replacing the Send button when the composer is empty — the same slot WhatsApp/iMessage use). Releasing over the icon stops and sends. Dragging up/away past a threshold shows "slide to cancel" and releasing there discards the recording instead of sending. A live amplitude waveform replaces the text field while recording, so the user gets immediate visual feedback that audio is being captured.

- **Max duration: 5 minutes**, enforced by a `Timer` inside the recording service itself (not the widget layer), so the cap holds regardless of UI state.
- **Minimum duration: 500ms.** A press-and-release shorter than this is treated as an accidental tap — discarded silently, no message sent, no error shown.
- **Format: AAC/M4A, ~32kbps mono.** Voice-optimized bitrate; a full 5-minute recording is ~1.2MB. AAC needs no server-side transcoding for iOS/Android/web playback.
- **Waveform data is sampled live on-device during recording**, not computed server-side. The `record` package's amplitude stream is downsampled incrementally into a fixed-length array (~100 points, values 0–255) regardless of recording duration, so the waveform is ready the instant the message is composed — no "processing" wait before the shape appears, unlike image thumbnails.

## Data Model

**`Message` entity** (`lib/features/chat/domain/entities/message.dart`) gains two fields, additive and nullable — no change to existing rows or the image code path:
- `int? mediaDurationMs` — recording length in milliseconds. Always present when `mediaType == 'audio'`; null otherwise.
- `List<int>? waveform` — the ~100-point amplitude array described above. Null for non-audio messages.
- `bool get hasAudio => mediaType == 'audio' && (signedMediaUrl != null || localMediaPath != null)` — mirrors the existing `hasImage` getter exactly.
- `toJson`/`fromJson`/`copyWith` extended for both fields, following the same pattern as every other field on this class.

**Migration** (`supabase/migrations/20260815120000_chat_voice_messages.sql`):
- `ALTER TABLE messages ADD COLUMN media_duration_ms integer, ADD COLUMN media_waveform jsonb` — both nullable.
- Widen `validate_message_media_before_insert`'s check from `media_type = 'image'` to `media_type IN ('image', 'audio')`.
- Widen `create_chat_media_upload_intent`'s MIME allowlist to include `audio/mp4` / `audio/m4a`, alongside a size ceiling consistent with the ~1.2MB target (existing hardening-migration re-validation logic is extended to check this for `audio` the same way it already does for `image`).
- `INSERT INTO feature_flags (key, enabled) VALUES ('chat_voice_messages', false)` — same convention as `chat_image_sharing`; defaults off, flipped explicitly per-environment.
- Extend the existing flag-enforcement check inside `create_chat_media_upload_intent` (added in `20260705230000_chat_media_flag_enforcement.sql` for images) to also gate on `chat_voice_messages` when the requested `media_type = 'audio'` — server-authoritative, matching images: a stale or hostile client cannot bypass the flag by skipping the UI gate.

No new bucket. No new RLS policies. The existing intent-ownership and relationship-membership policies already cover any media type stored under an intent-issued key.

## Client Architecture

**`VoiceRecorderService`** (new: `lib/core/services/media/voice_recorder_service.dart`, sibling to the existing `ImagePickerService`) wraps the `record` package:
- `Future<bool> requestPermission()` — via the already-installed `permission_handler`.
- `Future<void> start()` — begins recording to a temp file (AAC/M4A, 32kbps mono) and starts consuming `record`'s amplitude stream, incrementally downsampling into the fixed-length waveform buffer.
- `Future<VoiceRecording> stop()` — returns `(localPath, durationMs, waveform)`. Internally cancels the max-duration timer and the amplitude subscription.
- `Future<void> cancel()` — stops recording and deletes the temp file (used by the slide-to-cancel gesture).
- Every finite resource (recorder handle, stream subscription, timer) is released in `stop()`, `cancel()`, and `dispose()` — no leak on any exit path, including an error mid-recording.
- Recording failures (mic busy, disk full, permission revoked mid-session) are caught and surfaced as a typed `VoiceRecordingException(code)`, mirroring `ChatImagePreparer`'s `ChatImageRejected(code)` pattern — never a raw platform exception reaching the UI or logs.

**`ChatTextField`** (`lib/features/chat/presentation/widgets/chat_text_field.dart`) — the trailing send button becomes state-driven: it currently renders `IconButton.filled(icon: Icons.send_rounded)` unconditionally (disabled, not hidden, when there's no text). This changes to: mic icon when `!_hasText`, send icon when `_hasText`, gated overall by a new `showVoiceMessage` flag (mirroring `showAttachImage`'s existing gating pattern) so the feature stays fully inert when the flag is off. The mic icon is wrapped in a `GestureDetector` with `onLongPressStart`/`onLongPressMoveUpdate`/`onLongPressEnd` driving start/cancel/stop-and-send. While recording, the composer's text field area is replaced by the live waveform view.

**Sending** — `ChatController.sendVoiceMessage(localPath, durationMs, waveform)` mirrors `sendImageMessage`'s exact shape: builds an optimistic `Message` (playable immediately from `localMediaPath`, shown with a "sending" indicator), writes it to the same outbox cache `sendImageMessage` uses, and flushes through the existing retry path — no new retry/offline mechanism. On flush: the existing `createImageUploadIntent`/`uploadChatImage` repository methods are generalized to `createMediaUploadIntent(relationshipId, mimeType, mediaType)` / `uploadChatMedia(intent, localPath, mimeType)` (a parameter-widening rename, not a new method — `ChatMediaUploadIntent` is already media-type-agnostic: `intentId`/`storageKey`/`expiresAt`/`bucket`, no image-specific fields), then `sendTextMessage(..., mediaKey:, mediaType: 'audio')` inserts the row, now also carrying `mediaDurationMs`/`waveform`.

**Playback** — new `VoiceMessagePlayer` widget inside `MessageBubble`'s `_BubbleBody`, backed by the already-installed `audioplayers`. A single app-wide `StateProvider<String?>` (currently-playing message id, not scoped per-conversation) enforces one-at-a-time playback: starting playback on any bubble first stops whatever the provider currently points to, and leaving the chat screen while a voice message is playing stops it (via the provider's own dispose/screen-lifecycle hook) rather than letting it keep playing in the background — matching "explicitly out of scope: playing from a locked screen or notification" above, i.e. voice message playback only ever happens while its message list is on-screen. The waveform renders from `message.waveform` with a progress sweep driven by `audioplayers`' position stream; tapping anywhere on the waveform seeks to that proportional position.

## Error Handling & Checklist Mapping

| Failure | Behavior |
|---|---|
| Mic permission denied | Actionable message ("Attune needs microphone access to send voice messages") with a button to `openAppSettings()`. Never a silent no-op, never a raw platform error string (checklist 5.1, 5.5). |
| Recording fails mid-capture | Temp file discarded, composer returns to idle state, transient error toast. Never a stuck "recording" UI. Typed `VoiceRecordingException(code)`, not a raw exception (4.4/4.5 — no leaked internals in logs or UI). |
| Press-and-release under 500ms | Discarded silently — not an error, just a no-op (matches WhatsApp/iMessage). |
| Upload fails after send | Identical to the existing image outbox/retry path: optimistic bubble stays visible, automatic retry on reconnect, manual retry affordance after exhausted attempts, no duplicate on retry (1.10, 2.18, 6.4). |
| Compromised/stale client bypasses UI flag or MIME check | Server-side: `create_chat_media_upload_intent` still enforces the `chat_voice_messages` flag and MIME/size allowlist; `validate_message_media_before_insert` still rejects any insert not backed by a valid intent (1.4 — authorization at every access point, inherited unchanged from the image pipeline). |

**Checklist scope:** `[MOBILE][MUTATION][ASYNC]` (client capture/recording is mobile; sending is a mutation; outbox flush is async).

- **P0-U** — input validation both client-side (duration cap, ~1.2MB target size) and server-side (trigger + hardening re-check), never client-trust-only. No secrets involved. Authorization/authentication inherited from the existing intent-based flow.
- **P1** — 1.1/2.18 idempotency via the outbox's existing `clientMessageId` dedup (no new mechanism). 2.10 resource cleanup — recorder/stream/timer released on every exit path. 2.13 cleanup on cancellation — slide-to-cancel and app-backgrounded-mid-recording both discard cleanly, no orphaned temp files or dangling recorder handles.
- **P2** — 1.3 graceful degradation is the table above, not "won't happen." 4.11 configurable thresholds — max duration, bitrate, waveform point count, min-duration-to-send are named constants, not scattered magic numbers.
- **Explicitly out of scope for v1** (documented, not silently skipped): 6.10 soak test and 6.11 load test at the Storage/RPC infrastructure layer — this reuses already-soak-tested infra from image sharing; new soak/load testing is scoped to the delta (the widened trigger/RPC paths for `audio`), not a full 24h re-run against unchanged image infra.

## Explicitly Out of Scope (this spec)

- Video sharing — separate spec, to follow.
- Server-side waveform computation or reprocessing (the async `message_media_processing_outbox` pattern used for image thumbnails is not used here — waveform is captured client-side at record time and never recomputed).
- Voice message transcription / speech-to-text.
- Multi-message batch/queue recording (record → send → immediately record another without returning to the idle composer).
- Playing voice messages from a locked screen or notification.

## Testing Evidence Plan

- Unit tests for `VoiceRecorderService`: start/stop/cancel resource cleanup (assert no leaked subscriptions/timers across repeated start/stop cycles), max-duration auto-stop, waveform downsampling produces a fixed-length array regardless of input sample count, min-duration discard.
- Widget tests for `ChatTextField`'s mic/send swap and the press/drag/release gesture states (record start, slide-to-cancel threshold, stop-and-send).
- Widget tests for `VoiceMessagePlayer`: single-playback-at-a-time enforcement across two bubbles, tap-to-seek, play/pause icon state.
- Repository tests for the generalized `createMediaUploadIntent`/`uploadChatMedia` covering both `image` and `audio` mediaType values (regression guard that the image path is unaffected by the generalization).
- Migration test/manual verification: insert attempt with `media_type = 'audio'` and no valid intent is rejected by the trigger; insert with a valid intent but `chat_voice_messages` flag off is rejected by the RPC.
