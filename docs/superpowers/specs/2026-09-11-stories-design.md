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
| Only the author may delete | Enforced in RLS, not in the UI |
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
  media_url         text NOT NULL,
  thumbnail_url     text,
  media_width       int,
  media_height      int,
  duration_ms       int,

  -- The date the calendar groups by. A separate column, not a cast of
  -- created_at: a story posted at 01:00 belongs to the night before in
  -- the poster's head, and a date decided ONCE server-side beats every
  -- reader re-deriving it from a timestamp and disagreeing across
  -- timezones.
  occurred_on       date NOT NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Gates the reel, and nothing else. Set server-side at insert.
  expires_at        timestamptz NOT NULL,

  -- Soft delete. Hides the item from the reel AND the calendar at once,
  -- because both read this row.
  deleted_at        timestamptz,

  -- Null until the downscale job has run. Also the job's own idempotency
  -- marker.
  downscaled_at     timestamptz
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

### 3.3 RLS follows `timeline_events` exactly

The existing timeline policies are the precedent, and they already
encode the rule we want:

- **SELECT** — `deleted_at IS NULL` AND the caller is in the
  relationship.
- **INSERT / UPDATE / DELETE** — `auth.uid() = author_id`.

So "only the author may delete" is a database guarantee, not a hidden
button. A partner who calls the RPC directly is refused by Postgres.

`story_views` is narrower still: a viewer may insert only their own row
(`auth.uid() = viewer_id`); both partners may read views for items in
their relationship, so a poster can see who watched.

## 4. Media lifecycle

```
post ──► full quality, in the reel ──24h──► leaves the reel
                                              │
                                    (hourly job) downscale
                                              │
                                              ▼
                                    in the calendar, forever
                                              │
                                  author deletes ──► gone from both,
                                                     storage object removed
```

**Upload is two steps.** `create_story_upload_intent` mints a signed
upload URL, the client uploads, then `create_story_item` writes the row.
Two steps so that a failed upload can never leave a story row pointing
at a file that does not exist. This mirrors
`create_chat_media_upload_intent`, which exists for the same reason.

**Downscaling is an hourly cron → edge function.** It selects items
where `expires_at < now() AND downscaled_at IS NULL AND deleted_at IS
NULL`, re-encodes to a smaller long-lived rendition, swaps `media_url`,
and stamps `downscaled_at`.

The job is deliberately not load-bearing. If it never runs, the calendar
still works — it just shows full-size media and costs more storage. That
is degradation, not failure, and it is the difference between a job
whose outage is a bill and one whose outage is a bug.

**Permanent deletion.** Setting `deleted_at` hides the item everywhere
immediately. Removing the storage object is queued to the same edge
function rather than done inline, so a slow storage call cannot fail a
user-facing delete. The UI states that this cannot be undone — it is the
only irreversible action in the feature.

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

### 5.2 The reel

The streak viewer's shape: segmented progress bars across the top, tap
right for next, tap left for back, hold to pause, swipe down to dismiss.
Images hold for 5 seconds; videos run their length.

The existing streak viewer is **video-only** — it has no image branch at
all. The reel therefore reuses its structure and gesture handling but
adds image rendering. See §6, which is where the real cost of "photos
and videos" sits.

Viewing an item writes a `story_views` row. The poster's own reel shows
whether each item has been seen.

### 5.3 The calendar

The timeline screen gains stories as a third source beside events and
reminders. A date with stories shows a row saying how many; tapping it
opens that day's reel, expired items included.

This is where deletion-from-the-past lives, and it is author-only.

### 5.4 Replying

From the reel, a reply composes a chat message quoting the story item —
the same gesture both reference apps use. It lands in the couple's only
chat, which is where a reply would have gone anyway.

## 6. Reusing the streak camera, and what it does not give us

`streak_camera_screen.dart` is 760 lines of camera control, segment
recording, transcoding and outbox queueing. For **video**, all of it
applies unchanged. The single story-specific line is the last one:

```dart
// today
.sendStreakMessage(localPath: ..., durationMs: ..., viewsRemaining: ...)
```

The camera gains a destination parameter; the story path calls the
stories repository instead. Nothing about capture, permissions,
transcoding or the 25MB ceiling is duplicated or re-solved.

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

## 8. Risks

| Risk | Mitigation |
|---|---|
| Storage grows without bound | Downscaling after 24h; accepted cost, stated in §2 |
| A shared camera edit breaks streaks | Cover existing streak behaviour with tests first (§6.2) |
| Photo capture is new, not reused | Called out explicitly in §6.1 rather than assumed |
| Timezone disagreement on which day a story belongs to | `occurred_on` decided once, server-side |
| An orphaned row if upload fails | Two-step intent-then-insert |
| A storage object left behind after delete | Deletion queued to the same job, retried |
| The calendar merge slows the timeline screen | Partial indexes on both read paths (§3.1) |

## 9. Open questions

None. Every question raised during design was answered:

- Audience: partner only.
- Calendar model: separate table, merged at read (§3.1).
- Media after 24h: downscaled, kept, author-deletable (§4).
- Delete: removes from both surfaces; author only.
- Retention: forever unless deleted.
- Limits: none.
- Chat trail: no (§7).
- Rings: two, thumbnail-filled, partner's hidden when empty (§5.1).
- Camera: reuse the streak camera with a destination parameter for
  video; photo capture and image rendering are new work (§6.1).
