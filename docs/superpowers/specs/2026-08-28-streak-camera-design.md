# Streak Camera — Design

**Date:** 2026-08-28
**Status:** Approved, ready for implementation planning
**Spec reference:** `ATTUNE_MASTER_SPEC.md` §11 (Permanent Constraints),
`CHAT_SYSTEM_SPEC.md` §5 (media)

## Problem

Attune has an ephemeral camera: hold to record, one clip, ten seconds,
strict view-once, sent immediately on release. What is wanted is a
Snapchat-style **streak**: hold to record for as long as you like, with
the recording auto-splitting into segments, a review step before
sending, captions, and a batch sent as one message.

These are different features, not a tuning of the existing one. The
current screen has no queue, no review step, no captions, no replay
budget, and no segmentation.

Two bugs in the existing camera were fixed separately (commit
`6db5763d`) and are not part of this design: a stretched preview, and a
2MB output ceiling below what the encoder can produce.

## Research: what Snapchat actually does

Verified rather than assumed, because "exactly like Snapchat" was the
brief:

- **Multi Snap splits at 10 seconds**, up to 6 segments (60s total).
  Thumbnails appear above the capture button after each segment, and
  individual clips can be deleted before sending.
- **Replays: one per snap** for standard accounts — two total views.
  "One Time Only" (no replay) is a paid setting.
- The **streak counter** is a separate mechanic: a fire emoji after
  three consecutive days of mutual snap exchange, on a rolling 24-hour
  window keyed on send time, not open time.

This design deliberately diverges on two points, both product calls:

| | Snapchat | Attune |
|---|---|---|
| Split threshold | 10s | **60s** |
| Segment cap | 6 (hard stop at 60s) | **5 (hard stop at 5 min)** |
| Replays | 1 by default | **0 by default, opt-in up to 3** |

Longer segments suit a couples app: a partner talking for a minute is
the unit of value, where Snapchat optimises for a rapid highlight reel.
The stricter replay default follows §11's privacy posture — ephemerality
is the default and the sender opts out of it, never the reverse.

**The daily streak counter is out of scope.** This design covers the
camera and send flow only.

## Non-Goals

- **The streak day counter.** No flame, no consecutive-day tracking, no
  24-hour window. Its own feature.
- **Changing the existing ephemeral video.** `is_view_once` behaviour
  stays exactly as shipped; streaks are a new media type alongside it.
- **Per-clip deletion before send.** Snapchat allows it; this version
  sends the whole queue or discards it. Deferred rather than rejected —
  see Open Questions.

## The recording state machine

```
idle ──press──> recording(segment 1)
                    │
                    ├── release ────────> review
                    ├── 60s elapsed ────> recording(segment n+1)   [previews appear]
                    └── 5 segments ─────> review (recording stops)
review ──send──> queued as one message
       └─discard─> idle, all files deleted
```

**Under 60 seconds there is no split and no previews.** A single clip
behaves exactly like today's camera plus a review step. Thumbnails only
appear once a second segment exists — a lone thumbnail for a lone clip
is noise.

**At the 5-segment cap recording stops** and the review step opens with
everything captured. The alternative — a rolling window dropping the
oldest clip — silently discards what the user recorded with no way to
explain it in the UI.

### The progress ring

A circular progress indicator drawn **around the record button**,
filling over the 60-second segment duration. It completes and resets at
each split, so a full sweep is the visual signal that a segment just
closed. Paired with a haptic tick at each split, since the user is
looking at the subject rather than the button.

### Review step

On release, a caption bar appears below the preview: a text field and a
send button. The clips are already captured; this step exists so the
user can add a caption or back out. Discarding deletes every staged
file — a recorded-but-unsent streak must leave nothing behind.

## Captions

Captions are **view-time only**. They never appear in the chat row, and
the conversations-list preview says "Streak" with no caption text, the
way a view-once message reveals nothing before opening.

While viewing, the caption renders as a `Stack` overlay near the bottom
of the clip. One caption per streak, not per clip: the queue is one
message and one thought.

