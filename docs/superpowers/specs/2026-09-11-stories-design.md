# Stories — Design

**Status:** proposed, not implemented
**Date:** 2026-09-11

## 1. What this is

A Snapchat-style stories feature with an audience of exactly one: your
partner. You post a photo or short video, it sits in a reel for 24
hours, and then it leaves the reel — but stays in the couple's calendar
forever, on the date it was posted.

The point is not the reel. Attune already has a chat; a way to broadcast
to one person you can already message is not, by itself, a feature. The
point is that **the calendar fills itself up**. Today `timeline_events`
only gains a row when someone deliberately logs a moment, which is work,
so most days are empty. Stories make a shared record accumulate as a
by-product of something people already enjoy doing. Post without
thinking; keep without effort.

That framing decides most of what follows. The 24-hour expiry is not a
limitation to work around — it is what keeps posting cheap. The
permanence is not a nice extra — it is the reason the feature exists.

## 2. Decisions, and what they rule out

| Decision | Consequence |
|---|---|
| Audience is the partner, always | No privacy picker, no close-friends list, no audience UI at all |
| Stories live in their own table | The calendar merges them at read time; nothing is copied |
| Expiry hides, never deletes | `expires_at` gates the reel query only |
| Deleting a story removes it from the calendar too | One row, one `deleted_at`; no cleanup logic to get wrong |
| Only the author may delete | Enforced in a SECURITY DEFINER RPC; clients get no DELETE grant (§3.3) |
| Clients get SELECT only | Every write goes through an RPC that owns the server-side fields (§3.3) |
| Retention is forever unless the author deletes | No sweep job, no expiry of the calendar copy |
| No posting limit | A couple may post as much as they like |
| No chat trail when a story is posted | See §7 |

## 3. Data model

Three decisions are load-bearing here, so they are stated with reasons.

### 3.1 Stories are their own table

`timeline_events` carries a `CHECK` constraint on five event types
(`milestone`, `conflict`, `highlight`, `first`, `anniversary`) and has
no media columns. Making stories a sixth type would mean widening that
constraint and adding media columns that only one type ever uses — and
every existing consumer of `timeline_events` would start receiving rows
shaped differently from the ones it was written against.

Stories therefore keep their own table, and the calendar screen merges
them in at read time. This is not a new pattern: the timeline screen
already merges reminders, which are also not `timeline_events`.

A second benefit falls out of this. Because the reel and the calendar
read the SAME row, "deleting a story removes it from the calendar" needs
no code at all. The alternative — writing a `timeline_events` copy on
post — would need a two-row delete that could half-fail, and would turn
a day's six photos into six calendar entries.

```sql
CREATE TABLE public.story_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  author_id         uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,

  media_type        text NOT NULL CHECK (media_type IN ('image', 'video')),

  -- KEYS, not URLs. The bucket is private and reads mint a signed URL
  -- per request (§4.1). A stored URL would either expire in the row or
  -- imply a public object.
  media_key         text NOT NULL,

  -- NOT NULL: the rings have nothing to draw without it, so a story is
  -- not finalized until its thumbnail exists (§4.3).
  thumbnail_key     text NOT NULL,

  media_width       int CHECK (media_width IS NULL OR media_width > 0),
  media_height      int CHECK (media_height IS NULL OR media_height > 0),

  -- Present for video, absent for image.
  duration_ms       int,
  CONSTRAINT story_duration_matches_type CHECK (
    (media_type = 'video' AND duration_ms IS NOT NULL AND duration_ms > 0)
    OR (media_type = 'image' AND duration_ms IS NULL)
  ),

  -- The date the calendar groups by. Frozen at creation from the
  -- poster's civil date -- see §3.5. A stored date beats every reader
  -- re-deriving one from created_at and disagreeing across timezones.
  occurred_on       date NOT NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Gates the reel, and nothing else. Set server-side at insert.
  expires_at        timestamptz NOT NULL,

  -- Soft delete. Hides the item from the reel AND the calendar at once,
  -- because both read this row.
  deleted_at        timestamptz,

  -- Null until the downscale job has run. NOT sufficient as the job's
  -- idempotency mechanism on its own -- see §4.4.
  downscaled_at     timestamptz,

  CONSTRAINT story_expires_after_creation CHECK (expires_at > created_at)
);

CREATE INDEX idx_story_reel
  ON public.story_items (relationship_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_story_calendar
  ON public.story_items (relationship_id, occurred_on DESC)
  WHERE deleted_at IS NULL;

CREATE TABLE public.story_views (
  story_item_id uuid NOT NULL REFERENCES public.story_items(id)
                  ON DELETE CASCADE,
  viewer_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_item_id, viewer_id)
);
```

