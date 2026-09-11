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
| No product posting limit | No daily/retained-item cap; upload endpoints still have abuse bounds (§4.2) |
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

Stories therefore keep their own table, and the calendar screen composes
them at read time. This follows the timeline screen's existing shape:
events and reminders remain separate sources and are composed in the UI.

A second benefit falls out of this. Because the reel and the calendar
read the SAME row, "deleting a story removes it from the calendar" needs
no code at all. The alternative — writing a `timeline_events` copy on
post — would need a two-row delete that could half-fail, and would turn
a day's six photos into six calendar entries.

```sql
CREATE TABLE public.story_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Stable client id makes finalize retries safe when the server committed
  -- but the response was lost.
  client_story_id   uuid NOT NULL,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  author_id         uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,

  media_type        text NOT NULL CHECK (media_type IN ('image', 'video')),

  -- KEYS, not URLs. The bucket is private and reads mint a signed URL
  -- per request (§4.1). A stored URL would either expire in the row or
  -- imply a public object.
  media_key         text NOT NULL UNIQUE,

  -- NOT NULL: the rings have nothing to draw without it, so a story is
  -- not finalized until its thumbnail exists (§4.3).
  thumbnail_key     text NOT NULL UNIQUE,

  media_width       int NOT NULL CHECK (media_width > 0),
  media_height      int NOT NULL CHECK (media_height > 0),

  -- Present for video, absent for image.
  duration_ms       int,
  CONSTRAINT story_duration_matches_type CHECK (
    (media_type = 'video' AND duration_ms BETWEEN 500 AND 60000)
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

  -- With an audience of exactly one, one server-owned boolean is enough
  -- for realtime UI. The exact timestamp remains private in story_views.
  has_been_viewed   boolean NOT NULL DEFAULT false,

  CONSTRAINT story_distinct_media_keys CHECK (media_key <> thumbnail_key),
  CONSTRAINT story_expires_in_24h CHECK (
    expires_at = created_at + interval '24 hours'
  ),
  UNIQUE (author_id, client_story_id)
);

CREATE INDEX idx_story_reel
  ON public.story_items
    (relationship_id, author_id, created_at, id)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_story_calendar
  ON public.story_items
    (relationship_id, occurred_on DESC, created_at DESC, id DESC)
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
| `story_items` | `SELECT` only, scoped to members of an ACTIVE, unarchived relationship with `deleted_at IS NULL` |
| `story_views` | nothing directly — see §3.4 |

Everything that writes goes through a `SECURITY DEFINER` RPC:

- **`create_story_item(p_relationship_id, p_client_story_id,
  p_media_intent_id, p_thumbnail_intent_id, p_media_width,
  p_media_height, p_duration_ms, p_utc_offset_minutes)`** — derives
  `author_id` and `media_type`, validates ACTIVE/unarchived relationship
  membership, consumes both matching upload intents, and sets one captured
  `v_now` as `created_at`, `v_now + interval '24 hours'` as `expires_at`,
  and `occurred_on` itself. A retry with the same `(author_id,
  client_story_id)` returns the existing item instead of posting twice.
  The client cannot supply a storage key or any server-owned field.
- **`delete_story_item`** — verifies authorship, stamps `deleted_at`,
  and enqueues the current media, thumbnail, and deterministic archive
  key in the SAME transaction, so a tombstone can never exist without
  its cleanup work. Unlike create/view, deletion does not require the
  relationship still be active: an author never loses the right to
  remove their own retained media. Enqueueing the archive key is safe
  even when it does not exist and closes a delete/worker race (§4.5).
- **`mark_story_viewed`** — see §3.4.

No `UPDATE` grant exists at all. There is no story field a client has
any business changing after the fact.

Every definer function has a fixed `search_path`, derives the actor from
`auth.uid()`, is revoked from `PUBLIC` and `anon`, and is granted only to
the role that needs it. “Missing,” “not a member,” “ended relationship,”
and “deleted” return the same unavailable result rather than forming an
existence oracle.

### 3.4 `story_views`: private timestamp, public boolean state

With an audience of one, *who* viewed is not a disclosure — there is
only one other person. The real surface is the exact `viewed_at`
timestamp, which says when your partner was awake and looking at their
phone. The product promises seen / not-seen, so that is all the client
gets.

`story_views` is therefore **not readable by clients**. The first
successful `mark_story_viewed` call does two things in the same
transaction:

1. inserts the private timestamp with `ON CONFLICT DO NOTHING`; and
2. sets `story_items.has_been_viewed = true`.

The boolean is deliberately stored on `story_items`: its UPDATE emits a
Realtime event through the table clients are already allowed to read.
Subscribing directly to `story_views` would not work because Realtime
honours its no-SELECT policy.

The client derives the labels without receiving the timestamp:

- on a partner story, `has_been_viewed` means `viewed_by_me`;
- on the author's story, it means `viewed_by_partner`.

`mark_story_viewed` derives the viewer from `auth.uid()` and returns a
generic `Story unavailable` result unless all of these hold:

- the caller belongs to the ACTIVE, unarchived relationship;
- the caller is not the author;
- the story is not deleted; and
- `expires_at > now()`.

The last condition makes the decision explicit: expired stories opened
from the calendar do not record views. The view state answers “has my
partner seen what I posted while it was in the reel,” not whether they
found it months later.

### 3.5 `occurred_on`: the poster's civil date, no cutoff

"Server-side" does not explain how the server learns the poster's local
date, and the first draft's "01:00 belongs to the night before"
smuggled in a day cutoff that was never defined.

**Decision: `create_story_item` takes `p_utc_offset_minutes`, and
`occurred_on` is the poster's civil date at `now()` — midnight to
midnight, no cutoff.**

The offset is clamped to `[-840, 840]`, following the
precedent already in the repo: the streak RPC accepts
`p_utc_offset_minutes` the same way. It is advisory, not trusted — the
worst a wrong offset does is file a story one day off in its own
couple's calendar.

The night-before idea is dropped rather than left vague. A cutoff needs
a defensible hour, would differ per couple, and buys little: a story
posted at 01:00 appearing on the new day is what every calendar app
already does, so it will not surprise anyone.

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
relationship is ACTIVE and unarchived and contains the caller. Deletion
or relationship ending therefore stops *new* reads immediately; see
§4.5 for the window on already-issued URLs.

### 4.2 Upload is intent → upload → finalize

`create_story_upload_intent(p_relationship_id, p_object_kind,
p_media_type, p_mime_type)` returns an intent id, a storage key, the
`story-media` bucket and a 15-minute expiry. `p_object_kind` is `media`
or `thumbnail`; a thumbnail must be `image/jpeg`. Main media is
`image/jpeg` or `video/mp4`. The function derives the requester and
requires an ACTIVE, unarchived relationship.

It does **not** mint a signed upload URL — the client uploads normally
and Storage RLS authorizes it. (The first draft said "signed upload
URL"; `create_chat_media_upload_intent` does no signing, and the story
version follows the same shape.)

The supporting table is server-readable only:

```sql
CREATE TABLE public.story_media_upload_intents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  requester_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  object_kind     text NOT NULL CHECK (object_kind IN ('media', 'thumbnail')),
  media_type      text NOT NULL CHECK (media_type IN ('image', 'video')),
  mime_type       text NOT NULL,
  storage_key     text NOT NULL UNIQUE,
  expires_at      timestamptz NOT NULL,
  used_at         timestamptz,
  cleanup_queued_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
