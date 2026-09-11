-- Stories: maintenance -- expired-intent cleanup and leased image
-- archival. Spec §4.2 (cleanup) and §4.4 (archival) are the binding
-- authority; both sections explain WHY the ordering below is not
-- optional, so this migration follows their wording closely rather
-- than inventing a shape.
--
-- The brief's three named functions, plus fail_story_archival (the
-- outbox's failure/dead-letter path spec §4.4 asks for but does not
-- name) and the story_media_processing_outbox table itself. All
-- worker-only (called by a service_role Edge Function or pg_cron,
-- never a client):
--   cleanup_expired_story_media_intents()
--   claim_story_archival_batch(p_limit int)
--   complete_story_archival(p_story_id uuid, p_new_key text)
--   fail_story_archival(p_story_id uuid, p_error_code text)
--
-- =======================================================================
-- PART 1: cleanup_expired_story_media_intents() -- spec §4.2.
-- =======================================================================
--
-- "The hourly cleanup_expired_story_media_intents() transaction finds
-- unused expired intents whose cleanup_queued_at IS NULL, re-arms their
-- key in media_deletion_queue, and stamps cleanup_queued_at. The
-- existing Edge Function performs the physical Storage API removal.
-- The intent row is deleted 24 hours after that stamp; used intents are
-- pruned 24 hours after used_at without touching their finalized
-- objects."
--
-- CRITICAL, and the reason this is not a copy-paste of
-- cleanup_expired_chat_media_intents(): that function DELETEs directly
-- from storage.objects. Supabase refuses that at the platform level for
-- any table it does not consider its own DML surface (see
-- 20260930120000's own comment: "Direct deletion from storage tables is
-- not allowed. Use the Storage API instead."). This function never
-- touches storage.objects. It only calls queue_story_media_deletion,
-- exactly as delete_story_item does, and leaves physical removal to
-- process-media-deletion-queue.
--
-- queue_story_media_deletion's ON CONFLICT DO UPDATE (20260938070000) is
-- reused rather than a bare INSERT, for the same re-arming reason
-- delete_story_item uses it: an intent's storage_key can only ever be
-- queued as part of THIS function, but calling it more than once for
-- the same key (which cannot happen here because cleanup_queued_at
-- gates re-selection -- see below) must still not multiply queue rows
-- or error against the queue's UNIQUE (bucket_id, object_name).
--
-- The stamp IS the idempotency mechanism (brief contract 1): a second
-- run's WHERE clause (cleanup_queued_at IS NULL) excludes every row the
-- first run already stamped, so the same key is never re-armed twice.
-- Without the stamp, an hourly cron running against a still-unconsumed
-- key would re-insert/re-arm it every hour forever, repeatedly pushing
-- back the drain's "safe to delete" wall-clock reasoning for no reason.
--
-- Two DISTINCT prunes, matching the spec's two different clocks:
--   - unused + queued: delete 24h after cleanup_queued_at (the stamp
--     this function itself writes).
--   - used: delete 24h after used_at, WITHOUT enqueueing anything --
--     "used intents are pruned ... without touching their finalized
--     objects" (brief contract 2). A used intent's storage_key belongs
--     to a live story_items row (media_key or thumbnail_key); queueing
--     it for deletion here would be enqueuing a finalized object for
--     removal from a code path that has no business touching it.
CREATE OR REPLACE FUNCTION public.cleanup_expired_story_media_intents()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_claimed_key text;
BEGIN
  -- Re-arm + stamp: unused, expired, not yet queued. FOR UPDATE SKIP
  -- LOCKED so this hourly job never blocks on a row create_story_item
  -- is concurrently consuming (that UPDATE also touches used_at) --
  -- skipping it here just means the row is not yet expired-and-unused
  -- from this transaction's point of view; it will be revisited (with
  -- used_at now set, so it will no longer match at all) or caught next
  -- run if it somehow still qualifies.
  --
  -- UPDATE ... RETURNING drives the enqueue loop directly, rather than
  -- a second SELECT keyed on "recently stamped" -- a time-window
  -- re-select cannot distinguish "stamped just now, by THIS run" from
  -- "stamped a few seconds ago, by the PREVIOUS run", which would
  -- re-arm the same key on every call made within that window and
  -- defeat the whole point of the stamp (brief contract 1). RETURNING
  -- names exactly the rows this statement itself just claimed, no
  -- more and no less.
  FOR v_claimed_key IN
    UPDATE public.story_media_upload_intents i
       SET cleanup_queued_at = now()
     WHERE i.id IN (
             SELECT id
               FROM public.story_media_upload_intents
              WHERE used_at IS NULL
                AND cleanup_queued_at IS NULL
                AND expires_at <= now()
              FOR UPDATE SKIP LOCKED
           )
     RETURNING i.storage_key
  LOOP
    PERFORM public.queue_story_media_deletion('story-media', v_claimed_key);
  END LOOP;

  -- Prune 1: unused rows, 24h after their cleanup stamp. Their object
  -- was already enqueued (this run or an earlier one); the row itself
  -- is now just closed audit trail.
  DELETE FROM public.story_media_upload_intents
   WHERE used_at IS NULL
     AND cleanup_queued_at IS NOT NULL
     AND cleanup_queued_at <= now() - interval '24 hours';

  -- Prune 2: used rows, 24h after used_at. NEVER enqueues -- the
  -- storage_key here is a live story's media_key or thumbnail_key
  -- (brief contract 2: "cleanup NEVER touches a used intent's
  -- finalized object").
  DELETE FROM public.story_media_upload_intents
   WHERE used_at IS NOT NULL
     AND used_at <= now() - interval '24 hours';
END;
$$;

REVOKE ALL ON FUNCTION public.cleanup_expired_story_media_intents()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_story_media_intents()
  TO service_role;

-- =======================================================================
-- PART 2: leased image archival -- spec §4.4.
-- =======================================================================
--
-- Cleanup of fix round 1's now-superseded lease columns/function/index
-- on story_items -- safe to run against either a from-round-1 database
-- (where these exist) or a from-scratch one (where DROP ... IF EXISTS
-- is a no-op). The outbox's own state/attempts/processing_started_at
-- IS the lease now; keeping both would mean two places "is this image
-- claimed" could disagree.
DROP INDEX IF EXISTS public.idx_story_archival_claim;
ALTER TABLE public.story_items
  DROP COLUMN IF EXISTS archival_lease_token,
  DROP COLUMN IF EXISTS archival_leased_at;
DROP FUNCTION IF EXISTS public.archival_lease_timeout();
--
-- FIX ROUND 1: the first version of this migration substituted two
-- lease columns on story_items for the story_media_processing_outbox
-- TABLE spec §4.4 gives verbatim, on the reasoning that no earlier task
-- created it and the brief's own six contracts are phrased in terms of
-- stories rather than outbox rows. That reasoning about the brief was
-- correct -- Task 9's brief never names the table -- but the SPEC is
-- the binding authority per this task's own instructions, and it is
-- specific in a way a bare lease-timeout column pair does not satisfy:
-- retry accounting (attempts), dead-lettering, last_error_code, and an
-- operational alert at 5 failed attempts are all named in §4.4's prose
-- and have no equivalent in a plain "leased_at + timeout" pair. §12's
-- completion criteria ("Image processing and deletion queues expose
-- backlog age and failure metrics") is what a lease-only design cannot
-- provide: a lease that only ever times out and retries forever
-- reports nothing about a job that is failing every time. This section
-- now creates the table exactly as specced.
--
-- "images are downscaled at 24h; video is not, in v1." There is no
-- transcoding runtime in this project (§4.4's opening paragraph), so
-- the outbox only ever holds IMAGE rows -- "videos get no processing
-- row" is in the spec's own prose, not an inference. Video rows are
-- still marked downscaled_at (see claim_story_archival_batch below),
-- just never through this table.
--
-- WHO INSERTS THE OUTBOX ROW: the spec says "Finalizing an image
-- inserts a story_media_processing_outbox row" -- that is
-- create_story_item, Task 5, already committed in 20260938050000.
-- DECISION: rather than editing that already-shipped, already-tested
-- function body, this migration adds an AFTER INSERT trigger on
-- story_items that inserts the outbox row for images only, with
-- available_at = NEW.expires_at, exactly matching the spec's stated
-- behaviour ("available_at = expires_at"). Reasons for the trigger
-- over editing create_story_item directly:
--   1. It is strictly ADDITIVE -- no existing statement in Task 5's
--      function changes, so Task 5's own contract test
--      (story_rpc_contracts.sql) needs no edits and is re-run unchanged
--      below to prove nothing there moved.
--   2. It fires for EVERY row-level insert into story_items, not just
--      ones that go through create_story_item -- the same "trigger,
--      not RPC-specific" posture 20260938070000 already uses for the
--      hard-delete cascade (stories_enqueue_media_on_hard_delete). If
--      a future maintenance path or migration ever inserts a
--      story_items row outside create_story_item, the outbox is still
--      seeded correctly rather than silently skipped.
--   3. It keeps the "who owns outbox seeding" logic in the same
--      migration as the table and its RPCs, one place to read rather
--      than split across Task 5's file and this one.
-- ON CONFLICT DO NOTHING on story_item_id (its PRIMARY KEY) makes this
-- idempotent against any retry path that might insert the same story
-- row id twice, though create_story_item's own idempotent-retry branch
-- (existing = true) returns before a second INSERT would ever run.
CREATE TABLE IF NOT EXISTS public.story_media_processing_outbox (
  story_item_id         uuid PRIMARY KEY REFERENCES public.story_items(id)
                          ON DELETE CASCADE,
  source_key            text NOT NULL,
  available_at          timestamptz NOT NULL,
  state                 text NOT NULL DEFAULT 'pending'
                          CHECK (state IN (
                            'pending', 'processing', 'done', 'dead_letter'
                          )),
  attempts              int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  processing_started_at timestamptz,
  completed_at          timestamptz,
  last_error_code       text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_story_media_jobs_claim
  ON public.story_media_processing_outbox (available_at, created_at)
  WHERE state = 'pending';

-- Server-side only -- "The table and its claim/finish/recovery RPCs
-- are service-role only" (§4.4). RLS on with zero policies denies every
-- row to every role that isn't the table owner; the belt-and-suspenders
-- REVOKE lives in 20260938100000_stories_table_grants.sql (replayed by
-- scripts/local_pg_grants.sql AFTER the harness's blanket grant, same
-- as story_items/story_views/story_media_upload_intents already are --
-- this is exactly the hole that bit Task 2 if it is skipped here).
ALTER TABLE public.story_media_processing_outbox ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.stories_seed_processing_outbox()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.media_type = 'image' THEN
    INSERT INTO public.story_media_processing_outbox (
      story_item_id, source_key, available_at
    ) VALUES (
      NEW.id, NEW.media_key, NEW.expires_at
    )
    ON CONFLICT (story_item_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS stories_seed_processing_outbox_after_insert
  ON public.story_items;
CREATE TRIGGER stories_seed_processing_outbox_after_insert
  AFTER INSERT ON public.story_items
  FOR EACH ROW
  EXECUTE FUNCTION public.stories_seed_processing_outbox();

-- Five-minute stale-lease recovery, per spec §4.4's own words ("five-
-- minute stale-lease recovery") -- not the earlier draft's number,
-- which happened to already be 5 minutes but is now expressed as the
-- outbox's own claim predicate rather than a column on story_items.
CREATE OR REPLACE FUNCTION public.story_archival_lease_timeout()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT interval '5 minutes';
$$;

REVOKE ALL ON FUNCTION public.story_archival_lease_timeout()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.story_archival_lease_timeout() TO service_role;

-- Five failed attempts dead-letter the job (§4.4). Named so the claim,
-- fail, and test code all read the same number from one place.
CREATE OR REPLACE FUNCTION public.story_archival_max_attempts()
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 5;
$$;

REVOKE ALL ON FUNCTION public.story_archival_max_attempts()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.story_archival_max_attempts() TO service_role;

-- ---------------------------------------------------------------------
-- claim_story_archival_batch(p_limit int)
--
-- Claims up to p_limit eligible outbox rows: state = 'pending' (fresh)
-- OR state = 'processing' with a stale processing_started_at (crashed
-- worker, brief contract 4), AND available_at <= now() (the story has
-- actually left the reel). FOR UPDATE SKIP LOCKED is what makes two
-- concurrent callers unable to claim the same row (brief contract 3):
-- a row already locked by another in-flight claim is simply skipped,
-- never waited on and never double-returned.
--
-- Each claimed row: attempts += 1, state = 'processing',
-- processing_started_at = now(). Returns the story id and the CURRENT
-- source_key (the outbox's own copy of the media_key at finalize time
-- -- stable even if a previous failed attempt somehow raced a
-- media_key change, though nothing in this feature ever changes
-- media_key before a successful archive swap).
--
-- Before claiming anything, this ALSO closes out eligible VIDEO rows
-- directly on story_items with a single UPDATE -- videos never get an
-- outbox row at all ("videos get no processing row", §4.4), so there
-- is nothing to claim for them; marking downscaled_at here is this
-- function's one allowance for the images-only reality the brief asks
-- to be documented. That UPDATE is unconditional on being called at
-- all: idempotent, touches only rows that still need it, exactly like
-- any other WHERE ... IS NULL maintenance sweep -- no lease needed
-- because there is no rendition to create and nothing to crash between.
--
-- DROP FUNCTION first: fix round 1 changes this function's OUT columns
-- (dropped archival_lease_token, which no longer exists now that the
-- lease lives in the outbox table's own state/attempts columns
-- instead of on story_items) -- Postgres refuses CREATE OR REPLACE
-- across a RETURNS TABLE column change ("cannot change return type of
-- existing function ... Row type defined by OUT parameters is
-- different"), so a from-round-1 database needs the old signature
-- dropped before this one can be created. A brand-new database has
-- nothing to drop; IF EXISTS makes this safe either way.
DROP FUNCTION IF EXISTS public.claim_story_archival_batch(int);

CREATE OR REPLACE FUNCTION public.claim_story_archival_batch(p_limit int)
RETURNS TABLE (
  story_id   uuid,
  media_key  text
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200);
BEGIN
  -- Video: mark done, no outbox row, no rendition -- there is no
  -- re-encode runtime (§4.4), so "downscaled" for video means
  -- "considered, and correctly left alone."
  UPDATE public.story_items
     SET downscaled_at = now()
   WHERE media_type = 'video'
     AND deleted_at IS NULL
     AND downscaled_at IS NULL
     AND expires_at <= now();

  -- Image: the real claim, from the outbox.
  RETURN QUERY
  UPDATE public.story_media_processing_outbox o
     SET state                 = 'processing',
         attempts              = o.attempts + 1,
         processing_started_at = now(),
         updated_at            = now()
   WHERE o.story_item_id IN (
           SELECT j.story_item_id
             FROM public.story_media_processing_outbox j
            WHERE j.available_at <= now()
              AND (
                    j.state = 'pending'
                    OR (
                         j.state = 'processing'
                         AND j.processing_started_at
                             <= now() - public.story_archival_lease_timeout()
                       )
                  )
            ORDER BY j.available_at, j.created_at
            LIMIT v_limit
              FOR UPDATE SKIP LOCKED
         )
   RETURNING o.story_item_id, o.source_key;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_story_archival_batch(int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_story_archival_batch(int)
  TO service_role;

-- ---------------------------------------------------------------------
-- fail_story_archival(p_story_id uuid, p_error_code text)
--
-- The failure path §4.4 asks for but does not name: "five failed
-- attempts dead-letter the job and raise an operational alert." Called
-- by Task 10's worker when a claimed attempt fails (download error,
-- transform error, upload error) instead of complete_story_archival.
--
-- Does NOT increment attempts again -- claim already did that at claim
-- time, so "5 failed attempts" means "the 5th claim of this row was
-- also followed by a failure report", not a double count. This
-- function only records last_error_code and, once the row's own
-- attempts has reached story_archival_max_attempts(), moves it to
-- dead_letter (state = 'dead_letter') so no future claim ever picks it
-- up again -- a dead-lettered row simply stops matching claim's WHERE
-- clause (state IN ('pending', 'processing') only). Below the
-- threshold, state reverts to 'pending' so the row is immediately
-- reclaimable rather than waiting out the stale-processing timeout for
-- no reason -- a reported failure is more informative than a silent
-- crash, so there is no reason to make it wait as long as one.
--
-- "raise an operational alert": this schema has no existing alerting
-- table/channel for any other maintenance job to hook into (the
-- deletion queue's own "monitoring alerts when the oldest pending row
-- is more than 30 minutes old", §4.5, is external monitoring against
-- media_deletion_queue's own timestamps, not a row this codebase
-- writes). Consistent with that precedent, the "alert" surface here is
-- the dead_letter state itself plus last_error_code -- both directly
-- queryable columns an external monitor (or a future admin RPC) reads,
-- exactly as media_deletion_queue's queue-age alert reads
-- requested_at/deleted_at. No new alerting machinery invented for one
-- function.
CREATE OR REPLACE FUNCTION public.fail_story_archival(
  p_story_id uuid,
  p_error_code text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempts int;
  v_dead_lettered boolean := false;
BEGIN
  IF p_story_id IS NULL THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;

  UPDATE public.story_media_processing_outbox
     SET last_error_code = p_error_code,
         state = CASE
                   WHEN attempts >= public.story_archival_max_attempts()
                     THEN 'dead_letter'
                   ELSE 'pending'
                 END,
         updated_at = now()
   WHERE story_item_id = p_story_id
  RETURNING attempts, (state = 'dead_letter') INTO v_attempts, v_dead_lettered;

  IF v_attempts IS NULL THEN
    -- No outbox row (deleted mid-flight, cascaded away, or never
    -- existed) -- §4.4's last paragraph: "a zero-row finish is treated
    -- as cancellation, not worker failure." Same posture here: nothing
    -- to fail, nothing to alert on.
    RETURN jsonb_build_object('error', false, 'found', false);
  END IF;

  RETURN jsonb_build_object(
    'error', false, 'found', true,
    'attempts', v_attempts, 'dead_letter', v_dead_lettered
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fail_story_archival(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fail_story_archival(uuid, text)
  TO service_role;

-- ---------------------------------------------------------------------
-- complete_story_archival(p_story_id uuid, p_new_key text)
--
-- Called by Task 10's worker after it has already: downloaded the
-- source at p_story_id's leased media_key, transformed it (1600px long
-- edge, quality 80 -- §4.4's numbers for the archived rendition), and
-- uploaded the result to the deterministic key story_archive_key(id)
-- with upsert: false. By the time this function runs, THE NEW OBJECT
-- ALREADY EXISTS in storage -- that ordering (create rendition FIRST)
-- is the whole point of §4.4's idempotency argument: "downscaled_at
-- alone is not idempotency if the worker dies between upload and
-- update; the lease plus deterministic keys is." If the worker dies
-- after upload but before calling this function, the object sits at
-- its deterministic key, unreferenced; the NEXT claim (once the stale
-- lease times out) re-runs the SAME upload with upsert: false, which
-- either succeeds again at the same key or fails harmlessly against an
-- identical object already there -- either way this function still
-- gets called exactly once successfully per story, and nothing is lost
-- twice.
--
-- The ordering THIS function is responsible for is the second half:
-- "conditionally swap the key only where the original key and
-- deleted_at IS NULL still match, mark downscaled_at, then enqueue the
-- old key for deletion." Concretely:
--
--   1. Row-lock the story (FOR UPDATE). This serializes against a
--      concurrent delete_story_item, a concurrent complete_story_archival
--      for the same id (should never happen given the lease, but the
--      lock makes it impossible rather than merely unlikely), and the
--      hard-delete trigger.
--   2. The conditional swap: UPDATE ... WHERE id = p_story_id AND
--      deleted_at IS NULL AND downscaled_at IS NULL. "The original key
--      ... still matches" is expressed as downscaled_at IS NULL rather
--      than re-comparing media_key, because this function's fixed
--      two-argument signature (brief) carries no p_old_key to compare
--      against -- downscaled_at IS NULL is the equivalent guard: it is
--      true iff no earlier complete_story_archival call has already
--      swapped this row's key, which is exactly the condition "another
--      worker won" needs to detect. Combined with the row lock, this
--      makes the swap happen AT MOST ONCE per story no matter how many
--      times this function is called for it.
--   3. If the UPDATE affected zero rows (spec §4.5's race: "the story
--      was deleted or another worker won"), the row is gone or already
--      archived -- either way, brief contract 5: the NEWLY PRODUCED
--      object (p_new_key, which the worker already uploaded in step
--      one, before this function was ever called) must not be
--      orphaned. It is enqueued for deletion here, using the ordinary
--      (undelayed) queue_story_media_deletion -- no live player has
--      EVER been handed a signed URL to this brand-new key, since the
--      swap that would make it reachable never committed, so there is
--      no signed-URL-TTL grace period to respect for it.
--   4. On a successful swap, the OLD media_key (captured before the
--      UPDATE overwrote it) is enqueued for deletion with
--      not_before >= now() + story_archive_ttl_seconds() (600s) --
--      "The old rendition's deletion is delayed by at least the
--      signed-URL TTL ... or a player holding a fresh URL breaks
--      mid-playback" (§4.4). And bump_story_signal fires -- "a client
--      holding the old storage key needs to refetch the row before
--      asking for its next signed URL" (§5.5).
--
-- Same "missing story" / "someone else's business" posture as the rest
-- of this feature: this is a service_role-only function with no
-- membership check, because it has no invoking client at all.
--
-- FIX ROUND 1: now also marks the outbox row 'done' on a successful
-- swap. The zero-row-affected (deleted mid-flight / lost the race)
-- branch is UNCHANGED from the original version -- the coordinator's
-- own fix instructions call this part "exactly right" and spec §4.4's
-- last paragraph endorses it ("a zero-row finish is treated as
-- cancellation, not worker failure; the generated object has already
-- been re-enqueued by the zero-row story swap"). A cascaded-away
-- outbox row (ON DELETE CASCADE from story_items) simply has nothing
-- to mark done, which is fine: nothing will ever claim it again either.
CREATE OR REPLACE FUNCTION public.complete_story_archival(
  p_story_id uuid,
  p_new_key  text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_key text;
  v_relationship_id uuid;
  v_swapped boolean := false;
BEGIN
  IF p_story_id IS NULL OR p_new_key IS NULL OR p_new_key = '' THEN
    RETURN jsonb_build_object('error', true, 'code', 'INVALID_INPUT');
  END IF;

  -- Row-lock first so the swap below and the "did it happen" check are
  -- against a single consistent snapshot, and so a concurrent
  -- delete_story_item/hard-delete cannot interleave mid-function.
  PERFORM 1 FROM public.story_items WHERE id = p_story_id FOR UPDATE;

  -- Capture the pre-swap media_key (the OLD rendition) BEFORE
  -- attempting the conditional UPDATE, so it survives even if the row
  -- vanishes or the UPDATE's own WHERE clause excludes it. A missing
  -- row simply yields v_old_key = NULL, handled below.
  SELECT media_key, relationship_id
    INTO v_old_key, v_relationship_id
    FROM public.story_items
   WHERE id = p_story_id;

  -- The conditional swap. "original key and deleted_at IS NULL still
  -- match" == downscaled_at IS NULL still holds (see the function
  -- comment above for why that is the equivalent guard given this
  -- function's fixed signature).
  UPDATE public.story_items
     SET media_key     = p_new_key,
         downscaled_at = now()
   WHERE id = p_story_id
     AND deleted_at IS NULL
     AND downscaled_at IS NULL;

  v_swapped := FOUND;

  IF NOT v_swapped THEN
    -- §4.5's race: deleted mid-flight, or another worker's call already
    -- won this row. Either way the object this call just uploaded
    -- (p_new_key) must not be orphaned -- brief contract 5. No delay:
    -- nothing has ever been able to mint a signed URL to a key that
    -- was never swapped into a readable row. KEPT UNCHANGED from the
    -- original version, per the coordinator's fix instructions.
    PERFORM public.queue_story_media_deletion('story-media', p_new_key);

    RETURN jsonb_build_object(
      'error', false, 'swapped', false, 'story_id', p_story_id
    );
  END IF;

  -- Success: enqueue the OLD rendition, delayed past the signed-URL TTL
  -- (§4.4), and bump the change signal so a client holding the old key
  -- refetches before its next signed-URL request (§5.5).
  PERFORM public.queue_story_media_deletion(
    'story-media',
    v_old_key,
    now() + make_interval(secs => public.story_archive_ttl_seconds())
  );

  IF v_relationship_id IS NOT NULL THEN
    PERFORM public.bump_story_signal(v_relationship_id);
  END IF;

  -- Mark the outbox row done. A cascaded-away row (story hard-deleted
  -- between the claim and this call) simply updates zero rows here --
  -- harmless, and nothing will claim a nonexistent row again anyway.
  UPDATE public.story_media_processing_outbox
     SET state = 'done',
         completed_at = now(),
         updated_at = now()
   WHERE story_item_id = p_story_id;

  RETURN jsonb_build_object(
    'error', false, 'swapped', true, 'story_id', p_story_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_story_archival(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_story_archival(uuid, text)
  TO service_role;

-- =======================================================================
-- PART 3: pg_cron registration.
--
-- Follows 20260936160000_arcade_expiry_jobs.sql exactly: unschedule any
-- existing job of the same name first (idempotent re-run of this
-- migration), then (re-)schedule hourly at an offset minute so this
-- doesn't collide with the arcade/word-hunt sweeps or the top-of-hour
-- crowd.
--
-- Two jobs: the cleanup transaction runs directly (it's cheap, pure
-- SQL, no external call). The archival invoke follows the existing
-- "cron calls net.http_post against an Edge Function" shape used
-- elsewhere in this codebase for outbox-style workers (e.g.
-- enqueue_message_downstream_work's net.http_post calls) -- Task 10
-- writes process-story-archival; this job is what wakes it hourly, in
-- addition to any per-insert trigger Task 10 may add. If
-- app.settings.supabase_url / service_role_key are not configured
-- (e.g. local test harness), the guarded net.http_post is skipped
-- silently, matching that same precedent, so this migration is safe to
-- apply in the test database with no pg_net configuration at all.
-- =======================================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

DO $$
DECLARE
  v_job text;
BEGIN
  FOREACH v_job IN ARRAY ARRAY[
    'cleanup-expired-story-media-intents',
    'invoke-story-archival'
  ]
  LOOP
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = v_job;
  END LOOP;
END;
$$;

SELECT cron.schedule(
  'cleanup-expired-story-media-intents',
  '33 * * * *',
  $$ SELECT public.cleanup_expired_story_media_intents(); $$
);

-- The archival invoke: a thin PL/pgSQL wrapper so cron.schedule's SQL
-- string stays a single statement, matching the existing net.http_post
-- guard pattern (only fires when both settings are configured; never
-- raises on failure -- a missed wake-up this hour is not worse than the
-- outage that caused it, and the next hourly tick retries).
CREATE OR REPLACE FUNCTION public.invoke_story_archival_worker()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supabase_url text := current_setting('app.settings.supabase_url', true);
  v_service_role_key text := current_setting('app.settings.service_role_key', true);
BEGIN
  IF v_supabase_url IS NULL OR v_service_role_key IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    PERFORM net.http_post(
      url := v_supabase_url || '/functions/v1/process-story-archival',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_role_key,
        'apikey', v_service_role_key
      ),
      body := jsonb_build_object('trigger', 'cron')
    );
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.invoke_story_archival_worker()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invoke_story_archival_worker() TO service_role;

SELECT cron.schedule(
  'invoke-story-archival',
  '38 * * * *',
  $$ SELECT public.invoke_story_archival_worker(); $$
);