### 3.2 Expiry hides; it never deletes

`expires_at` is written by the server at insert and is read by exactly
one query: the reel's. Nothing deletes a row when it passes.

This is deliberately structural rather than a job. A story leaves the
reel the instant the clock passes it, whether or not any scheduled task
ran — and a job that failed to run can never take the calendar's copy
with it.

### 3.3 Security contract: read-only RLS, everything else through RPCs

The first draft said "RLS follows `timeline_events` exactly." That is
wrong for mutations, and the reason is worth stating because it is easy
to repeat.

The timeline policies are:

```
UPDATE  USING (auth.uid() = logged_by)  WITH CHECK (auth.uid() = logged_by)
DELETE  USING (auth.uid() = logged_by)
```

Authorship and nothing else. No column restriction, no re-check of
relationship membership. For a timeline event — a title, a note, a mood
score, all author-owned — that is fine. For a story it is not, because
these columns are **server-owned**:

- `expires_at` — an author could extend their story indefinitely
- `occurred_on` — could be moved to any date in the calendar
- `media_key` — could be repointed at another object
- `relationship_id` — could move a story to a different couple
- `downscaled_at` — could suppress the job

And a direct `DELETE` would bypass the soft-delete contract entirely,
removing the row while its storage object is never enqueued.

**So the grants are:**

| Table | authenticated may |
|---|---|
| `story_items` | `SELECT` only, scoped to relationship members with `deleted_at IS NULL` |
| `story_views` | nothing directly — see §3.4 |

Everything that writes goes through a `SECURITY DEFINER` RPC:

- **`create_story_item`** — derives `author_id` from `auth.uid()`,
  validates ACTIVE relationship membership, consumes a matching upload
  intent, and sets `created_at`, `expires_at` and `occurred_on` itself.
  The client cannot supply any of them.
- **`delete_story_item`** — verifies authorship, stamps `deleted_at`,
  and enqueues every associated object (media, thumbnail, and any
  superseded rendition) in the SAME transaction, so a tombstone can
  never exist without its cleanup work.
- **`mark_story_viewed`** — see §3.4.

No `UPDATE` grant exists at all. There is no story field a client has
any business changing after the fact.

### 3.5 `occurred_on`: the poster's civil date, no cutoff

"Server-side" does not explain how the server learns the poster's local
date, and the first draft's "01:00 belongs to the night before"
smuggled in a day cutoff that was never defined.

**Decision: `create_story_item` takes `p_utc_offset_minutes`, and
`occurred_on` is the poster's civil date at `now()` — midnight to
midnight, no cutoff.**

The offset is validated to `[-840, 840]` and clamped, following the
precedent already in the repo: the streak RPC accepts
`p_utc_offset_minutes` the same way. It is advisory, not trusted — the
worst a wrong offset does is file a story one day off in its own
couple's calendar.

The night-before idea is dropped rather than left vague. A cutoff needs
a defensible hour, would differ per couple, and buys little: a story
posted at 01:00 appearing on the new day is what every calendar app
already does, so it will not surprise anyone.

### 3.4 `story_views`: derived status, not a readable table

With an audience of one, *who* viewed is not a disclosure — there is
only one other person. The real surface is the exact `viewed_at`
timestamp, which says when your partner was awake and looking at their
phone. The product promises seen / not-seen, so that is all the client
gets.

`story_views` is therefore **not readable by clients**. Story queries
return derived booleans instead:

- `viewed_by_me` — drives the ring's bright/faded state
- `viewed_by_partner` — drives "seen" on the author's own reel

