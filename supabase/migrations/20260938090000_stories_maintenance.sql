-- Stories: maintenance -- expired-intent cleanup and leased image
-- archival. Spec §4.2 (cleanup) and §4.4 (archival) are the binding
-- authority; both sections explain WHY the ordering below is not
-- optional, so this migration follows their wording closely rather
-- than inventing a shape.
--
-- Three functions, all worker-only (called by a service_role Edge
-- Function or pg_cron, never a client):
--   cleanup_expired_story_media_intents()
--   claim_story_archival_batch(p_limit int)
--   complete_story_archival(p_story_id uuid, p_new_key text)
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
-- "images are downscaled at 24h; video is not, in v1." There is no
-- transcoding runtime in this project (§4.4's opening paragraph), so
-- Task 10's worker only ever produces a new rendition for images. This
-- migration's claim function reflects that directly: it never leases a
-- video row for re-encoding work that will never happen. Instead, per
-- the brief ("A video row should be marked downscaled_at WITHOUT
-- re-encoding ... your claim function should reflect the images-only
-- reality -- read §4.4 and decide how, documenting your choice"):
--
-- DECISION: claim_story_archival_batch only ever leases and returns
-- IMAGE rows -- it is the sole source of archival work, and there is no
-- video work to hand out. Before leasing anything, it opportunistically
-- stamps downscaled_at directly on every eligible VIDEO row (expired,
-- not deleted, not yet stamped) with a plain UPDATE -- no lease, no
-- rendition, no key change, because there is nothing to swap and
-- nothing that can crash mid-flight: a single UPDATE ... WHERE
-- downscaled_at IS NULL is already atomic and idempotent on its own.
-- This keeps "downscaled" meaning "this worker's job is done with this
-- item" for BOTH media types -- which matters because nothing else in
-- the schema currently reads downscaled_at to mean "and re-encoded",
-- and a video that sat with downscaled_at forever NULL would look
-- exactly like a stuck job to any future monitoring built on this
-- column, when it is actually just... a video, correctly done.
--
-- Lease design, on story_items directly (no separate outbox table --
-- see note below):
--   archival_lease_token uuid   -- this attempt's identity, returned to
--                                   the caller so complete_story_archival
--                                   can be matched to the batch that
--                                   produced it (not strictly required by
--                                   the two-argument complete_story_archival
--                                   signature the brief fixes, but kept so
--                                   Task 10/11 have it available and so a
--                                   lease is inspectable independent of
--                                   its timestamp).
--   archival_leased_at timestamptz -- when this row was last leased.
-- A row is eligible to be (re-)leased when archival_leased_at IS NULL
-- OR archival_leased_at <= now() - archival_lease_timeout(). That
-- second branch is the crash recovery: a worker that leased a row and
-- died before calling complete_story_archival leaves
-- archival_leased_at stuck in the past forever, and the timeout is what
-- makes it reclaimable rather than parking the row (brief contract 4).
--
-- Chosen timeout: 5 minutes, matching this project's other stale-lease
-- precedent (§4.4's own outbox-shape reference: "five-minute stale-lease
-- recovery") rather than inventing a new number.
--
-- DEVIATION FROM THE SPEC'S LITERAL SHAPE, stated here rather than
-- discovered later: §4.4 shows a story_media_processing_outbox TABLE
-- with its own claim/finish/recovery RPCs, seeded by create_story_item
-- at finalize time (available_at = expires_at). That table does not
-- exist in any migration through 20260938110000 -- it was never created
-- by Tasks 1-8, and this task's brief does not ask for it either: the
-- brief's ONLY interfaces are the three functions named above, and its
-- six contracts are all phrased in terms of STORIES ("claims rows",
-- "a story deleted mid-flight", "the OLD key"), never in terms of an
-- outbox row. Retrofitting the outbox table now would mean also
-- retrofitting create_story_item (Task 5, already shipped and tested)
-- to populate it, which is out of this task's scope and would touch a
-- file this task has no mandate to touch. So the lease lives directly
-- on story_items, and eligibility ("available_at = expires_at") is
-- expressed as the equivalent existing predicate expires_at <= now() --
-- a story becomes eligible for archival at the exact instant it leaves
-- the reel, which is what §4.4's available_at = expires_at means
-- anyway. Functionally equivalent; one fewer table, one fewer place the
-- two ideas of "is this story done" (downscaled_at) and "is this story
-- claimed" (archival_leased_at) could drift apart. If a later task
-- needs the outbox table's attempt-count/dead-letter machinery for
-- images specifically, it is additive on top of this lease, not a
-- replacement for it.
ALTER TABLE public.story_items
  ADD COLUMN IF NOT EXISTS archival_lease_token uuid,
  ADD COLUMN IF NOT EXISTS archival_leased_at timestamptz;

COMMENT ON COLUMN public.story_items.archival_leased_at IS
  'Set by claim_story_archival_batch when a worker takes this image '
  'for downscaling; cleared by complete_story_archival on success. '
  'A lease older than archival_lease_timeout() is stale and '
  'reclaimable -- see claim_story_archival_batch.';

CREATE OR REPLACE FUNCTION public.archival_lease_timeout()
RETURNS interval
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT interval '5 minutes';
$$;

REVOKE ALL ON FUNCTION public.archival_lease_timeout()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.archival_lease_timeout() TO service_role;

-- Supports the claim query's WHERE clause: eligible IMAGE rows that are
-- expired, not deleted, not yet downscaled, and not under an active
-- (non-stale) lease. Partial on media_type = 'image' since video rows
-- are never claimed through this path at all.
CREATE INDEX IF NOT EXISTS idx_story_archival_claim
  ON public.story_items (expires_at)
  WHERE media_type = 'image'
    AND deleted_at IS NULL
    AND downscaled_at IS NULL;

-- ---------------------------------------------------------------------
-- claim_story_archival_batch(p_limit int)
--
-- Leases up to p_limit expired, not-yet-downscaled IMAGE rows and
-- returns enough for the worker to do its job: the story id, the
-- CURRENT media_key (the source to download and transform), and the
-- lease token. FOR UPDATE SKIP LOCKED is what makes two concurrent
-- callers unable to claim the same row (brief contract 3): a row
-- already locked by another in-flight claim (or by
-- complete_story_archival, or by delete_story_item) is simply skipped,
-- never waited on and never double-returned.
--
-- Before leasing anything, this ALSO closes out eligible VIDEO rows
-- with a single UPDATE -- see the "images-only reality" note above.
-- That UPDATE is unconditional on being called at all (it runs every
-- time this function runs, which is fine: it is idempotent and touches
-- only rows that still need it, exactly like any other WHERE ... IS
-- NULL maintenance sweep).
CREATE OR REPLACE FUNCTION public.claim_story_archival_batch(p_limit int)
RETURNS TABLE (
  story_id            uuid,
  media_key           text,
  archival_lease_token uuid
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 200);
BEGIN
  -- Video: mark done, no rendition, no lease -- there is no re-encode
  -- runtime (§4.4), so "downscaled" for video means "considered, and
  -- correctly left alone." Plain UPDATE, not FOR UPDATE SKIP LOCKED:
  -- there is nothing this could race against except itself, and two
  -- concurrent runs both issuing this UPDATE just both affect
  -- (possibly zero, possibly overlapping) rows harmlessly -- it is not
  -- a conditional swap, so there is no lost-update hazard to guard.
  UPDATE public.story_items
     SET downscaled_at = now()
   WHERE media_type = 'video'
     AND deleted_at IS NULL
     AND downscaled_at IS NULL
     AND expires_at <= now();

  -- Image: the real claim. Lease is stale-reclaimable per
  -- archival_lease_timeout() (brief contract 4).
  RETURN QUERY
  UPDATE public.story_items si
     SET archival_lease_token = gen_random_uuid(),
         archival_leased_at   = now()
   WHERE si.id IN (
           SELECT s.id
             FROM public.story_items s
            WHERE s.media_type = 'image'
              AND s.deleted_at IS NULL
              AND s.downscaled_at IS NULL
              AND s.expires_at <= now()
              AND (
                    s.archival_leased_at IS NULL
                    OR s.archival_leased_at <= now() - public.archival_lease_timeout()
                  )
            ORDER BY s.expires_at
            LIMIT v_limit
              FOR UPDATE SKIP LOCKED
         )
   RETURNING si.id, si.media_key, si.archival_lease_token;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_story_archival_batch(int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_story_archival_batch(int)
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
  -- function's fixed signature). Clears the lease on success too --
  -- the story is done, so there is nothing left to reclaim.
  UPDATE public.story_items
     SET media_key             = p_new_key,
         downscaled_at         = now(),
         archival_lease_token  = NULL,
         archival_leased_at    = NULL
   WHERE id = p_story_id
     AND deleted_at IS NULL
     AND downscaled_at IS NULL;

  v_swapped := FOUND;

  IF NOT v_swapped THEN
    -- §4.5's race: deleted mid-flight, or another worker's call already
    -- won this row. Either way the object this call just uploaded
    -- (p_new_key) must not be orphaned -- brief contract 5. No delay:
    -- nothing has ever been able to mint a signed URL to a key that
    -- was never swapped into a readable row.
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