## Replays

Strict view-once by default. The sender may toggle **"allow replays"**
before sending, which grants the recipient up to **3 total views**.

This inverts the existing ephemeral video's storage model and is the
subtlest part of the design. `mark_video_viewed` currently **deletes the
storage object** on first view — correct for strict view-once, fatal for
a replay budget. So:

- `streak_views_remaining` (int, default 1) is decremented per view
- the storage object is deleted only when it reaches **0**
- the existing `mark_video_viewed` path is untouched; streaks get their
  own `mark_streak_viewed` RPC

A replay budget therefore means the media survives longer on the server
than a view-once clip does. That is a real privacy difference and the
reason it is opt-in and capped rather than default.

## Data model

One message, several clips. `messages` gains nothing; a new table holds
the segments:

```sql
CREATE TABLE public.streak_clips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  clip_index int NOT NULL,
  media_url text NOT NULL,
  media_thumbnail_url text,
  duration_ms int NOT NULL,
  width int,
  height int,
  UNIQUE (message_id, clip_index)
);
```

`messages.media_type` gains `'streak'`, which requires widening
`messages_media_type_check` — the same constraint that silently blocked
voice notes until commit `5c23cfc8`. The upload-intents table's own
constraint must be widened in the same migration, since drift between
those two is exactly what made that bug so hard to find.

Playback is sequential: clip 1 → 2 → 3, then the view is spent.

## §11 and privacy

- The chat row and the conversations preview reveal **nothing** — no
  caption, no thumbnail, no clip count beyond "Streak".
- A discarded review deletes every staged file.
- Replays are opt-in, capped at 3, and extend server retention only for
  as long as views remain.
- Screenshot detection is **not** in scope and must not be implied in
  the UI: promising it and not delivering it is worse than its absence.

## Testing

| Layer | Coverage |
|---|---|
| Flutter unit | the state machine: split at 60s, no split under it, stop at 5 segments, release mid-segment keeps the partial clip |
| Flutter unit | a release during the async start does not orphan a recording (the bug fixed in `511f4665` — same shape) |
| Flutter unit | a partial final segment is kept, and the 500ms minimum applies only to the first |
| Flutter unit | every segment records with audio enabled |
| Flutter widget | no previews under one segment; previews appear from the second |
| Flutter widget | the progress ring resets at each split |
| Flutter widget | discarding the review deletes every staged file |
| Flutter widget | the caption never renders in the chat row, only in the viewer |
| SQL contract | `streak_clips` cascades when its message is deleted |
| SQL contract | views decrement, and storage is deleted only at zero |
| SQL contract | a non-member cannot read another couple's streak clips |
| SQL contract | `messages_media_type_check` and the intents constraint both accept `'streak'` and stay in step |

## Resolved decisions

These were the spec's open questions; all three are now settled.

### No per-clip deletion in review

Snapchat allows removing individual segments before sending. This
version sends the whole queue or discards it.

Deferred rather than rejected: it complicates both the review UI and the
queue model, and the core flow should be proven first. Worth revisiting
once people are actually recording multi-segment streaks — if nobody
records more than two clips, per-clip deletion solves a problem that
does not exist.

### A partial final segment is kept

Releasing at 1m20s leaves a second clip of twenty seconds. It is sent.

It is what the user recorded, and silently dropping it would lose
content they watched themselves capture. The alternative — discarding
anything under some minimum — would make the last thing said disappear
for no reason the user could see.

The existing 500ms minimum still applies to the FIRST segment, since a
stray tap should not send an empty streak.

### Segments record audio

The same as the existing ephemeral camera (`enableAudio: true`). A
streak is someone talking to their partner, so a muted visual-only
format would remove most of what makes it worth sending.

This means each segment carries an audio track through the transcode,
which counts against the per-clip size ceiling — sized accordingly in
the plan rather than assumed away.

## Open questions

None outstanding. The three that were open — per-clip deletion, partial
final segments, and audio — are resolved above.