`mark_story_viewed` is a `SECURITY DEFINER` RPC that derives the viewer
from `auth.uid()` and refuses unless all of these hold:

- the caller belongs to the story's relationship
- **the caller is not the author** — otherwise reviewing your own reel
  marks your own story seen, and the author's "seen" indicator becomes
  meaningless
- the story is not deleted

It uses `ON CONFLICT DO NOTHING`, so the first view is the recorded one
and re-watching does not move the timestamp.

**Expired stories viewed from the calendar do not record a view.** The
view state answers "has my partner seen what I posted today"; a view
recorded eight months later would silently flip a long-settled
indicator.

## 4. Storage and media lifecycle

```
capture ─► intent ─► upload ─► finalize ─► in the reel (24h) ─► leaves reel
                                   │                               │
                            (never finalized)              (downscale job)
                                   │                               │
                            cleanup job                            ▼
                                                        in the calendar, forever
                                                                   │
                                              author deletes ─► tombstone + enqueue
```

### 4.1 Keys, not URLs

The bucket `story-media` is **private**, and the table stores
**`media_key` / `thumbnail_key`**, never durable URLs. Reads mint a
signed URL per request, with the same 600-second TTL chat already uses
(`_signedUrlTtl`).

Storage SELECT is authorized by a policy requiring that the key belong
to a `story_items` row that is `deleted_at IS NULL` and whose
relationship contains the caller. Deletion therefore stops *new* reads
immediately; see §4.5 for the window on already-issued URLs.

### 4.2 Upload is intent → upload → finalize

`create_story_upload_intent` returns an intent id, a storage key, a
bucket and an expiry. It does **not** mint a signed upload URL — the
client uploads normally and Storage RLS authorizes it. (The first draft
said "signed upload URL"; `create_chat_media_upload_intent` does no
signing, and the story version follows the same shape.)

`create_story_item` then finalizes: it consumes the intent, validates
the object's MIME type and size against the intent, and writes the row.

**The failure mode this creates** is the opposite of an orphaned row: an
object uploaded but never finalized. Chat already solves this with
`cleanup_expired_chat_media_intents()`; stories get the equivalent, and
the risk table says so rather than claiming the two-step flow is free.

### 4.3 Thumbnails are required, and generated by the client

The rings show the newest item's thumbnail, so a story without one has
nothing to render. `thumbnail_key` is therefore **NOT NULL**.

The client generates it before finalizing and uploads it under its own
intent: for a video, a frame grab; for an image, a downscaled rendition.
Both target **400px on the long edge, JPEG, quality 75** — the same
numbers `process-chat-media` already uses for chat thumbnails. Loading a
full original inside a 64px circle would be wasteful on both bandwidth
and memory.

A story becomes visible only when finalization succeeds, which means it
never appears without its thumbnail.

### 4.4 Downscaling needs a video runtime, which does not exist yet

`process-chat-media` uses Supabase Storage's **image** transform. It is
not a transcoder, and no video-processing runtime exists in this
project. "Cron → edge function re-encodes video" named a capability we
do not have.

**Decision: images are downscaled at 24h; video is not, in v1.**

- **Images**: the existing transform handles this — 1600px long edge,
  quality 80.
- **Video**: keeps its original rendition. Video is already capped at
  60 seconds and 25MB by `ChatVideoPreparer`, so the unbounded growth
  the downscale job was protecting against is already bounded at the
  point of capture.

Choosing a transcoding runtime is real work with its own operational
surface, and it is not on this feature's critical path. Deferring it is
stated here rather than discovered when the job is written.

The image job therefore needs, and gets: a claim/lease so two runs
cannot process the same row, deterministic output keys, and this
ordering — **create the new rendition, then conditionally swap the key,
then enqueue the old one for deletion**. `downscaled_at` alone is not
idempotency if the worker dies between upload and update; the lease plus
deterministic keys is.

The old rendition's deletion is delayed by at least the signed-URL TTL
(§4.1), or a player holding a fresh URL breaks mid-playback.

### 4.5 Deletion

`delete_story_item` stamps `deleted_at` and enqueues every object —
media, thumbnail, and any superseded rendition — in one transaction.

