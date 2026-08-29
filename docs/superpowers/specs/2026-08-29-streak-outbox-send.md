# Streak Send Through the Outbox — Design

**Date:** 2026-08-29
**Status:** Approved, ready for implementation
**Spec reference:** `CHAT_SYSTEM_SPEC.md` §4.2, §7.2 (send queue, retry)

## Problem

A streak sends synchronously from the camera. `sendStreak` uploads,
inserts the message row, inserts the clip row, and only then pops the
screen — so the user watches a progress ring through a 25MB upload before
they can do anything else.

Three consequences:

1. **The camera holds the user hostage.** Every other media type in chat
   sends optimistically: the bubble appears immediately and the upload
   happens behind it.
2. **A failure has nowhere to go.** The outbox owns retry, backoff and
   recovery after a dropped connection. A streak that fails mid-upload is
   simply lost, with a snackbar.
3. **It is a second send path.** `sendVoiceMessage`, `sendImageMessage`
   and `sendEphemeralVideoMessage` all queue through `PendingSend`;
   `sendStreak` does not. Two paths mean two things to keep correct.

## What makes streaks different

The original design queued up to five clips per streak, which is what
made the outbox a poor fit: `PendingSend` carries exactly one
`localMediaPath`, and widening it to a list would reshape the retry
machinery every message type depends on.

**That constraint is gone.** Streaks are now a single clip of at most
sixty seconds. A streak is therefore an ephemeral video with one extra
field — its view budget — and the outbox already carries
`isViewOnce` for precisely this shape of message.

## Design

### `PendingSend` gains one field

```dart
/// Views the recipient gets. Null for every message type but a streak.
final int? streakViewsRemaining;
```

Null rather than defaulting to 1: a null budget on a non-streak is
meaningless, and a default would quietly make every video a one-view
message if the media type were ever mis-set.

### `sendMessage` gains one parameter

`streak_views_remaining` joins the insert map, passed through from the
pending row. The column already exists and already has its grant.

### `sendStreakMessage` on the controller

Mirrors `sendEphemeralVideoMessage` exactly:

1. guard `canSend`, resolve the user
2. verify the file exists and is within duration bounds
3. build a `PendingSend` with `mediaType: 'streak'` and the budget
4. `putOutbox`, then an optimistic `Message` into state
5. `_attemptSend(pending)` — which uploads, inserts, reconciles and
   retries on failure, all of it already written

The camera's job ends at "here is a file": it pops immediately.

### The bubble carries the sending state

`StreakBubble` gains `isSending`. An optimistic streak renders a small
spinner with **"Sending…"** in place of the play affordance — the same
information the camera's ring gave, in the place the user is now looking.

A failed send falls through to the existing failed-message treatment
(retry affordance, error styling) rather than needing its own.

## What this does NOT change

- **The view rules.** `mark_streak_viewed` and the sender/recipient
  budget logic are untouched.
- **`streak_clips`.** The table stays. `_attemptSend` inserts the clip
  row after the message row lands, using the storage key it already
  resolved for the upload.
- **The camera UI.** The record button, ring, preview and review sheet
  all stay. Only what happens after "Send" moves.

## Risk

`_attemptSend` is shared by every message type. The streak branch must be
additive — a new `if (pending.mediaType == 'streak')` after the existing
media upload — and must not alter the paths text, image, audio, video and
ephemeral video take. The regression surface is the whole chat send path,
so `chat_system_contracts` and the existing send tests are the gate.

## Testing

| Layer | Coverage |
|---|---|
| Flutter unit | a streak pending row round-trips through the cache with its budget |
| Flutter unit | `sendStreakMessage` queues an optimistic message and returns before the upload completes |
| Flutter widget | an optimistic streak bubble shows "Sending…", not a play affordance |
| Flutter widget | a sent streak bubble shows the play affordance |
| Flutter unit | a non-streak pending row carries a null budget |
| SQL contract | `streak_views_remaining` survives the insert path unchanged |