```

The Storage INSERT policy permits exactly the unconsumed, unexpired key
owned by `auth.uid()`. Its membership helper is `SECURITY DEFINER`, so
the policy does not require granting clients SELECT on the intent table.
Uploads use `upsert: false`.

“No posting limit” means no product/day/retention cap, not an unbounded
storage-write endpoint. `create_story_upload_intent` permits at most 120
intent calls per user per one-hour server window and refuses when that
user already has 20 unconsumed, unexpired story intents. Since every
story uses two intents, this still allows 60 finalized stories per hour
while bounding abandoned-upload abuse. Rate-limit state is server-only and a rejected
call returns a retryable `rate_limited` code.

`create_story_item` then finalizes: it consumes the intent, validates
**both** intents under `FOR UPDATE`, verifies their requester and
relationship match, checks that both objects exist, validates MIME and
size from `storage.objects`, and writes the row atomically. Limits are:

| Object | Accepted form | Maximum |
|---|---|---|
| Main image | JPEG, prepared to at most 2560px on the long edge | 5MB |
| Main video | MP4, declared duration 500ms–60s | 25MB |
| Thumbnail | JPEG, 400px long edge, quality 75 | 800KB |

The 25MB and declared-duration checks are authoritative for the client
contract. V1 has no server video probe, so a modified client could lie
about duration; it still cannot exceed the server-checked byte ceiling.
Width, height and duration are layout metadata, not authorization data.

**The failure mode this creates** is the opposite of an orphaned row: an
object uploaded but never finalized. The repo contains
`cleanup_expired_chat_media_intents()`, but it directly deletes from
`storage.objects`; later media work established that Supabase requires
the Storage API for physical deletion. Stories must not copy that part.

The hourly `cleanup_expired_story_media_intents()` transaction finds
unused expired intents whose `cleanup_queued_at IS NULL`, re-arms their
key in `media_deletion_queue`, and stamps `cleanup_queued_at`. The
existing Edge Function performs the physical Storage API removal. The
intent row is deleted 24 hours after that stamp; used intents are pruned
24 hours after `used_at` without touching their finalized objects. This
keeps a short audit window without repeatedly re-arming the same key.

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
  a declared 60 seconds and a server-checked 25MB. That bounds each
  object, not aggregate storage: unlimited permanent video still grows
  without bound, and v1 accepts and measures that cost (§9).

Choosing a transcoding runtime is real work with its own operational
surface, and it is not on this feature's critical path. Deferring it is
stated here rather than discovered when the job is written.

Finalizing an image inserts a `story_media_processing_outbox` row with
`available_at = expires_at`; videos get no processing row. The outbox
uses the existing chat-worker shape: `pending / processing / done /
dead_letter`, `attempts`, `processing_started_at`, `last_error_code`, and
five-minute stale-lease recovery. The hourly worker claims eligible rows
with `FOR UPDATE SKIP LOCKED`; five failed attempts dead-letter the job
and raise an operational alert.

```sql
CREATE TABLE public.story_media_processing_outbox (
  story_item_id        uuid PRIMARY KEY REFERENCES public.story_items(id)
                         ON DELETE CASCADE,
  source_key           text NOT NULL,
  available_at         timestamptz NOT NULL,
  state                text NOT NULL DEFAULT 'pending'
                         CHECK (state IN (
                           'pending', 'processing', 'done', 'dead_letter'
                         )),
  attempts             int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  processing_started_at timestamptz,
  completed_at         timestamptz,
  last_error_code      text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_story_media_jobs_claim
  ON public.story_media_processing_outbox (available_at, created_at)
  WHERE state = 'pending';
```

The table and its claim/finish/recovery RPCs are service-role only. If a
hard delete cascades the job away while an Edge Function is working, a
zero-row finish is treated as cancellation, not worker failure; the
generated object has already been re-enqueued by the zero-row story swap.

The output key is deterministic (`story-archive/<story-id>.jpg`) and the
ordering is: **create/upsert the rendition, conditionally swap the key
only where the original key and `deleted_at IS NULL` still match, mark
`downscaled_at`, then enqueue the old key for deletion**. If the
conditional update affects zero rows, the story was deleted or another
worker won; the generated key is enqueued instead. `downscaled_at` alone
is not idempotency if the worker dies between upload and update.

The old rendition's deletion is delayed by at least the signed-URL TTL
(§4.1), or a player holding a fresh URL breaks mid-playback.

### 4.5 Deletion

`delete_story_item` row-locks the story, verifies authorship, stamps
`deleted_at`, and enqueues its current media, thumbnail, and deterministic
`story-archive/<story-id>.jpg` key in one transaction. It is idempotent:
deleting an already-deleted story returns success and re-arms cleanup for
the same three keys rather than multiplying queue rows.

Deferring the physical delete is safe because the bucket is private and
its SELECT policy requires a live story row: new requests fail
immediately. What survives is any signed URL already issued, for up to
its 600-second TTL. That is the accepted window, and it is bounded by
the TTL rather than by the queue's latency.

Physical removal reuses the existing `media_deletion_queue` and its
10-minute `process-media-deletion-queue` drain. Failed rows remain
unstamped and are retried on the next drain; there is no invented
backoff/dead-letter state in that existing queue. Monitoring alerts when
the oldest pending row is more than 30 minutes old.

The existing queue gains `not_before timestamptz NOT NULL DEFAULT now()`
and the drain adds `not_before <= now()` to its pending query.
Normal story deletion uses the default. Downscale replacement uses a
new internal `queue_media_deletion_after(...)` helper with `not_before`
at least 600 seconds in the future, so an already-issued URL can finish.

The story helper must not use the queue's current `ON CONFLICT DO
NOTHING`. On conflict it sets `deleted_at = NULL`, refreshes
`requested_at`, and keeps the earlier `not_before`. Otherwise this race
leaks an object: deletion queues the not-yet-created deterministic key,
the drain stamps that no-op complete, then an in-flight worker uploads
the key and cannot queue it again. Re-arming makes the worker's
post-upload enqueue authoritative. Deleting a nonexistent key remains a
safe Storage no-op.

`ON DELETE CASCADE` does not call `delete_story_item`. A `BEFORE DELETE`
trigger on `story_items` therefore enqueues the current media and
thumbnail plus the deterministic archive key for hard deletes caused by
relationship deletion, account deletion, or privileged maintenance. The
re-arming upsert and unique `(bucket_id, object_name)` constraint make
this safe beside the soft-delete path and an in-flight worker.

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

After a partner's active item renders successfully, the client calls
`mark_story_viewed`; its first successful call records the private view
and flips the public boolean (§3.4). Merely opening the screen, a failed
media load, the author's own preview, and expired calendar playback do
not count. The poster's own reel shows whether each item has been seen.

### 5.3 The calendar

The timeline screen gains stories as a third source beside events and
reminders. A date with stories shows a row saying how many; tapping it
opens that day's reel, expired items included.

This is where deletion-from-the-past lives, and it is author-only.

### 5.4 Replying: live link, textual snapshot

Replies today reference another **message**: `reply_to_message_id` and
`quoted_text`. There is no way to quote a story, so this is not
implementable without a schema change.

**Decision: `messages` gains `story_item_id uuid NULL REFERENCES
story_items(id) ON DELETE SET NULL`. Existing `quoted_text` is the durable
snapshot and is server-normalized to `Photo story` or `Video story`.**

The previous revision proposed snapshotting `thumbnail_key`, but that
contradicted deletion: the quote would point at the same thumbnail the
story deletion queue removes. Copying it would create a second retained
piece of story media with a different deletion promise. V1 therefore
snapshots text, not media.

- While the story exists, the quote may render its live thumbnail after
  the normal story authorization check.
- After soft deletion, the message still reads “Photo story” or “Video
  story,” but tap-through reports “Story no longer available.”
- Expiry alone does not break the link; an expired-but-kept story opens
  in that day's calendar reel.
- A hard cascade sets `story_item_id` to null and leaves `quoted_text`.

Messages are inserted directly today, not through a story-reply RPC. A
`BEFORE INSERT` trigger therefore handles the trust seam: when
`story_item_id` is present it requires a live story in the same ACTIVE,
unarchived relationship, requires the sender to be a member, and
overwrites `quoted_text` from the story's media type. A mismatch raises
the same generic unavailable error. This preserves the existing chat
outbox and prevents quoting another couple's story.

### 5.5 Read and refresh contracts

The UI does not fetch an unlimited relationship history and group it in
memory. These are the read contracts:

| Read | Contract |
|---|---|
| `get_story_ring_summary` | Active-story counts, unviewed partner count, and newest thumbnail for each author |
| `list_active_story_items` | One author's `expires_at > now()` items, oldest first for playback, keyset pages of 50 by `(created_at, id)` |
| `list_story_day_counts` | One row per `occurred_on` with count, bounded by requested `[start_on, end_on]` |
| `list_story_day_items` | Non-deleted items for one date, oldest first for playback, keyset pages of 50 |

Reads require the requested relationship to be ACTIVE and unarchived.
The server caps `p_limit` to 50 even if a modified client asks for more.
These SQL RPCs are `SECURITY INVOKER`, so `story_items` RLS remains the
authorization authority rather than being reimplemented four times.
The active reel opens at the oldest active item; viewed segments are
still shown faded, not skipped. It never uses offset pagination: inserts
during viewing append rather than duplicate or skip items. Calendar day
playback obtains later pages as the viewer advances rather than loading
an unbounded day at open.

Realtime is a refetch signal, not a second source of truth. A private,
server-written `story_change_signals(relationship_id, version,
updated_at)` row is bumped after story insert, soft delete, first view, or
a successful archive-key swap.
Active relationship members may SELECT/subscribe but not write it. This
solves two RLS problems in the previous revision: clients cannot
subscribe to private `story_views`, and a soft-deleted `story_items` row
may become invisible before its UPDATE can be delivered. On a signal,
the client invalidates ring summary and the currently visible reel/day.
It also refetches on app resume and pull-to-refresh. The archive swap
must signal because a client holding the old storage key needs to refetch
the row before asking for its next signed URL.

```sql
CREATE TABLE public.story_change_signals (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  version         bigint NOT NULL DEFAULT 1,
  updated_at      timestamptz NOT NULL DEFAULT now()
);
```

Only the mutation RPCs/internal trigger may INSERT or UPDATE this table.
Its SELECT policy repeats the ACTIVE/unarchived membership predicate.
All four read RPCs and the signal table revoke default function/table
access and grant only the minimum authenticated SELECT/EXECUTE rights.

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
switching and media preparation, and *returns a result* —
`CapturedMedia(path, type, width, height, durationMs, thumbnailPath)`.
It knows nothing about destinations. Main images are orientation-corrected
JPEGs capped at 2560px / 5MB; every result already includes the 400px
JPEG thumbnail required by finalization.

**Two thin adapters consume it.** The streak adapter does what
`_send` does today: replay preference, view budget, chat outbox. The
story adapter calls the stories repository. Each owns its own sounds and
copy.

This is more work than a flag and less risk: the streak path keeps its
exact behaviour, and neither adapter can grow branches in the other.

### 6.1 Story posting outbox

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

The queue reuses the encrypted SQLite/cache patterns behind the chat
outbox but has a separate `story_outbox` record:

```
clientStoryId, relationshipId, localMediaPath, localThumbnailPath,
mediaType, mimeType, width, height, durationMs, utcOffsetMinutes,
state, attempts, nextAttemptAt, lastErrorCode, createdAt
```

States are `queued`, `uploading_media`, `uploading_thumbnail`,
`finalizing`, and `failed_permanent`. Network failures use the chat
outbox's bounded exponential retry pattern. An expired intent causes a
new pair of intents and re-upload; the server cleanup removes the old
unused objects. `clientStoryId` makes a lost finalize response safe to
retry.

The Mine ring shows a local pending tile with progress. A permanent
failure exposes Retry and Discard; it never silently disappears. Local
files remain in app-private storage until success or explicit discard,
and logout/account removal clears them. Finalization time is posting
time: it sets the 24-hour window and `occurred_on`, even if an offline
capture waited in the queue.

### 6.2 Photos are new work

Verified against the code, because the first draft of this spec assumed
otherwise:

- `streak_camera_screen.dart` calls `startVideoRecording()` and never
  `takePicture()`.
- `ephemeral_camera_screen.dart` is the same — also video-only.
- `streak_viewer_screen.dart` renders through `VideoPlayerController`
  and has no image branch.
- Images anywhere in chat come from `ImagePickerService`, never from an
  in-app camera.

So "photos and videos" is not free. The gesture state machine is fixed,
not left to whichever recognizer is convenient: release before a 300ms
hold threshold takes a photo; crossing the threshold starts video;
release stops it; recordings shorter than 500ms are discarded. Only one
capture operation may be in flight. This needs `takePicture()`, image
orientation/size preparation, and an image review branch. The reel needs
an image branch with its own 5-second timer, since a photo has no natural
duration to drive the progress bar.

This is the largest single piece of new client work in the feature and
is called out here so it is planned rather than discovered.

The server-side *validation pattern* already exists —
`create_chat_media_upload_intent` takes `p_media_type` and validates
MIME and size — but story storage policies, intents, finalization and
reads are all new (§4).

### 6.3 Streaks want photos too, separately

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

1. Extract the destination-neutral capture module and cover the existing
   streak adapter before changing capture gestures.
2. Add photo results to that module; the story adapter accepts both media
   types while the streak adapter continues to request video only.
3. Streak photos become a small follow-up — a media type on
   `sendStreakMessage`, an image branch in the streak viewer, and an
   answer to the view-budget question.

So the camera work is done once, stories ship complete, and streaks are
left one well-understood step from photos rather than needing the
capture layer rebuilt. What this spec does NOT do is change streak
behaviour; §6.4's rule stands.

### 6.4 The shared-camera risk

The streak camera is shared, so a careless edit breaks streaks — a
shipped feature with its own users. Its existing behaviour is covered by
tests BEFORE extraction or the photo path is added. Contract tests then
run unchanged against the streak adapter after each extraction step.

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
- **No streak photo support** — sequenced to follow (§6.3).

## 8. Remaining decisions

Settled here rather than left to implementation:

| Question | Decision |
|---|---|
| Max video duration | 60s — `kStreakSegmentDuration`, already the capture ceiling |
| Reel fetch size | Page at 50 items, oldest first for playback. "No posting limit" must not mean an unbounded single query |
| Rings with many items | Segments cap at 12 arcs; beyond that the ring is drawn solid. Thirty hairlines read as a circle anyway |
| Push notification on post | **No.** Same reasoning as the chat trail (§7): a push makes an ambient thing demand attention |
| Posting limit | No user-facing daily or retained-item cap; upload intents have the operational abuse bounds in §4.2 |
| Rollout flag | `stories` gates the rings/camera and new upload intents. Finalization of an already-issued intent, reads and author deletion remain enabled, so a rollout change neither strands an in-flight upload nor traps retained data |
| Realtime | Subscribe to the read-safe `story_change_signals` row, then refetch canonical reads (§5.5) |
| Former partners | Playback/list access ends when the relationship does. Follows the chat-media precedent (`status = 'active' AND chat_archived_at IS NULL`), not the laxer timeline one. The author-only delete RPC remains available so ending a relationship never removes the right to erase one's own media |
| Viewing an expired story from the calendar | Does **not** record a view (§3.4) |
| DB constraints | Dimensions and thumbnail are required; video duration is 500ms–60s and image duration is NULL; media keys are distinct/unique; expiry is exactly 24h; `(author_id, client_story_id)` is unique |

## 9. Risks

| Risk | Mitigation |
|---|---|
| An author rewrites server-owned fields | No UPDATE grant at all; RPC owns them (§3.3) |
| A direct DELETE bypasses the storage queue | No DELETE grant; `delete_story_item` tombstones and enqueues in one transaction (§4.5) |
| An author marks their own story seen | `mark_story_viewed` refuses the author (§3.4) |
| `viewed_at` leaks a partner's activity pattern | `story_views` unreadable; only derived booleans returned (§3.4) |
| Object uploaded, never finalized | Intent cleanup queues the key for the Storage API worker; it does not copy chat's direct `storage.objects` deletion (§4.2) |
| A modified client mints unlimited upload keys | 120 intent calls/hour and no more than 20 live unused intents per user (§4.2) |
| Worker dies between upload and DB update | Lease plus deterministic output keys; `downscaled_at` alone is insufficient (§4.4) |
| Deleting an old rendition breaks a live player | Old-key deletion delayed past the signed-URL TTL (§4.4) |
| Signed URL outlives a deletion | Bounded at 600s by the TTL; accepted (§4.5) |
| A shared camera edit breaks streaks | Capture is EXTRACTED, not branched; streak adapter keeps today's behaviour (§6) |
| A story post lost on bad connectivity | Durable, idempotent local queue with visible retry/discard (§6.1) |
| Storage grows without bound | Images downscaled; videos are byte-bounded per item; aggregate bytes/day and backlog are monitored and the permanent-retention cost is explicitly accepted (§4.4) |
| A reply outlives its story | Durable textual snapshot plus nullable live reference; `ON DELETE SET NULL` (§5.4) |
| Timezone disagreement on a story's date | `occurred_on` frozen at creation from a clamped offset (§3.5) |

## 10. Testing

| Area | What must be covered |
|---|---|
| RLS and grants | An author cannot INSERT, UPDATE or DELETE directly; ended-relationship members and non-members see nothing; `story_views` and upload intents are unreadable |
| RPC contracts | Finalization derives every server field, atomically consumes both intents, validates stored objects, and a repeated `client_story_id` returns one story |
| View contract | Self/non-member/expired views are refused; the first partner view records one private row, flips one boolean and bumps one signal; repeats are no-ops |
| Storage policies | Only an owned live intent can upload; live members can read finalized keys; deleted/ended/non-member reads fail; unsigned/public reads fail |
| Intent cleanup | Half-uploaded and fully-uploaded-but-unfinalized pairs are removed after expiry; used live objects are untouched |
| Abuse bounds | Intent rate and outstanding-count limits are atomic under concurrent calls and do not charge idempotent finalization retries |
| Worker idempotency | Two concurrent runs produce one rendition; crash at every boundary recovers; deletion racing the swap cannot resurrect media |
| Deletion | Soft delete queues current keys once; relationship/account cascades fire the hard-delete trigger; delayed old-key deletion respects `not_before` |
| Timezone boundaries | Offsets at ±840 and around local midnight file the expected `occurred_on` |
| Camera regression | Streak capture, replay preference, view budget and sounds are unchanged by the extraction — written BEFORE it |
| Capture | Tap/hold threshold races, only-one-operation guard, photo orientation, image limits, thumbnail generation, 500ms/60s video bounds |
| Story outbox | Restart recovery, expired-intent restart, lost-finalize response, transient retry, permanent failure, retry/discard and local-file cleanup |
| Reel | Failed media does not mark viewed; segment advance, tap-left/right, hold-to-pause, image timer, backgrounding and pagination |
| Reply | Trigger rejects cross-relationship/deleted stories, normalizes quote text, existing chat outbox retries, and deleted/hard-deleted display states remain coherent |
| Refresh | Insert, first view, soft delete and archive-key swap bump the signal; subscribers refetch; app resume and pull-to-refresh recover missed events |

## 11. Implementation order

Each step leaves a testable vertical seam and avoids changing the shipped
camera before its current behaviour is locked down.

1. **Database and storage foundation** — `stories` feature flag,
   `story_items`, `story_views`,
   upload intents, processing outbox, change signals, private bucket,
   grants/RLS, hardened helpers and the four read RPCs.
2. **Mutation contracts** — upload intent, idempotent finalize, view and
   delete RPCs; orphan cleanup; hard-delete trigger; extend the generic
   deletion queue with `not_before`.
3. **Repository and models** — story model, ring/day reads, signed-URL
   cache, posting coordinator and Realtime signal subscription.
4. **Story outbox** — encrypted local record, retry state machine,
   progress/retry/discard UI and startup/resume flushing.
5. **Streak regression harness** — characterize current camera capture,
   review, sounds, replay preference, view budget and outbox handoff.
6. **Capture extraction** — destination-neutral video result first; run
   the unchanged streak contract after every move.
7. **Photo capture** — tap/hold state machine, image preparation,
   thumbnail generation and story adapter; streak remains video-only.
8. **Rings and reel** — summary row, pagination, mixed-media controller,
   gestures, lifecycle and view marking after successful render.
9. **Calendar** — month counts, per-day row/reel, author-only deletion,
   refresh/error states and expired playback.
10. **Replies** — message column and validation trigger, pending-send
    plumbing, quote rendering and live/unavailable tap-through.
11. **Image archival and operations** — worker, stale-lease recovery,
    delayed old-object removal, queue-age alert and aggregate storage
    metrics.

## 12. Implementation-ready acceptance criteria

The feature is complete only when all of these hold:

- A photo or video queued offline posts exactly once after connectivity
  returns, survives restart, and visibly fails if it cannot be posted.
- New stories are visible only to the two members of the active,
  unarchived relationship; access ends immediately when that relationship
  ends or the author deletes the story.
- The partner's first successful active-reel render changes seen state;
  no caller can retrieve the exact view timestamp.
- The reel expires from server time without a job, while the same row
  remains playable from its calendar day.
- Story deletion hides every surface synchronously and queues every
  object even when deletion comes from an account/relationship cascade.
- Rings, calendar counts and reels recover from missed Realtime events by
  refetching canonical server reads.
- Story replies cannot cross relationships and remain understandable
  after their story becomes unavailable.
- Existing streak capture/view/replay behaviour passes unchanged.
- Image processing and deletion queues expose backlog age and failure
  metrics; a failed maintenance job affects cost, never reel expiry or
  logical deletion.