Deferring the physical delete is safe because the bucket is private and
its SELECT policy requires a live story row: new requests fail
immediately. What survives is any signed URL already issued, for up to
its 600-second TTL. That is the accepted window, and it is bounded by
the TTL rather than by the queue's latency.

The queue retries with backoff and dead-letters after exhausting them;
a dead-lettered object is a cost and monitoring concern, never a
correctness one, because the row is already invisible.

Relationship deletion cascades (`ON DELETE CASCADE`), and the same
enqueue runs for every story in it.

## 5. Surfaces

### 5.1 The rings row

A row at the top of the conversations screen, above the conversation
tile. Two rings, never more, because the audience is one person.

|  | Empty | Has stories |
|---|---|---|
| **Mine** | Empty ring, `+` in the middle | Newest item's thumbnail fills the circle, `+` badge at the bottom-right |
| **Partner's** | Renders nothing at all | Newest item's thumbnail, ring around it |

The ring is segmented — one arc per item — and bright for unviewed,
faded once seen.

Two details that differ from Snapchat and are chosen, not inherited:

- **The circle is a thumbnail, never an avatar.** With an audience of
  one, a face tells you nothing you do not already know. The last frame
  tells you what is new.
- **It is not the conversation tile's avatar.** That is a couple's group
  avatar; ringing it would be ambiguous about whose story it is, and
  would need image processing to do well.

An empty partner ring renders nothing rather than a placeholder. A
placeholder reads as "they have something" and makes the row feel like a
prompt to check on someone.

### 5.2 The reel — a new module

Segmented progress bars across the top, tap right for next, tap left for
back, hold to pause, swipe down to dismiss. Images hold for 5 seconds;
videos run their length.

**The streak viewer provides almost none of this, and stays unchanged.**
It is a single-item video player whose only gesture is
`onTap: () => _finish()` — no segments, no navigation, no pause, no
dismissal gesture, no image branch. Turning it into the story reel would
put a shipped feature's viewer at risk for no gain.

| Reusable from the streak viewer | New in the reel |
|---|---|
| Signed-media loading and its two open states | Reel controller and item sequencing |
| `VideoPlayerController` setup and disposal | Segmented progress bars |
| Black-field presentation | Tap-left / tap-right / hold-to-pause / swipe-down |
| | Image rendering and its 5-second timer |
| | Lifecycle pause/resume (backgrounding mid-item) |
| | Next-item preloading |

The reel is therefore a new screen that borrows two patterns, not an
adaptation of an existing one.

Viewing an item writes a `story_views` row. The poster's own reel shows
whether each item has been seen.

### 5.3 The calendar

The timeline screen gains stories as a third source beside events and
reminders. A date with stories shows a row saying how many; tapping it
opens that day's reel, expired items included.

This is where deletion-from-the-past lives, and it is author-only.

### 5.4 Replying needs a column on `messages`

Replies today reference another **message**: `reply_to_message_id` and
`quoted_text`. There is no way to quote a story, so this is not
implementable without a schema change.

**Decision: `messages` gains `story_item_id uuid NULL REFERENCES
story_items(id) ON DELETE SET NULL`, plus a snapshot of the thumbnail
key.**

- **A snapshot, not a live reference.** The reply must still read
  sensibly after the story is deleted or expired — a quote that empties
  itself later rewrites history in the conversation.
- **`ON DELETE SET NULL`**, so a deleted story leaves the reply intact
  with its snapshot, and the tap-through simply stops working.
- **Tapping the quote** opens the story if it is still live; if it is
  deleted, the reply says so rather than opening an empty reel. An
  expired-but-kept story opens from the calendar as normal.
- **The RPC validates** that the story's `relationship_id` matches the
  message's, so a reply can never quote another couple's story.

## 6. The camera: extract, do not branch

`streak_camera_screen.dart` is 760 lines, and its *capture* half —
permissions, camera switching, segment recording, the ticker, transcode
through `ChatVideoPreparer`, the 25MB ceiling — is genuinely reusable.

Its other half is streak behaviour, and it is not one line. Verified:

| Line | Streak coupling |
|---|---|
| 31 | Requires a `Conversation` |
| 250, 303, 417 | `AppSound.streakCaptureReady` / `streakSend` |
| 372 | Reads `streakReplayPreferenceProvider` |
| 410 | Sends through `chatControllerProvider` |
| 414 | `streakViewBudget(allowReplays:)` |
| 377-420 | Streak review sheet and copy |

A destination enum would scatter `if (isStory)` through all six points
of a module that already carries a shipped feature. Instead:

**Extract a camera module** that owns capture, review, permissions,
switching and video preparation, and *returns a result* —
`CapturedMedia(path, type, durationMs)`. It knows nothing about
destinations.

**Two thin adapters consume it.** The streak adapter does what
`_send` does today: replay preference, view budget, chat outbox. The
story adapter calls the stories repository. Each owns its own sounds and
copy.

This is more work than a flag and less risk: the streak path keeps its
exact behaviour, and neither adapter can grow branches in the other.

### 6.0 Story posting needs its own outbox decision

Calling a stories repository does **not** inherit the chat outbox. The
streak path gets retries, optimistic UI and durable queueing from
`chatControllerProvider`; a story sent through a new repository gets
none of that for free.

**Decision: stories post through a durable local queue of their own.**
A story is captured in the moment, often on poor connectivity, and a
failed upload that silently vanishes is worse here than in chat —
there is no bubble to show a retry affordance. The queue is small (one
pending item at a time is the normal case) but it must survive app
restart.

### 6.1 Photos are new work

Verified against the code, because the first draft of this spec assumed
otherwise:

- `streak_camera_screen.dart` calls `startVideoRecording()` and never
  `takePicture()`.
- `ephemeral_camera_screen.dart` is the same — also video-only.
- `streak_viewer_screen.dart` renders through `VideoPlayerController`
  and has no image branch.
- Images anywhere in chat come from `ImagePickerService`, never from an
  in-app camera.

So "photos and videos" is not free. It needs, in the camera: a
shutter/hold distinction (tap for photo, hold for video — the idiom both
reference apps use), `takePicture()`, and an image branch through the
upload path. In the viewer: an image branch with its own 5-second
timer, since a photo has no natural duration to drive the progress bar.

This is the largest single piece of new client work in the feature and
is called out here so it is planned rather than discovered.

The server-side *validation pattern* already exists —
`create_chat_media_upload_intent` takes `p_media_type` and validates
MIME and size — but story storage policies, intents, finalization and
reads are all new (§4).

### 6.1.1 Streaks want photos too, separately

Streaks are also video-only today and are due the same upgrade. That is
a SEPARATE change to a shipped feature, not part of this one:
`sendStreakMessage` hardcodes `mediaMimeType: 'video/mp4'` and sends
`mediaType: 'streak'`, its own media type with its own viewer, budget
and expiry rules. Photos there means deciding what a photo streak's view
budget and replay behaviour are — questions stories does not have.

The two are still worth building in an order that pays twice. The photo
CAPTURE work in the camera — the tap/hold shutter distinction and
`takePicture()` — is common to both, and belongs to the camera rather
than to either destination:

1. Add photo capture to the shared camera, behind the existing
   destination parameter, with the streak path unchanged (still sending
   video only).
2. Stories consume it immediately: the stories destination accepts both
   media types from day one.
3. Streak photos become a small follow-up — a media type on
   `sendStreakMessage`, an image branch in the streak viewer, and an
   answer to the view-budget question.

So the camera work is done once, stories ship complete, and streaks are
left one well-understood step from photos rather than needing the
capture layer rebuilt. What this spec does NOT do is change streak
behaviour; §6.2's rule stands.

### 6.2 The shared-camera risk

The streak camera is shared, so a careless edit breaks streaks — a
shipped feature with its own users. Its existing behaviour is covered by
tests BEFORE the destination parameter or the photo path is added.

## 7. What this does NOT do, and why

**No chat trail when a story is posted.** The game trail exists because
a game has state you must act on ("your move"). A story has no state; it
is ambient by definition. A trail would turn "I posted something casual"
into a notification-shaped object in the conversation — exactly the
pressure that makes people stop posting. The ring is the signal, and a
ring is passive.

**No reactions, no view counts beyond seen/not-seen, no highlights, no
public anything.** All of these are answers to problems a
one-person audience does not have.

**No posting limit, no retention cap.** Retention is forever unless the
author deletes. This is a promise that is easy to make now and
impossible to retract later, so it is stated explicitly rather than
defaulted into.

**No push notification on post** (§8), for the same reason as the trail.

Deferred by this revision, each with its reason in place:

- **No video downscaling in v1** — no transcoding runtime exists, and
  capture already bounds video at 60s / 25MB (§4.4).
- **No day cutoff** for `occurred_on` — midnight to midnight (§3.5).
- **No streak photo support** — sequenced to follow (§6.1.1).

## 8. Remaining decisions

Settled here rather than left to implementation:

| Question | Decision |
|---|---|
| Max video duration | 60s — `kStreakSegmentDuration`, already the capture ceiling |
| Reel fetch size | Page at 50 items, newest first. "No posting limit" must not mean an unbounded single query |
| Rings with many items | Segments cap at 12 arcs; beyond that the ring is drawn solid. Thirty hairlines read as a circle anyway |
| Push notification on post | **No.** Same reasoning as the chat trail (§7): a push makes an ambient thing demand attention |
| Realtime | Rings and view state subscribe to `story_items` / view changes for the relationship, matching how game cards refresh |
| Former partners | Access ends when the relationship does. Follows the chat-media precedent (`status = 'active' AND chat_archived_at IS NULL`), not the laxer timeline one — stories are personal media, and the timeline's own looseness is arguably a bug rather than a model to copy |
| Viewing an expired story from the calendar | Does **not** record a view (§3.4) |
| DB constraints | `media_width`/`media_height` positive when present; `duration_ms` NOT NULL for video and NULL for image; `thumbnail_key` NOT NULL; `expires_at > created_at` |

## 9. Risks

| Risk | Mitigation |
|---|---|
| An author rewrites server-owned fields | No UPDATE grant at all; RPC owns them (§3.3) |
| A direct DELETE bypasses the storage queue | No DELETE grant; `delete_story_item` tombstones and enqueues in one transaction (§4.5) |
| An author marks their own story seen | `mark_story_viewed` refuses the author (§3.4) |
| `viewed_at` leaks a partner's activity pattern | `story_views` unreadable; only derived booleans returned (§3.4) |
| Object uploaded, never finalized | Cleanup job, mirroring `cleanup_expired_chat_media_intents()` (§4.2) |
| Worker dies between upload and DB update | Lease plus deterministic output keys; `downscaled_at` alone is insufficient (§4.4) |
| Deleting an old rendition breaks a live player | Old-key deletion delayed past the signed-URL TTL (§4.4) |
| Signed URL outlives a deletion | Bounded at 600s by the TTL; accepted (§4.5) |
| A shared camera edit breaks streaks | Capture is EXTRACTED, not branched; streak adapter keeps today's behaviour (§6) |
| A story post lost on bad connectivity | Durable local queue of its own (§6.0) |
| Storage grows without bound | Images downscaled; video bounded at capture by the 60s / 25MB ceiling (§4.4) |
| A reply outlives its story | Snapshot, not live reference; `ON DELETE SET NULL` (§5.4) |
| Timezone disagreement on a story's date | `occurred_on` frozen at creation from a validated offset (§3.5) |

## 10. Testing

| Area | What must be covered |
|---|---|
| RLS and grants | An author cannot UPDATE or DELETE directly; a non-member sees nothing; `story_views` is unreadable |
| RPC contracts | `create_story_item` ignores client-supplied `expires_at` / `occurred_on` / `author_id`; `mark_story_viewed` refuses the author and the non-member |
| Storage policies | A key whose story is deleted is unreadable; a non-member cannot read any key |
| Worker idempotency | Two concurrent runs produce one rendition; a crash between upload and update leaves a recoverable state |
| Timezone boundaries | Offsets at ±840 and around local midnight file the expected `occurred_on` |
| Camera regression | Streak capture, replay preference, view budget and sounds are unchanged by the extraction — written BEFORE it |
| Reel | Segment advance, tap-left/right, hold-to-pause, image timer, backgrounding mid-item |
